#!/bin/zsh
# Lance le serveur LLM sur 0.0.0.0:8080 avec le profil demande (ou le profil par defaut de models.conf).
# Usage : /Users/amaury/DEV/SETUP-LLM/start.sh [flash|27b|27b-dspark]
set -euo pipefail

source /Users/amaury/DEV/SETUP-LLM/models.conf

PROFILE=${1:-$DEFAULT_PROFILE}
if ! (( ${PROFILES[(Ie)$PROFILE]} )); then
  echo "Profil inconnu : $PROFILE (choix : ${PROFILES[*]})" >&2
  exit 1
fi
profile_$PROFILE

if [[ ! -s $PASSWORD_FILE ]]; then
  echo "Fichier mot de passe absent ou vide : $PASSWORD_FILE (voir set-password.sh)" >&2
  exit 1
fi

mkdir -p $LOG_DIR
LOG=$LOG_DIR/llm-server.log
exec >>$LOG 2>&1
echo "===== $(date '+%F %T') demarrage profil $PROFILE ($ENGINE, alias $ALIAS) ====="

# caffeinate -s : empeche la veille systeme uniquement sur secteur, sans effet sur batterie.
if [[ $ENGINE == llama ]]; then
  # Interface web avec l'entree Documentation (tools/build-webui.py), seulement si elle a ete copiee
  # depuis cette version de llama-server ; sinon l'interface integree est servie.
  WEBUI_ARGS=()
  if [[ -f $ROOT/webui/.llama-version ]] &&
     [[ $(<$ROOT/webui/.llama-version) == $(/opt/homebrew/bin/llama-server --version 2>&1 | head -1) ]]; then
    WEBUI_ARGS=(--path $ROOT/webui)
  elif [[ -d $ROOT/webui ]]; then
    echo "webui/ copiee depuis une autre version de llama-server : interface integree servie (relancer tools/build-webui.py)"
  fi
  exec /usr/bin/caffeinate -s /opt/homebrew/bin/llama-server -m $MODEL --alias $ALIAS \
    --host $HOST --port $PORT --api-key-file $PASSWORD_FILE \
    $LLAMA_COMMON $WEBUI_ARGS $ARGS
else
  # mlx-dspark n'a pas d'option fichier pour la cle : elle est lue ici et passee en argument.
  exec /usr/bin/caffeinate -s $DSPARK_BIN serve --model $MODEL \
    --host $HOST --port $PORT --api-key "$(<$PASSWORD_FILE)" \
    $ARGS
fi
