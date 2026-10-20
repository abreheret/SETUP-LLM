#!/bin/zsh
# Change le modele actif : met a jour le profil par defaut de models.conf puis redemarre le service.
# Usage : /Users/amaury/DEV/SETUP-LLM/switch.sh <flash|27b|27b-dspark>
set -euo pipefail

CONF=/Users/amaury/DEV/SETUP-LLM/models.conf
LABEL=fr.local.llm-server
source $CONF

if [[ $# -ne 1 ]] || ! (( ${PROFILES[(Ie)$1]} )); then
  echo "Usage : $0 <${(j:|:)PROFILES}>  (profil actuel : $DEFAULT_PROFILE)" >&2
  exit 1
fi

sed -i '' "s/^DEFAULT_PROFILE=.*/DEFAULT_PROFILE=$1/" $CONF
echo "Profil par defaut : $1"

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  echo "Service $LABEL redemarre. Chargement du modele en cours (10 a 120 s), suivre avec status.sh."
else
  echo "Service $LABEL non charge : lancer start.sh a la main, ou charger le LaunchAgent."
fi
