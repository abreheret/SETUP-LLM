#!/bin/zsh
# Installation complete du serveur LLM local (MacBook Pro M5 Max, 128 Go) depuis zero.
# Rejoue toutes les etapes de SETUP_LLM_SERVER.md telles qu'elles ont ete validees le 20/10/2026
# (voir README.md pour les choix et les mesures), avec les ajouts suivants (README.md, section 12) :
#   21/10/2026 : plafond de reflexion 24576 tokens (models.conf) ; interface web avec l'entree
#                Documentation (etape 11, tools/build-webui.py, servie avec --path par start.sh)
#   24/10/2026 : vision pour Flash-Next (mmproj-F16.gguf, etape 3, --mmproj dans models.conf)
#   25/10/2026 : creation de fichiers depuis l'interface web, outils executes dans le conteneur
#                setup-llm-tools sous Colima (etape 6 bis, tools-runtime/setup.sh, --tools dans start.sh) ;
#                recherche web (SearXNG et serveur MCP dans setup-llm-web, --mcp-servers-config) ;
#                voix : dictee (whisper-server, modele large-v3-turbo) et acces HTTPS :8443 (Caddy),
#                lecture a voix haute dans la page (etape 3, etape 6 ter, voice/)
#
# Usage : ./install.sh [--no-dspark] [--no-models] [--no-tools] [--no-voice] [--no-sudo] [--yes]
#   --no-dspark : ne pas installer mlx-dspark ni le modele MLX (profil 27b-dspark)
#   --no-models : ne rien telecharger (modeles deja presents ou copies a la main)
#   --no-tools  : ne pas installer Colima ni le conteneur des outils (interface web sans outils)
#   --no-voice  : ne pas installer la dictee (whisper-server) ni l'acces HTTPS :8443 (Caddy)
#   --no-sudo   : sauter les etapes systeme qui demandent sudo (limite GPU, veille, pare-feu)
#   --yes       : repondre oui a toutes les confirmations (sudo et gros telechargements compris)
#
# Le script est idempotent : il peut etre relance, chaque etape verifie ce qui est deja fait.
set -euo pipefail

# ---------------------------------------------------------------------------------------------
# Parametres
# ---------------------------------------------------------------------------------------------
DEFAULT_ROOT=/Users/amaury/DEV/SETUP-LLM
ROOT=${0:A:h}
MODELS=$ROOT/models
LOG_DIR=$ROOT/logs
PASSWORD_FILE=$ROOT/password
AGENT_LABEL=fr.local.llm-server
DAEMON_LABEL=fr.local.iogpu-wired-limit
GPU_WIRED_LIMIT_MB=112640
DSPARK_VERSION=0.20.3

FLASH_REPO=unsloth/Qwen3.8-Flash-Next-GGUF
FLASH_FILES=(
  UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf
  UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00002-of-00004.gguf
  UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00003-of-00004.gguf
  UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00004-of-00004.gguf
  # Tete MTP autonome : la version "shared" ne se charge pas avec le llama.cpp Homebrew.
  MTP/mtp-Qwen3.8-Flash-Next-Q8_0.gguf
)
DENSE_REPO=unsloth/Qwen3.8-27B-GGUF
DENSE_FILES=(Qwen3.8-27B-Q8_0.gguf)
MLX_REPO=mlx-community/Qwen3.8-27B-8bit
DFLASH_REPO=incoai/Qwen3.8-27B-DFlash2
WHISPER_REPO=ggerganov/whisper.cpp
WHISPER_FILE=ggml-large-v3-turbo.bin

WITH_DSPARK=1 WITH_MODELS=1 WITH_TOOLS=1 WITH_VOICE=1 WITH_SUDO=1 ASSUME_YES=0
for arg in "$@"; do
  case $arg in
    --no-dspark) WITH_DSPARK=0 ;;
    --no-models) WITH_MODELS=0 ;;
    --no-tools) WITH_TOOLS=0 ;;
    --no-voice) WITH_VOICE=0 ;;
    --no-sudo) WITH_SUDO=0 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,20p' $0; exit 0 ;;
    *) echo "Option inconnue : $arg" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------------------------
