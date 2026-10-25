#!/usr/bin/env python3
"""Serveur MCP (stdio, JSON-RPC une ligne par message) des outils web de l'interface web.

Noms vus par le modele : web_search et web_fetch_page (llama-server prefixe le nom du serveur, "web").
- search : recherche via SearXNG (conteneur setup-llm-searxng, reseau Docker llm-web).
- fetch_page : lit une page web et renvoie son texte principal (trafilatura), par tranches.

Tourne dans le conteneur setup-llm-web, qui a acces a Internet mais pas a /work (fichiers produits).
llama-server le lance avec "docker exec -i setup-llm-web python /app/server.py" (start.sh,
tools-runtime/mcp.json). Les adresses non publiques (reseau local du Mac, localhost, Docker) sont
refusees, redirections comprises, pour que le modele ne puisse pas viser le LAN.
"""
import ipaddress
import json
import socket
import sys
from urllib.parse import urljoin, urlparse

import httpx
import trafilatura

SEARXNG = "http://setup-llm-searxng:8080/search"
MAX_BYTES = 5_000_000
CHUNK = 20_000
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36"

TOOLS = [
    {
        "name": "search",
        "description": (
            "Search the web (Google, Bing, DuckDuckGo... via SearXNG). Returns titles, URLs, snippets and "
            "dates. Use it for current events or anything after your training data, then read the most "
            "relevant results with web_fetch_page. Cite the URLs you rely on."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
                "max_results": {"type": "integer", "description": "Number of results, 1-20 (default 8)"},
                "time_range": {
                    "type": "string",
                    "enum": ["day", "week", "month", "year"],
                    "description": "Only results from this period (optional)",
                },
                "language": {"type": "string", "description": "Language code such as fr or en (optional)"},
                "news": {"type": "boolean", "description": "Search news sites only (default false)"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "fetch_page",
        "description": (
            "Download a web page (http or https) and return its main text as Markdown, without menus or ads. "
            f"Long pages are returned in chunks of {CHUNK} characters: call again with the given start "
            "value to read more."
        ),
        "inputSchema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "Page URL"},
                "start": {"type": "integer", "description": "Character offset to start from (default 0)"},
            },
            "required": ["url"],
        },
    },
]


class ToolError(Exception):
    pass


def check_url(url):
    """Refuse tout ce qui n'est pas une adresse Internet publique en http ou https."""
    parts = urlparse(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise ToolError(f"URL refusee (http ou https uniquement) : {url}")
    try:
        infos = socket.getaddrinfo(parts.hostname, parts.port or (443 if parts.scheme == "https" else 80))
    except socket.gaierror as e:
        raise ToolError(f"nom introuvable : {parts.hostname} ({e})")
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if not ip.is_global:
            raise ToolError(f"adresse non publique refusee : {parts.hostname} ({ip})")


def web_search(query, max_results=8, time_range=None, language=None, news=False):
    params = {"q": query, "format": "json"}
    if time_range:
        params["time_range"] = time_range
    if language:
        params["language"] = language
    if news:
        params["categories"] = "news"
    r = httpx.get(SEARXNG, params=params, timeout=30)
    r.raise_for_status()
    data = r.json()
    results = data.get("results", [])[: max(1, min(int(max_results), 20))]
    if not results:
        hints = [f"{e[0]} : {e[1]}" for e in data.get("unresponsive_engines", [])]
        return "Aucun resultat." + (" Moteurs indisponibles : " + ", ".join(hints) if hints else "")
    lines = []
    for i, res in enumerate(results, 1):
        date = res.get("publishedDate") or ""
        lines.append(f"{i}. {res.get('title', '').strip()}\n   {res.get('url')}" + (f"\n   date : {date}" if date else ""))
        snippet = (res.get("content") or "").strip()
        if snippet:
            lines.append("   " + snippet[:500])
    return "\n".join(lines)


def fetch_page(url, start=0):
    start = max(0, int(start))
    with httpx.Client(timeout=30, headers={"User-Agent": UA, "Accept-Language": "fr,en;q=0.8"}) as client:
        for _ in range(6):
            check_url(url)
            with client.stream("GET", url) as r:
                if r.is_redirect:
                    url = urljoin(url, r.headers.get("location", ""))
                    continue
                if r.status_code >= 400:
                    raise ToolError(f"HTTP {r.status_code} pour {url}")
                ctype = r.headers.get("content-type", "")
                body = b""
                for part in r.iter_bytes():
                    body += part
                    if len(body) > MAX_BYTES:
                        break
                break
        else:
            raise ToolError("trop de redirections")
    if "html" in ctype or not ctype:
        text = trafilatura.extract(body.decode(r.encoding or "utf-8", "replace"), output_format="markdown",
                                   include_tables=True, include_links=False, url=url) or ""
    elif ctype.startswith("text/") or "json" in ctype or "xml" in ctype:
        text = body.decode(r.encoding or "utf-8", "replace")
    else:
        raise ToolError(f"type de contenu non pris en charge : {ctype} (pages web et texte uniquement)")
    if not text.strip():
        return f"Page {url} : aucun texte extrait (page vide ou chargee en JavaScript)."
    chunk = text[start : start + CHUNK]
    head = f"Page : {url}\nCaracteres {start}-{start + len(chunk)} sur {len(text)}\n\n"
    tail = f"\n\n[suite : web_fetch_page avec start={start + CHUNK}]" if start + CHUNK < len(text) else ""
    return head + chunk + tail


HANDLERS = {"search": web_search, "fetch_page": fetch_page}


def handle(msg):
    method, params = msg.get("method"), msg.get("params") or {}
    if method == "initialize":
        return {
            "protocolVersion": params.get("protocolVersion", "2025-06-18"),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "setup-llm-web", "version": "1.0"},
        }
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": TOOLS}
    if method == "tools/call":
        name, args = params.get("name"), params.get("arguments") or {}
        if name not in HANDLERS:
            return {"content": [{"type": "text", "text": f"outil inconnu : {name}"}], "isError": True}
        # llama-server ajoute ses propres arguments (runtime...) : seuls ceux du schema sont gardes.
        allowed = next(t["inputSchema"]["properties"] for t in TOOLS if t["name"] == name)
        args = {k: v for k, v in args.items() if k in allowed}
        try:
            return {"content": [{"type": "text", "text": HANDLERS[name](**args)}], "isError": False}
        except (ToolError, httpx.HTTPError, TypeError, ValueError) as e:
            return {"content": [{"type": "text", "text": f"Erreur : {e}"}], "isError": True}
    raise LookupError(method)


def main():
    for line in sys.stdin:
        if not line.strip():
            continue
        msg = json.loads(line)
        if "id" not in msg:
            continue  # notification (notifications/initialized...) : pas de reponse
        try:
            reply = {"jsonrpc": "2.0", "id": msg["id"], "result": handle(msg)}
        except LookupError:
            reply = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": "Method not found"}}
        sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
