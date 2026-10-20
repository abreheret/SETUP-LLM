import glob, json, os, subprocess, sys, threading, time, urllib.request

# Test de charge du serveur LLM : prompts longs (en-tetes libc++ du SDK macOS).
# usage : PORT=8080 python3 tools/load.py <label> <tokens_par_prompt> [modele]
# Mesure : 1 requete seule, puis 2 requetes simultanees, prompts longs differents, ~500 tokens generes.
label, target = sys.argv[1], int(sys.argv[2])
MODEL = sys.argv[3] if len(sys.argv) > 3 else "qwen3.8-flash-next"
PORT = os.environ.get("PORT", "8080")
BASE = f"http://127.0.0.1:{PORT}"
KEY = open("/Users/amaury/DEV/SETUP-LLM/password").read().strip()
HEADERS = {"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"}
SDK_CXX = sorted(glob.glob("/Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk/usr/include/c++/v1"))[-1]
HDR = sorted(glob.glob(f"{SDK_CXX}/**/*.h", recursive=True) + glob.glob(f"{SDK_CXX}/*"))
HDR = [h for h in HDR if os.path.isfile(h)]


def post(path, body, timeout=3600):
    req = urllib.request.Request(BASE + path, json.dumps(body).encode(), HEADERS)
    return json.load(urllib.request.urlopen(req, timeout=timeout))


def ntok(text):
    return len(post("/tokenize", {"content": text})["tokens"])


def build(files, target):
    parts, used = [], 0
    for f in files:
        txt = open(f, errors="replace").read()
        parts.append(f"// ===== {os.path.basename(f)} =====\n{txt}\n")
        used += len(txt) // 3
        if used > target * 1.3:
            break
    text = "".join(parts)
    lo, hi = 0, len(text)
    while hi - lo > 2000:  # ajuste la longueur au nombre de tokens vise
        mid = (lo + hi) // 2
        if ntok(text[:mid]) < target: lo = mid
        else: hi = mid
    return text[:lo]


QUESTION = ("\n\nAbove is a large excerpt of the libc++ headers. Write a structured summary of about 500 words: "
            "which components appear, the main design patterns, and three non-obvious implementation details.")
half = len(HDR) // 2
print(f"[{label}] construction des prompts (~{target} tokens chacun)...", flush=True)
CACHE = f"/tmp/llm-load-prompts-{target}.json"
if os.path.exists(CACHE):
    prompts, sizes = json.load(open(CACHE))
else:
    prompts = [build(HDR[:half], target), build(HDR[half:], target)]
    sizes = [ntok(p) for p in prompts]
    json.dump([prompts, sizes], open(CACHE, "w"))
print(f"[{label}] {len(HDR)} fichiers, prompts de {sizes} tokens", flush=True)
assert min(sizes) > target * 0.9, "prompts trop courts"

mem = {"min_free": 100, "swapouts0": None, "swapouts": 0}
stop = threading.Event()


def watch():
    while not stop.is_set():
        out = subprocess.run(["memory_pressure"], capture_output=True, text=True).stdout
        for l in out.splitlines():
            if "free percentage" in l: mem["min_free"] = min(mem["min_free"], int(l.split()[-1].rstrip("%")))
            if l.startswith("Swapouts"):
                v = int(l.split()[-1]); mem["swapouts0"] = mem["swapouts0"] if mem["swapouts0"] is not None else v
                mem["swapouts"] = v - mem["swapouts0"]
        time.sleep(5)


threading.Thread(target=watch, daemon=True).start()


def run(prompt, res, i):
    t0 = time.time()
    try:
        d = post("/v1/chat/completions", {"model": MODEL, "messages": [{"role": "user", "content": prompt + QUESTION}],
                                         "max_tokens": 500, "cache_prompt": False,
                                         "chat_template_kwargs": {"enable_thinking": False}})
        t = d.get("timings", {})
        res[i] = dict(ok=True, wall=time.time() - t0, prompt=d["usage"]["prompt_tokens"], gen=d["usage"]["completion_tokens"],
                      pp=t.get("prompt_ms", 0) / 1000, pps=t.get("prompt_per_second", 0), tgs=t.get("predicted_per_second", 0),
                      finish=d["choices"][0]["finish_reason"])
    except Exception as e:
        res[i] = dict(ok=False, err=str(e)[:200], wall=time.time() - t0)


for n in (1, 2):
    res = [None] * n
    th = [threading.Thread(target=run, args=(prompts[i], res, i)) for i in range(n)]
    t0 = time.time()
    [x.start() for x in th]; [x.join() for x in th]
    wall = time.time() - t0
    for i, r in enumerate(res):
        if r["ok"]:
            print(f"[{label}] {n} user(s) #{i}: prompt {r['prompt']} tok, prefill {r['pp']:.0f} s ({r['pps']:.0f} tok/s), "
                  f"gen {r['gen']} tok @ {r['tgs']:.1f} tok/s, total {r['wall']:.0f} s, finish={r['finish']}", flush=True)
        else:
            print(f"[{label}] {n} user(s) #{i}: ECHEC {r['err']}", flush=True)
    ok = [r for r in res if r["ok"]]
    if ok:
        print(f"[{label}] {n} user(s): debit generation total {sum(r['tgs'] for r in ok):.1f} tok/s, duree {wall:.0f} s", flush=True)
stop.set()
print(f"[{label}] memoire : free min {mem['min_free']} %, swapouts pendant le test {mem['swapouts']}", flush=True)
