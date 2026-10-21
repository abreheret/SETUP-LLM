#!/usr/bin/env python3
"""Construit /Users/amaury/DEV/SETUP-LLM/webui : copie de l'interface web integree a llama-server,
avec une entree "Documentation" dans le menu et la doc clients (CLIENTS.md, clients/*.md).

La doc est convertie en HTML et integree a index.html : llama-server ne sert sans mot de passe que les
fichiers de son interface integree, un fichier docs/*.html ajoute demanderait la cle.

llama-server sert ensuite ce dossier avec --path (voir start.sh), a la place de son interface integree.

Usage : uv run --no-project --with markdown python /Users/amaury/DEV/SETUP-LLM/tools/build-webui.py

- Les fichiers de l'interface sont telecharges depuis le serveur qui tourne (http://127.0.0.1:8080),
  seulement s'il sert son interface integree. S'il sert deja la copie (marqueur present) et que la
  version de llama-server n'a pas change, la copie existante est reutilisee : seules l'injection et
  la doc sont refaites.
- webui/.llama-version enregistre la version copiee. start.sh n'ajoute --path que si elle correspond
  a la version installee : apres une mise a jour de llama.cpp, le serveur repart sur l'interface
  integree, et il suffit de relancer ce script puis de redemarrer le service.
"""
import gzip
import hashlib
import html
import json
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

import markdown

ROOT = Path("/Users/amaury/DEV/SETUP-LLM")
OUT = ROOT / "webui"
SRC = ROOT / "webui-src"
SERVER = "http://127.0.0.1:8080"
LLAMA_SERVER = "/opt/homebrew/bin/llama-server"
MARKER = "setup-llm-docs-inject"

# Pages de doc : (fichier source, identifiant, titre dans le menu).
DOCS = [
    ("CLIENTS.md", "general", "Guide général"),
    ("clients/OPENCODE.md", "opencode", "OpenCode"),
    ("clients/QWEN-CODE.md", "qwen-code", "Qwen Code"),
    ("clients/HERMES.md", "hermes", "Hermes Agent"),
]


def llama_version():
    out = subprocess.run([LLAMA_SERVER, "--version"], capture_output=True, text=True)
    return (out.stdout + out.stderr).strip().splitlines()[0]