step() { print -P "\n%F{cyan}==== $* ====%f"; }
ok()   { print -P "  %F{green}OK%f $*"; }
warn() { print -P "  %F{yellow}ATTENTION%f $*"; }
die()  { print -P "  %F{red}ERREUR%f $*" >&2; exit 1; }
# grep qui lit toute son entree : avec pipefail, grep -q couperait le pipe (SIGPIPE) et ferait echouer le test.
has()  { grep -c "$@" >/dev/null; }

confirm() {
  (( ASSUME_YES )) && return 0
  local answer
  read "answer?  $* [o/N] "
  [[ $answer == [oOyY]* ]]
}

# Taille totale (octets) et sha256 attendus des fichiers d'un depot Hugging Face, via l'API (curl).
hf_manifest() {
  local repo=$1
  curl -fsSL --retry 5 "https://huggingface.co/api/models/$repo/tree/main?recursive=true" \
    | /usr/bin/python3 -c '
import json, sys
for e in json.load(sys.stdin):
    if e["type"] == "file":
        print(e["path"], e["size"], (e.get("lfs") or {}).get("oid", "-"))'
}

# Telecharge des fichiers d'un depot avec hf, puis verifie taille et sha256.
# Reessaie jusqu'a 5 fois (coupures reseau constatees pendant l'installation d'origine).
hf_fetch() {
  local repo=$1 dest=$2; shift 2
  local manifest; manifest=$(hf_manifest $repo) || die "depot $repo introuvable"
  local files=("$@")
  (( ${#files} )) || files=(${(f)"$(print -r -- $manifest | awk '{print $1}')"})
  local f size sha line attempt
  for f in $files; do
    line=$(print -r -- $manifest | awk -v p=$f '$1==p') || true
    [[ -n $line ]] || die "$repo : fichier $f absent du depot"
    size=${${(s: :)line}[2]} sha=${${(s: :)line}[3]}
    for attempt in 1 2 3 4 5; do
      if [[ -f $dest/$f && $(stat -f %z $dest/$f) == $size ]]; then
        if [[ $sha == - || $(shasum -a 256 $dest/$f | cut -d' ' -f1) == $sha ]]; then
          ok "$repo/$f ($(( size / 1000000 )) Mo, verifie)"
          continue 2
        fi
        warn "$f : sha256 incorrect, nouveau telechargement"
        rm -f $dest/$f
      fi
      echo "  telechargement $repo/$f ($(( size / 1000000 )) Mo), essai $attempt/5..."
      caffeinate -i hf download $repo $f --local-dir $dest >/dev/null || warn "hf a echoue, nouvel essai"
    done
    die "$repo/$f : echec apres 5 essais"
  done
}

total_size_gb() {
  local repo=$1; shift
  local manifest; manifest=$(hf_manifest $repo)
  if (( $# )); then
    print -r -- $manifest | awk -v list="$*" 'BEGIN{n=split(list,a," "); for(i=1;i<=n;i++) w[a[i]]=1} ($1 in w){s+=$2} END{printf "%.1f", s/1e9}'
  else
    print -r -- $manifest | awk '{s+=$2} END{printf "%.1f", s/1e9}'
  fi
}

# ---------------------------------------------------------------------------------------------
step "Etape 0 : etat des lieux"
# ---------------------------------------------------------------------------------------------
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || die "il faut un Mac Apple Silicon"
echo "  macOS $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string), $(( $(sysctl -n hw.memsize) / 1073741824 )) Go"
(( $(sysctl -n hw.memsize) >= 120 * 1073741824 )) || warn "moins de 128 Go : les reglages de models.conf ne tiendront pas en memoire"
FREE_GB=$(df -g $ROOT | awk 'NR==2 {print $4}')
echo "  disque libre : $FREE_GB Go (il faut environ 180 Go avec tous les modeles)"
(( FREE_GB >= 180 || ! WITH_MODELS )) || warn "espace disque probablement insuffisant"
echo "  Bonjour : $(scutil --get LocalHostName).local, IP : $(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo '?')"
mkdir -p $LOG_DIR $MODELS

if [[ $ROOT != $DEFAULT_ROOT ]]; then
  warn "dossier $ROOT different de $DEFAULT_ROOT : les chemins absolus des scripts vont etre adaptes"
  confirm "Adapter les chemins dans start.sh, switch.sh, status.sh, set-password.sh, models.conf et tools/ ?" || die "abandon"
  sed -i '' "s|$DEFAULT_ROOT|$ROOT|g" $ROOT/{start.sh,switch.sh,status.sh,set-password.sh,models.conf} $ROOT/tools/*.py
  ok "chemins adaptes"
fi

# ---------------------------------------------------------------------------------------------
step "Etape 1 : outils de base (Homebrew, llama.cpp, hf, uv)"
# ---------------------------------------------------------------------------------------------
if ! command -v brew >/dev/null; then
  [[ -x /opt/homebrew/bin/brew ]] || {
    confirm "Homebrew absent. Lancer l'installeur officiel (demande le mot de passe administrateur) ?" || die "Homebrew requis"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  }
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"
for formula in llama.cpp hf uv; do
  brew list --versions $formula >/dev/null || brew install $formula
  ok "$(brew list --versions $formula)"
done
# Support de l'architecture de Qwen3.8-Flash-Next et du decodage MTP dans le build installe.
strings $(brew --prefix llama.cpp)/lib/libllama.dylib | has qwen4exp \
  || die "llama.cpp $(llama-server --version 2>&1 | head -1) ne connait pas l'architecture qwen4exp : compiler llama.cpp depuis les sources (voir SETUP_LLM_SERVER.md, etape 1)"
llama-server --help 2>&1 | has draft-mtp || warn "ce llama-server ne propose pas --spec-type draft-mtp : retirer le MTP du profil flash dans models.conf"
llama-server --help 2>&1 | has -- --kv-unified-per-slot || warn "option --kv-unified-per-slot absente : adapter CTX_ARGS dans models.conf"
ok "$(llama-server --version 2>&1 | head -1)"
if ! hf auth whoami >/dev/null 2>&1; then
  warn "hf non connecte : telechargements limites en debit. Pour un jeton en lecture : hf auth login --token \"\$(pbpaste)\""
fi

# ---------------------------------------------------------------------------------------------
step "Etape 2 : limite de memoire GPU ($GPU_WIRED_LIMIT_MB Mo)"
# ---------------------------------------------------------------------------------------------
if (( ! WITH_SUDO )); then
  warn "etape sautee (--no-sudo)"
elif [[ $(sysctl -n iogpu.wired_limit_mb) == $GPU_WIRED_LIMIT_MB && -f /Library/LaunchDaemons/$DAEMON_LABEL.plist ]]; then
  ok "deja en place (iogpu.wired_limit_mb = $GPU_WIRED_LIMIT_MB, LaunchDaemon present)"
else
  echo "  valeur actuelle : $(sysctl -n iogpu.wired_limit_mb) (0 = defaut macOS)"
  if confirm "sudo : fixer iogpu.wired_limit_mb=$GPU_WIRED_LIMIT_MB et installer le LaunchDaemon $DAEMON_LABEL ?"; then
    sudo sysctl iogpu.wired_limit_mb=$GPU_WIRED_LIMIT_MB
    sudo cp $ROOT/system/$DAEMON_LABEL.plist /Library/LaunchDaemons/
    sudo chown root:wheel /Library/LaunchDaemons/$DAEMON_LABEL.plist
    sudo chmod 644 /Library/LaunchDaemons/$DAEMON_LABEL.plist
    sudo plutil -lint /Library/LaunchDaemons/$DAEMON_LABEL.plist
    sudo launchctl bootout system/$DAEMON_LABEL 2>/dev/null || true
    sudo launchctl bootstrap system /Library/LaunchDaemons/$DAEMON_LABEL.plist
    ok "iogpu.wired_limit_mb = $(sysctl -n iogpu.wired_limit_mb)"
  else
    warn "etape refusee : Flash-Next (environ 97 Go sur le GPU) ne tiendra pas avec la limite par defaut"
  fi
fi

# ---------------------------------------------------------------------------------------------
step "Etape 3 : modeles"
# ---------------------------------------------------------------------------------------------
if (( ! WITH_MODELS )); then
  warn "etape sautee (--no-models)"
else
  SIZE_FLASH=$(total_size_gb $FLASH_REPO $FLASH_FILES)
  SIZE_DENSE=$(total_size_gb $DENSE_REPO $DENSE_FILES)
  echo "  Flash-Next UD-Q4_K_XL + tete MTP : $SIZE_FLASH Go (+ 0,9 Go de vision) ; 27B Q8_0 : $SIZE_DENSE Go"
  if confirm "Telecharger (ou verifier) ces modeles ?"; then
    hf_fetch $FLASH_REPO $MODELS/qwen3.8-flash-next $FLASH_FILES
    # Projecteur de vision (0,9 Go) : sans lui, toute image envoyee renvoie
    # "image input is not supported - hint: ... you may need to provide the mmproj".
    hf_fetch $FLASH_REPO $MODELS/qwen3.8-flash-next/mmproj mmproj-F16.gguf
    hf_fetch $DENSE_REPO $MODELS/qwen3.8-27b $DENSE_FILES
  else
    warn "modeles GGUF non telecharges"
  fi
  # Modele de transcription de la dictee (1,6 Go), lu par voice/whisper.sh.
  (( WITH_VOICE )) && hf_fetch $WHISPER_REPO $MODELS/whisper $WHISPER_FILE
  if (( WITH_DSPARK )); then
    SIZE_MLX=$(total_size_gb $MLX_REPO) SIZE_DFLASH=$(total_size_gb $DFLASH_REPO)
    echo "  27B MLX 8 bits : $SIZE_MLX Go ; drafter DFlash 2 : $SIZE_DFLASH Go"
    if confirm "Telecharger (ou verifier) le modele MLX et son drafter (profil 27b-dspark) ?"; then
      hf_fetch $MLX_REPO $MODELS/qwen3.8-27b-mlx-8bit
      hf_fetch $DFLASH_REPO $MODELS/qwen3.8-27b-dflash2
    else
      warn "modele MLX non telecharge : le profil 27b-dspark ne marchera pas"
    fi
  fi
fi

# ---------------------------------------------------------------------------------------------
step "Etape 4 bis : mlx-dspark (profil 27b-dspark)"
# ---------------------------------------------------------------------------------------------
if (( ! WITH_DSPARK )); then
  warn "etape sautee (--no-dspark)"
else
  # Python 3.12 gere par uv dans le projet : pip sous le Python 3.15 Homebrew (OpenSSL 4) expirait sur pypi.org.
  if [[ ! -x $ROOT/venv-dspark/bin/mlx-dspark ]]; then
    UV_PYTHON_INSTALL_DIR=$ROOT/python uv venv --python 3.12 $ROOT/venv-dspark
    VIRTUAL_ENV=$ROOT/venv-dspark uv pip install "mlx-dspark==$DSPARK_VERSION"
  fi
  ok "mlx-dspark $($ROOT/venv-dspark/bin/python -c 'import importlib.metadata as m; print(m.version("mlx-dspark"))')"
  # mlx-dspark expose le nom du dossier du modele : lien pour garder l'alias qwen3.8-27b.
  mkdir -p $MODELS/mlx-alias
  ln -sfn $MODELS/qwen3.8-27b-mlx-8bit $MODELS/mlx-alias/qwen3.8-27b
  ok "alias $MODELS/mlx-alias/qwen3.8-27b"
fi

# ---------------------------------------------------------------------------------------------
step "Etape 5 : mot de passe partage"
# ---------------------------------------------------------------------------------------------
chmod +x $ROOT/{start.sh,switch.sh,status.sh,set-password.sh}
if [[ -s $PASSWORD_FILE ]]; then
  chmod 600 $PASSWORD_FILE
  ok "mot de passe deja defini ($PASSWORD_FILE)"
else
  echo "  Le serveur sera visible par tout le reseau local (y compris au travail) : 12 caracteres minimum, sans espace."
  read -s "PW?  Mot de passe (vide = generer 4 mots francais) : "; echo
  if [[ -z $PW ]]; then
    WORDS=(abeille abricot ardoise aurore baleine bambou boussole brume cabane cactus caillou canard
           castor cerise chalet citron colline comete corbeau cristal dauphin eclair falaise faucon
           fougere galet girafe glacier guitare hibou horloge jardin lagune lanterne lavande lezard
           marmotte meteore miroir moulin navire nuage orage panda papillon pelican phare pinceau
           prairie renard requin rivage rocher sapin soleil tambour tortue toupie trefle tulipe
           vague valise violon volcan)
    PW=$(for i in 1 2 3 4; do print -r -- ${WORDS[$(( $(od -An -N2 -tu2 /dev/urandom) % ${#WORDS} + 1 ))]}; done | paste -sd- -)
    echo "  Mot de passe genere : $PW"
  fi
  $ROOT/set-password.sh "$PW" >/dev/null
  ok "mot de passe enregistre dans $PASSWORD_FILE (droits 600)"
fi

# ---------------------------------------------------------------------------------------------
step "Etape 6 bis : outils de l'interface web (Colima, conteneur setup-llm-tools)"
# ---------------------------------------------------------------------------------------------
# Avant le LaunchAgent : start.sh n'active les outils (--tools) que si le conteneur tourne.
if (( ! WITH_TOOLS )); then
  warn "etape sautee (--no-tools) : l'interface web ne pourra pas creer de fichiers"
elif $ROOT/tools-runtime/setup.sh; then
  ok "Colima demarre au login (brew services), fichiers produits dans ~/LLM-fichiers, recherche web prete"
else
  warn "tools-runtime/setup.sh a echoue : l'interface web reste sans outils"
fi

# ---------------------------------------------------------------------------------------------
step "Etape 6 ter : voix (dictee whisper-server, acces HTTPS :8443 avec Caddy)"
# ---------------------------------------------------------------------------------------------
# Le micro du navigateur n'est autorise qu'en HTTPS : Caddy sert l'interface web sur le port 8443
# (certificat auto-signe, voice/https.sh) et /whisper/ vers whisper-server. Les LaunchAgents sont
# installes a l'etape 7. La lecture a voix haute utilise les voix du navigateur : rien a installer.
if (( ! WITH_VOICE )); then
  warn "etape sautee (--no-voice) : pas de dictee dans l'interface web"
else
  for formula in whisper-cpp caddy; do
    brew list --versions $formula >/dev/null || brew install $formula
    ok "$(brew list --versions $formula)"
  done
  [[ -s $MODELS/whisper/$WHISPER_FILE ]] && ok "modele $WHISPER_FILE present" ||
    warn "modele $MODELS/whisper/$WHISPER_FILE absent (etape 3) : la dictee ne marchera pas"
fi

# ---------------------------------------------------------------------------------------------
step "Etape 7 : demarrage automatique (LaunchAgents)"
# ---------------------------------------------------------------------------------------------
# fr.local.llm-server : llama-server ; fr.local.whisper-server et fr.local.llm-https : voix (etape 6 ter).
install_agent() {
  local label=$1 plist=$HOME/Library/LaunchAgents/$1.plist
  sed "s|@ROOT@|$ROOT|g" $ROOT/system/$label.plist > $plist
  plutil -lint $plist >/dev/null
  if launchctl print gui/$(id -u)/$label >/dev/null 2>&1; then
    launchctl bootout gui/$(id -u)/$label || true
    # bootstrap echoue (erreur 5) tant que l'ancien service n'est pas completement arrete.
    for i in {1..30}; do launchctl print gui/$(id -u)/$label >/dev/null 2>&1 || break; sleep 1; done
  fi
  for i in {1..5}; do launchctl bootstrap gui/$(id -u) $plist && break; sleep 2; done
  launchctl print gui/$(id -u)/$label >/dev/null 2>&1 || die "le LaunchAgent $label ne s'est pas charge"
}
mkdir -p $HOME/Library/LaunchAgents
install_agent $AGENT_LABEL
ok "LaunchAgent $AGENT_LABEL charge (profil $(awk -F= '/^DEFAULT_PROFILE=/{print $2}' $ROOT/models.conf))"
if (( WITH_VOICE )); then
  install_agent fr.local.whisper-server
  install_agent fr.local.llm-https
  ok "LaunchAgents fr.local.whisper-server et fr.local.llm-https charges"
fi

# ---------------------------------------------------------------------------------------------
step "Etape 8 : pas de veille sur secteur"
# ---------------------------------------------------------------------------------------------
if (( ! WITH_SUDO )); then
  warn "etape sautee (--no-sudo) : le serveur tourne sous caffeinate -s, mais la veille reste active le reste du temps"
elif [[ $(pmset -g custom | awk '/AC Power/{f=1} f && $1=="sleep"{print $2; exit}') == 0 ]]; then
  ok "deja en place (sleep 0 sur secteur)"
elif confirm "sudo : pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 0 (batterie inchangee) ?"; then
  sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 0
  ok "veille desactivee sur secteur"
fi

# ---------------------------------------------------------------------------------------------
step "Etape 9 : pare-feu macOS"
# ---------------------------------------------------------------------------------------------
FW=/usr/libexec/ApplicationFirewall/socketfilterfw
if $FW --getglobalstate | has disabled; then
  ok "pare-feu desactive : rien a autoriser (il n'est pas modifie)"
elif (( ! WITH_SUDO )); then
  warn "pare-feu actif, etape sautee (--no-sudo) : les clients du reseau seront bloques"
else
  APPS=($(realpath $(command -v llama-server)))
  [[ -x $ROOT/venv-dspark/bin/python ]] && APPS+=($(realpath $ROOT/venv-dspark/bin/python))
  if confirm "sudo : autoriser ${APPS[*]} dans le pare-feu ?"; then
    for app in $APPS; do sudo $FW --add $app; sudo $FW --unblockapp $app; done
    ok "binaires autorises"
  fi
fi

# ---------------------------------------------------------------------------------------------
step "Etape 10 : verification"
# ---------------------------------------------------------------------------------------------
IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)
echo "  attente du chargement du modele (jusqu'a 3 min)..."
for i in {1..90}; do
  curl -s -m 2 -H "Authorization: Bearer $(<$PASSWORD_FILE)" http://$IP:8080/v1/models | has '"id"' && break
  sleep 2
done
CODE_OK=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(<$PASSWORD_FILE)" http://$IP:8080/v1/models)
CODE_KO=$(curl -s -o /dev/null -w '%{http_code}' http://$IP:8080/v1/models)
[[ $CODE_OK == 200 ]] && ok "API via $IP : 200 avec mot de passe" || warn "API via $IP : $CODE_OK avec mot de passe (voir $LOG_DIR/llm-server.log)"
[[ $CODE_KO == 401 ]] && ok "API sans mot de passe : 401" || warn "API sans mot de passe : $CODE_KO (attendu 401)"
if (( WITH_TOOLS )); then
  # L'outil shell doit tourner dans le conteneur : /work existe, /Users n'existe pas.
  OUT=$(curl -s -H "Authorization: Bearer $(<$PASSWORD_FILE)" -H 'Content-Type: application/json' \
    http://127.0.0.1:8080/tools -d '{"tool":"exec_shell_command","params":{"command":"test -d /work && test ! -e /Users && echo isole"}}')
  [[ $OUT == *isole* ]] && ok "outils de l'interface web actifs, dans le conteneur isole" ||
    warn "outils de l'interface web inactifs (voir $LOG_DIR/llm-server.log et docker ps)"
  OUT=$(curl -s -H "Authorization: Bearer $(<$PASSWORD_FILE)" -H 'Content-Type: application/json' \
    http://127.0.0.1:8080/tools -d '{"tool":"web_search","params":{"query":"wikipedia","max_results":1}}')
  [[ $OUT == *http* ]] && ok "recherche web active (web_search)" ||
    warn "recherche web inactive (voir docker logs setup-llm-searxng et $LOG_DIR/llm-server.log)"
fi
if (( WITH_VOICE )); then
  for i in {1..30}; do curl -sk -m 2 https://127.0.0.1:8443/health | has ok && break; sleep 2; done
  curl -sk -m 2 https://$IP:8443/health | has ok && ok "interface web en HTTPS (micro) : https://$IP:8443" ||
    warn "HTTPS :8443 inactif (voir $LOG_DIR/llm-https.log)"
  # Transcription d'une phrase generee par say : verifie Caddy, le mot de passe et whisper-server.
  say -v Thomas -o /tmp/setup-llm-voice.wav --data-format=LEI16@16000 "Bonjour, ceci est un essai."
  CODE_KO=$(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:8443/whisper/inference -F file=@/tmp/setup-llm-voice.wav)
  OUT=$(curl -sk -H "Authorization: Bearer $(<$PASSWORD_FILE)" https://127.0.0.1:8443/whisper/inference \
    -F file=@/tmp/setup-llm-voice.wav -F response_format=json)
  rm -f /tmp/setup-llm-voice.wav
  [[ $OUT == *ssai* ]] && ok "dictee : transcription correcte, $CODE_KO sans mot de passe" ||
    warn "dictee inactive : $OUT (voir $LOG_DIR/whisper-server.log)"
fi
if [[ $(awk -F= '/^DEFAULT_PROFILE=/{print $2}' $ROOT/models.conf) == flash ]]; then
  curl -s -H "Authorization: Bearer $(<$PASSWORD_FILE)" http://127.0.0.1:8080/props | has '"vision":true' &&
    ok "vision active (images acceptees)" ||
    warn "vision inactive : verifier $MODELS/qwen3.8-flash-next/mmproj/mmproj-F16.gguf et --mmproj dans models.conf"
fi

# ---------------------------------------------------------------------------------------------
step "Etape 11 : documentation clients dans l'interface web"
# ---------------------------------------------------------------------------------------------
if [[ $(awk -F= '/^DEFAULT_PROFILE=/{print $2}' $ROOT/models.conf) == 27b-dspark ]]; then
  warn "etape sautee : le profil 27b-dspark (mlx-dspark) n'a pas d'interface web"
elif uv run --no-project --with markdown python $ROOT/tools/build-webui.py; then
  if curl -s -H 'Accept-Encoding: gzip' http://127.0.0.1:8080/ | gunzip 2>/dev/null | has setup-llm-docs-inject; then
    ok "interface web avec l'entree Documentation deja servie (doc regeneree)"
  else
    launchctl kickstart -k gui/$(id -u)/$AGENT_LABEL
    echo "  redemarrage du service pour servir webui/ (jusqu'a 3 min)..."
    for i in {1..90}; do
      curl -s -m 2 -H "Authorization: Bearer $(<$PASSWORD_FILE)" http://127.0.0.1:8080/v1/models | has '"id"' && break
      sleep 2
    done
    curl -s -H 'Accept-Encoding: gzip' http://127.0.0.1:8080/ | gunzip 2>/dev/null | has setup-llm-docs-inject &&
      ok "interface web avec l'entree Documentation : http://$IP:8080/?docs" ||
      warn "l'interface web n'a pas l'entree Documentation (voir $LOG_DIR/llm-server.log)"
  fi
else
  warn "tools/build-webui.py a echoue : l'interface integree reste servie, sans documentation"
fi

$ROOT/status.sh
print -P "\n%F{green}Installation terminee.%f Guides clients : $ROOT/CLIENTS.md et $ROOT/clients/"
