#!/bin/zsh
# Etat du serveur LLM : service, modele charge, adresses d'acces, memoire.
# Usage : /Users/amaury/DEV/SETUP-LLM/status.sh

source /Users/amaury/DEV/SETUP-LLM/models.conf
LABEL=fr.local.llm-server

echo "== Service =="
if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl print "gui/$(id -u)/$LABEL" | awk -F' = ' '/^\tstate|^\tpid|last exit code/ {gsub(/^\t+/, "", $1); print "  " $1 " : " $2}'
else
  echo "  LaunchAgent $LABEL non charge"
fi
# Le serveur tourne sous caffeinate, dont la ligne de commande correspond aussi : on l'ecarte.
PID=""
for P in $(pgrep -f "(llama-server|mlx-dspark serve) .*--port $PORT"); do
  [[ $(ps -o comm= -p $P) != */caffeinate ]] && { PID=$P; break; }
done
if [[ -n $PID ]]; then
  echo "  processus serveur : PID $PID ($(ps -o comm= -p $PID | xargs basename))"
else
  echo "  aucun processus serveur sur le port $PORT"
fi
echo "  profil par defaut : $DEFAULT_PROFILE"

echo "== Modele =="
MODELS_JSON=$(curl -s -m 5 -H "Authorization: Bearer $(<$PASSWORD_FILE)" http://127.0.0.1:$PORT/v1/models 2>/dev/null)
if [[ -n $MODELS_JSON ]]; then
  echo "  charge : $(print -r -- $MODELS_JSON | /usr/bin/python3 -c 'import json,sys; print(", ".join(m["id"] for m in json.load(sys.stdin)["data"]))' 2>/dev/null || echo '? (reponse illisible)')"
  HEALTH=$(curl -s -m 5 http://127.0.0.1:$PORT/health 2>/dev/null)
  echo "  sante : $(print -r -- ${HEALTH:-'{}'} | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", "?"))' 2>/dev/null || echo '?')"
else
  echo "  le serveur ne repond pas (arrete, ou modele en cours de chargement)"
fi

echo "== Acces reseau =="
NAME=$(scutil --get LocalHostName)
for IF in en0 en1; do
  IP=$(ipconfig getifaddr $IF 2>/dev/null) || continue
  echo "  $IF : http://$IP:$PORT/v1   (interface web : http://$IP:$PORT, avec micro : https://$IP:8443)"
done
echo "  Bonjour : http://$NAME.local:$PORT/v1   (WSL2 : utiliser l'IP)"

echo "== Memoire =="
memory_pressure | awk '/free percentage/ {print "  memoire libre : " $NF}'
PAGE=$(sysctl -n hw.pagesize)
vm_stat | awk -v p=$PAGE '/Pages wired down/ {gsub(/\./,"",$4); printf "  memoire verrouillee (GPU + noyau) : %.1f Go\n", $4*p/1e9}'
sysctl -n vm.swapusage | awk '{print "  swap utilise : " $6}'
[[ -n $PID ]] && ps -o rss= -p $PID | awk '{printf "  memoire du processus serveur (RSS) : %.1f Go\n", $1/1e6}'
echo "  limite GPU : $(sysctl -n iogpu.wired_limit_mb) Mo"
