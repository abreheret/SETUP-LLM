#!/bin/zsh
# Remplace le mot de passe partage du serveur LLM et redemarre le service.
# Usage : /Users/amaury/DEV/SETUP-LLM/set-password.sh <nouveau_mot_de_passe>
set -euo pipefail

PASSWORD_FILE=/Users/amaury/DEV/SETUP-LLM/password
LABEL=fr.local.llm-server

if [[ $# -ne 1 ]]; then
  echo "Usage : $0 <nouveau_mot_de_passe>" >&2
  exit 1
fi

NEW=$1
if (( ${#NEW} < 12 )); then
  echo "Refuse : 12 caracteres minimum (le serveur est visible par tout le reseau local, y compris au travail)." >&2
  exit 1
fi
if [[ $NEW == *[[:space:]]* ]]; then
  echo "Refuse : pas d'espace dans le mot de passe (il est envoye dans un en-tete HTTP)." >&2
  exit 1
fi

(umask 077; printf '%s\n' "$NEW" > "$PASSWORD_FILE")
chmod 600 "$PASSWORD_FILE"
echo "Mot de passe mis a jour dans $PASSWORD_FILE"

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  echo "Service $LABEL redemarre."
else
  echo "Service $LABEL non charge : le nouveau mot de passe sera pris en compte au prochain demarrage."
fi