def fetch(path):
    req = urllib.request.Request(SERVER + "/" + path, headers={"Accept-Encoding": "gzip"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
        if r.headers.get("Content-Encoding") == "gzip":
            data = gzip.decompress(data)
        return data


def asset_refs(name, data):
    """Chemins relatifs a la racine references par un fichier de l'interface."""
    text = data.decode("utf-8", "replace")
    base = name.rsplit("/", 1)[0] + "/" if "/" in name else ""
    refs = set()
    if name.endswith(".html"):
        for ref in re.findall(r'(?:href|src)="([^"#?]+)"', text):
            if not ref.startswith(("http:", "https:", "data:", "#")):
                refs.add(ref)
    elif name.endswith((".js", ".css", ".webmanifest")):
        for ref in re.findall(r'["\'(](\.{0,2}/?[A-Za-z0-9_./-]+\.(?:js|css|png|svg|ico|json|webmanifest|woff2?|wasm))["\')]', text):
            refs.add(ref)
    if name == "sw.js":
        # Service worker : fichiers precaches et module workbox charge par define(["./workbox-..."]).
        refs.update(re.findall(r'url:"([^"]+)"', text))
        refs.update(m + ".js" for m in re.findall(r'define\(\["(\./[^"]+)"', text))
    # Dans le JS, un chemin relatif peut viser le dossier du fichier ou la racine de la page :
    # les deux sont essayes, ceux qui n'existent pas sont ignores par copy_ui.
    out = set()
    for ref in refs:
        if ref.startswith("/"):
            candidates = [ref.lstrip("/")]
        else:
            rel = ref.removeprefix("./")
            candidates = [str(Path(base + rel)), str(Path(rel))]
        for path in candidates:
            if path in (".", ""):
                path = "index.html"
            if not path.startswith("..") and "//" not in path:
                out.add(path)
    return out


def copy_ui(dest):
    todo, seen, missing = ["index.html"], set(), 0
    while todo:
        name = todo.pop()
        if name in seen:
            continue
        seen.add(name)
        try:
            data = fetch(name)
        except urllib.error.HTTPError:
            # Chemin candidat qui n'existe pas : llama-server repond 401 (route inconnue, cle exigee).
            if name != "index.html":
                missing += 1
                continue
            raise
        target = dest / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        todo.extend(asset_refs(name, data) - seen)
    print(f"  {len(seen) - missing} fichiers copies ({missing} chemins candidats absents)")


def docs_data():
    """Doc clients en HTML, pour window.__SETUP_LLM_DOCS (voir webui-src/inject.js)."""
    ids = {Path(src).name: page_id for src, page_id, _ in DOCS}
    pages = []
    for src, page_id, title in DOCS:
        body = markdown.markdown((ROOT / src).read_text(), extensions=["tables", "fenced_code", "toc", "sane_lists"])
        # Liens entre fichiers .md : doc:<id>[#ancre], interceptes par inject.js.
        body = re.sub(
            r'href="(?:[^"]*/)?([A-Za-z0-9_-]+\.md)(#[^"]*)?"',
            lambda m: f'href="doc:{ids[m.group(1)]}{m.group(2) or ""}"' if m.group(1) in ids else m.group(0),
            body,
        )
        pages.append({"id": page_id, "title": html.escape(title), "html": body})
    return {"css": (SRC / "docs.css").read_text(), "pages": pages}


def inject(index):
    text = index.read_text()
    text = re.sub(r'\n?<script id="%s">.*?</script>' % MARKER, "", text, flags=re.S)
    data = json.dumps(docs_data(), ensure_ascii=False).replace("</", "<\\/")
    js = (SRC / "inject.js").read_text()
    tag = f'<script id="{MARKER}">\nwindow.__SETUP_LLM_DOCS = {data};\n{js}</script>'
    index.write_text(text.replace("</body>", tag + "\n</body>", 1))
    print(f"Entree Documentation et {len(DOCS)} pages de doc injectees")


def patch_service_worker(dest):
    """Met a jour l'empreinte de l'index dans le precache du service worker : sans cela, un navigateur
    deja venu garderait en cache l'index d'origine, sans l'entree Documentation."""
    sw = dest / "sw.js"
    if not sw.exists():
        return
    rev = hashlib.md5((dest / "index.html").read_bytes()).hexdigest()
    text, n = re.subn(r'\{url:"\./",revision:"[0-9a-f]*"\}', '{url:"./",revision:"%s"}' % rev, sw.read_text())
    sw.write_text(text)
    print("Service worker : empreinte de l'index mise a jour" if n else "Service worker : entree de l'index introuvable")


def main():
    version = llama_version()
    serving_copy = MARKER in fetch("index.html").decode("utf-8", "replace")
    stamp = OUT / ".llama-version"
    have_copy = (OUT / "index.html").exists() and stamp.exists() and stamp.read_text().strip() == version

    if serving_copy and not have_copy:
        sys.exit(
            "Le serveur sert une copie de l'interface d'une autre version de llama-server.\n"
            "Supprimez webui/.llama-version, redemarrez le service (interface integree), puis relancez ce script."
        )
    if not serving_copy:
        print(f"Copie de l'interface integree ({version})")
        tmp = OUT.with_name("webui.tmp")
        shutil.rmtree(tmp, ignore_errors=True)
        tmp.mkdir()
        copy_ui(tmp)
        shutil.rmtree(OUT, ignore_errors=True)
        tmp.rename(OUT)
        stamp.write_text(version + "\n")
    else:
        print("Le serveur sert deja la copie, version inchangee : copie reutilisee")

    shutil.rmtree(OUT / "docs", ignore_errors=True)  # ancienne version : pages docs/*.html
    inject(OUT / "index.html")
    patch_service_worker(OUT)
    print(f"Termine : {OUT}")


if __name__ == "__main__":
    main()
