#!/bin/zsh
# Outils de l'interface web (shell, lecture et ecriture de fichiers) dans un conteneur isole.
# llama-server execute ces outils dans le conteneur setup-llm-tools (--tools-runtime, voir start.sh) :
# le modele n'a ni reseau ni acces au Mac, seulement au dossier partage ~/LLM-fichiers (/work).
# Les fichiers produits se telechargent depuis l'interface web (bouton Telecharger, menu Fichiers).
#
# Usage : /Users/amaury/DEV/SETUP-LLM/tools-runtime/setup.sh
#   - installe Colima (VM Linux legere) et le client docker avec Homebrew (sans sudo)
#   - demarre Colima au login (brew services), VM : 2 CPU, 2 Gio, 20 Gio, seul ~/LLM-fichiers monte
#   - construit l'image setup-llm-tools (Dockerfile de ce dossier) et (re)cree le conteneur
# Idempotent. Redemarrer ensuite le service pour que llama-server active les outils :
#   launchctl kickstart -k gui/$(id -u)/fr.local.llm-server
set -euo pipefail

DIR=${0:A:h}
CONTAINER=setup-llm-tools
IMAGE=setup-llm-tools
FILES_DIR=$HOME/LLM-fichiers
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
BUILD_LOG=$(mktemp)
docker build -q -t $IMAGE $DIR >/dev/null 2>$BUILD_LOG || { cat $BUILD_LOG >&2; rm -f $BUILD_LOG; exit 1; }
rm -f $BUILD_LOG

# Conteneur toujours recree : il reprend la derniere image. Restrictions : pas de reseau, systeme en
# lecture seule sauf /work et /tmp, aucun privilege, 1 Gio de memoire, 256 processus.
docker rm -f $CONTAINER >/dev/null 2>&1 || true
docker run -d --name $CONTAINER --restart unless-stopped \
  --network none --read-only --tmpfs /tmp --tmpfs /home/agent \
  --cap-drop ALL --security-opt no-new-privileges --pids-limit 256 --memory 1g --cpus 2 \
  -v $FILES_DIR:/work $IMAGE sleep infinity >/dev/null
docker exec $CONTAINER python -c "import docx, openpyxl, pptx, reportlab" &&
  echo "Conteneur $CONTAINER pret (fichiers : $FILES_DIR)"
