#!/bin/zsh
# Lance Caddy : interface web en HTTPS sur le port 8443 (voir Caddyfile), pour le micro.
# Certificat auto-signe dans voice/tls/ (non versionne), regenere si l'IP du Mac n'y figure pas :
# le navigateur affiche une alerte au premier acces (Avance, puis Continuer).
# Usage : /Users/amaury/DEV/SETUP-LLM/voice/https.sh (LaunchAgent fr.local.llm-https)
set -euo pipefail

source /Users/amaury/DEV/SETUP-LLM/models.conf
TLS_DIR=$ROOT/voice/tls
mkdir -p $TLS_DIR $LOG_DIR
exec >>$LOG_DIR/llm-https.log 2>&1
echo "===== $(date '+%F %T') demarrage HTTPS :8443 ====="

# Noms et adresses du certificat : IP actuelles, nom Bonjour, localhost.
SAN="DNS:localhost,DNS:$(scutil --get LocalHostName).local,IP:127.0.0.1"
for IF in en0 en1; do
  IP=$(ipconfig getifaddr $IF 2>/dev/null) && SAN+=",IP:$IP"
done
if [[ ! -s $TLS_DIR/cert.pem ]] || [[ $(<$TLS_DIR/san.txt 2>/dev/null) != $SAN ]]; then
  echo "certificat (re)genere : $SAN"
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -subj "/CN=llm-server" -addext "subjectAltName=$SAN" \
    -keyout $TLS_DIR/key.pem -out $TLS_DIR/cert.pem 2>/dev/null
  chmod 600 $TLS_DIR/key.pem
  print -r -- $SAN > $TLS_DIR/san.txt
fi

export LLM_TLS_DIR=$TLS_DIR
# Le mot de passe passe par l'environnement de Caddy (lisible seulement par ce compte), pas en argument.
export LLM_PASSWORD="$(<$PASSWORD_FILE)"
exec /opt/homebrew/bin/caddy run --adapter caddyfile --config $ROOT/voice/Caddyfile
