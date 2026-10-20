import json, os, sys, time, urllib.request

# Mesure la vitesse de generation (code C++ et prose francaise) du serveur LLM.
# usage : PORT=8080 MODEL=qwen3.8-flash-next python3 tools/bench.py <label> <runs>
#   -> une ligne par prompt : tok/s moyen et taux d'acceptation du decodage speculatif (MTP)
label, runs = sys.argv[1], int(sys.argv[2])
PORT = os.environ.get("PORT", "8080")
MODEL = os.environ.get("MODEL", "qwen3.8-flash-next")
KEY = open("/Users/amaury/DEV/SETUP-LLM/password").read().strip()
HEADERS = {"Content-Type": "application/json", "Authorization": f"Bearer {KEY}"}
PROMPTS = {
    "code": "Write a C++17 header-only thread-safe LRU cache class template with get/put, using std::list and std::unordered_map, "
            "with doc comments. Output only the code, about 120 lines.",
    "prose": "Rédige un texte en français d'environ 400 mots expliquant à un étudiant ingénieur comment fonctionne un moteur "
             "à combustion interne quatre temps. Pas de liste, uniquement des paragraphes.",
}
for name, p in PROMPTS.items():
    tps, drafted, accepted, gen = [], 0, 0, 0
    for _ in range(runs):
        body = {"model": MODEL, "messages": [{"role": "user", "content": p}], "max_tokens": 700,
                "chat_template_kwargs": {"enable_thinking": False}}
        req = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions", json.dumps(body).encode(),
                                     HEADERS)
        t0 = time.time()
        d = json.load(urllib.request.urlopen(req, timeout=1800))
        wall = time.time() - t0
        t = d.get("timings", {})
        n = d["usage"]["completion_tokens"]
        tps.append(t.get("predicted_per_second", n / wall))
        gen += n
        drafted += t.get("draft_n", 0)
        accepted += t.get("draft_n_accepted", 0)
    acc = f"{100 * accepted / drafted:.0f} %" if drafted else "-"
    print(f"{label:12s} {name:6s} {sum(tps) / len(tps):6.1f} tok/s  (runs: {', '.join(f'{x:.1f}' for x in tps)})  "
          f"acceptation {acc}  gen moy {gen // runs} tok")
