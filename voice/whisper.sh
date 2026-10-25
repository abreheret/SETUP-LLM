#!/bin/zsh
# Lance whisper-server (transcription de la voix pour le micro de l'interface web) sur 127.0.0.1:8178.
# Joignable seulement par Caddy (https://<IP>:8443/whisper/, avec le mot de passe), pas depuis le reseau.
# Modele large-v3-turbo (1,6 Go, GPU), langue detectee automatiquement (francais, anglais...).
# Usage : /Users/amaury/DEV/SETUP-LLM/voice/whisper.sh (LaunchAgent fr.local.whisper-server)
set -euo pipefail

source /Users/amaury/DEV/SETUP-LLM/models.conf
mkdir -p $LOG_DIR
exec >>$LOG_DIR/whisper-server.log 2>&1
echo "===== $(date '+%F %T') demarrage whisper-server ====="
exec /opt/homebrew/bin/whisper-server -m $MODELS/whisper/ggml-large-v3-turbo.bin \
  --host 127.0.0.1 --port 8178 -l auto -t 4
