#!/bin/zsh
# Outils de l'interface web (shell, lecture et ecriture de fichiers) dans un conteneur isole.
# llama-server execute ces outils dans le conteneur setup-llm-tools (--tools-runtime, voir start.sh) :
# le modele n'a ni reseau ni acces au Mac, seulement au volume Docker setup-llm-fichiers (/work).
# Chaque conversation y a son dossier /work/<id> ; /work n'est pas listable (droits 1733, voir Dockerfile),
# pour qu'un utilisateur ne voie pas les fichiers des autres. Les fichiers se telechargent depuis
# l'interface web (bouton Telecharger, menu Fichiers).
# Recherche web : serveur MCP (web/server.py, outils web_search et web_fetch_page) dans le conteneur
# setup-llm-web, avec SearXNG (setup-llm-searxng) ; reseau Docker llm-web avec acces Internet, sans
# fichiers. Le shell (setup-llm-tools) reste sans reseau.
#
# Usage : /Users/amaury/DEV/SETUP-LLM/tools-runtime/setup.sh
#   - installe Colima (VM Linux legere) et le client docker avec Homebrew (sans sudo)
#   - demarre Colima au login (brew services), VM : 2 CPU, 2 Gio, 20 Gio, seul ~/LLM-fichiers monte
#     (sans --mount, Colima monterait tout le dossier personnel ; les outils ne l'utilisent plus)
#   - construit les images setup-llm-tools, setup-llm-searxng et setup-llm-web, et (re)cree les conteneurs
# Idempotent. Redemarrer ensuite le service pour que llama-server active les outils :
#   launchctl kickstart -k gui/$(id -u)/fr.local.llm-server
set -euo pipefail

DIR=${0:A:h}
CONTAINER=setup-llm-tools
IMAGE=setup-llm-tools
SEARXNG=setup-llm-searxng
WEB=setup-llm-web
WEB_NET=llm-web
FILES_DIR=$HOME/LLM-fichiers
FILES_VOLUME=setup-llm-fichiers
export PATH=/opt/homebrew/bin:$PATH

for formula in colima docker; do
  brew list --versions $formula >/dev/null || brew install $formula
done
mkdir -p $FILES_DIR

# Premier demarrage : cree la VM avec ses reglages (enregistres dans ~/.colima/default/colima.yaml).
# Ensuite brew services la relance au login avec ces memes reglages.
if ! colima status >/dev/null 2>&1; then
  if [[ ! -f $HOME/.colima/default/colima.yaml ]]; then
    colima start --vm-type vz --cpu 2 --memory 2 --disk 20 --mount $FILES_DIR:w
    colima stop
  fi
  brew services start colima
elif ! brew services list | awk '$1=="colima"{print $2}' | grep -q started; then
  # VM lancee a la main : relancee par brew services pour qu'elle redemarre au login.
  colima stop
  brew services start colima
fi
for i in {1..90}; do docker info >/dev/null 2>&1 && break; sleep 2; done
docker info >/dev/null 2>&1 || { echo "Docker (Colima) ne repond pas : voir colima status" >&2; exit 1; }

# Constructeur classique (sans buildx) : son avertissement "legacy builder" n'est affiche qu'en cas d'echec.
build() {
  local log=$(mktemp)
  docker build -q -t $1 $2 >/dev/null 2>$log || { cat $log >&2; rm -f $log; exit 1; }
  rm -f $log
}
build $IMAGE $DIR
build $SEARXNG $DIR/searxng
build $WEB $DIR/web

# Conteneur toujours recree : il reprend la derniere image. Restrictions : pas de reseau, systeme en
# lecture seule sauf /work et /tmp, aucun privilege, 1 Gio de memoire, 256 processus.
# Volume garde d'une installation a l'autre ; droits de /work reappliques (volume plus ancien).
docker rm -f $CONTAINER >/dev/null 2>&1 || true
docker volume inspect $FILES_VOLUME >/dev/null 2>&1 || docker volume create $FILES_VOLUME >/dev/null
docker run --rm -u 0 --network none -v $FILES_VOLUME:/work $IMAGE sh -c 'chown 0:0 /work && chmod 1733 /work'
docker run -d --name $CONTAINER --restart unless-stopped \
  --network none --read-only --tmpfs /tmp --tmpfs /home/agent \
  --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 1g --cpus 2 \
  -v $FILES_VOLUME:/work $IMAGE sleep infinity >/dev/null
docker exec $CONTAINER python -c "import docx, openpyxl, pptx, reportlab" &&
  echo "Conteneur $CONTAINER pret (fichiers : volume $FILES_VOLUME)"

# Recherche web. SearXNG garde les droits dont son image a besoin au demarrage (changement d'utilisateur).
# setup-llm-web n'execute que web/server.py, qui refuse les adresses non publiques (LAN, Docker).
docker network inspect $WEB_NET >/dev/null 2>&1 || docker network create --subnet 172.30.99.0/24 $WEB_NET >/dev/null
docker rm -f $SEARXNG $WEB >/dev/null 2>&1 || true
docker run -d --name $SEARXNG --restart unless-stopped --network $WEB_NET \
  -e SEARXNG_SECRET=$(openssl rand -hex 32) \
  --cap-drop ALL --cap-add CHOWN --cap-add SETGID --cap-add SETUID --cap-add DAC_OVERRIDE \
  --security-opt no-new-privileges --memory 512m $SEARXNG >/dev/null
docker run -d --name $WEB --restart unless-stopped --network $WEB_NET \
  --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges --pids-limit 128 --memory 512m \
  $WEB sleep infinity >/dev/null
for i in {1..30}; do
  docker exec $WEB python -c "import httpx; httpx.get('http://$SEARXNG:8080/healthz', timeout=2).raise_for_status()" \
    >/dev/null 2>&1 && break
  sleep 2
done
docker exec $WEB python -c "import httpx; httpx.get('http://$SEARXNG:8080/healthz', timeout=2).raise_for_status()" \
  >/dev/null 2>&1 && echo "Recherche web prete ($WEB, $SEARXNG)" || echo "SearXNG ne repond pas : docker logs $SEARXNG" >&2
