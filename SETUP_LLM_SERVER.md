# Mission : transformer ce Mac en serveur LLM pour le reseau local

## Contexte

Machine : MacBook Pro M5 Max, 128 Go de memoire unifiee, SSD 2 To, macOS.
Objectif : faire tourner en continu le meilleur LLM open-weight du moment pour le code, les maths et l'ingenierie (FR + EN), expose via une API compatible OpenAI, accessible depuis d'autres machines du meme reseau (clients : OpenCode, Hermes Agent sous WSL2, etc.).

Choix techniques arretes :
- Moteur : llama.cpp (`llama-server`), installe via Homebrew. Il expose `/v1/chat/completions` compatible OpenAI.
- Modele principal : Qwen3.8-Flash-Next (MoE 125B, ~6B actifs), en GGUF.
- Modele de secours plus leger : Qwen3.8-27B (dense) en Q8_0.
- Un seul modele charge a la fois (pas assez de memoire pour les deux).

## Regles de travail pour toi (Claude Code)

1. Avance etape par etape. A la fin de chaque etape, verifie que ca marche avant de passer a la suivante.
2. Demande-moi confirmation avant toute commande `sudo` et avant tout telechargement de plus de 10 Go.
3. Ne suppose jamais qu'un nom de depot Hugging Face ou un nom de fichier existe : verifie-le (API Hugging Face ou `hf`) avant de l'utiliser. Si un depot cite ici n'existe pas ou a change, propose-moi l'alternative la plus proche et attends mon accord.
4. Repertoire de travail : `/Users/amaury/DEV/SETUP-LLM/`. Tout ce que tu crees va dedans : scripts, config et fichier `password` a la racine, logs dans `logs/`, poids des modeles dans `models/`, builds eventuels de llama.cpp et venv Python dans des sous-dossiers. Utilise toujours des chemins absolus dans les scripts et les plist (launchd ne connait pas `~`). Seules exceptions imposees par macOS : les LaunchAgents dans `~/Library/LaunchAgents/` et le LaunchDaemon dans `/Library/LaunchDaemons/`.
   Si le dossier est un depot git, ajoute un `.gitignore` qui exclut `models/`, `logs/`, `password`, les builds et les venv.
5. A la fin, ecris un `/Users/amaury/DEV/SETUP-LLM/README.md` qui resume ce qui a ete installe, comment demarrer / arreter / changer de modele, et comment s'y connecter.

## Etape 0 : etat des lieux

Lance et resume-moi :
- `sw_vers`
- `sysctl -n hw.memsize` et `system_profiler SPHardwareDataType | grep -E "Chip|Memory"`
- `df -h ~` (il faut au moins 150 Go libres)
- `scutil --get LocalHostName` (nom Bonjour du Mac, joignable en `NOM.local`)
- `ipconfig getifaddr en0` (et `en1` si vide)
- `brew --version` (Homebrew present ou non)

## Etape 1 : outils de base

- Installe Homebrew s'il est absent (installeur officiel).
- `brew install llama.cpp`
- Outil Hugging Face en ligne de commande : `brew install huggingface-cli`, verifie que la commande `hf` repond. Si la formule n'existe pas, utilise `brew install pipx && pipx install "huggingface_hub[cli]"`.
- Verifie que llama.cpp est assez recent pour l'architecture de Qwen3.8-Flash-Next (identifiant `qwen4exp`, support fusionne dans llama.cpp fin aout 2026) : `llama-server --version`. Si le chargement du modele echoue plus tard avec "unknown model architecture", compile llama.cpp depuis les sources (depuis `/Users/amaury/DEV/SETUP-LLM/` : `git clone https://github.com/ggml-org/llama.cpp && cd llama.cpp && cmake -B build -DGGML_METAL=ON && cmake --build build -j --target llama-server`) et utilise ce binaire.

## Etape 2 : autoriser le GPU a utiliser plus de memoire

Par defaut macOS limite la memoire que le GPU peut verrouiller. On veut environ 110 Go pour le GPU et laisser le reste a macOS.

- Montre-moi la valeur actuelle : `sysctl iogpu.wired_limit_mb`
- Apres mon accord : `sudo sysctl iogpu.wired_limit_mb=112640`
- Rends le reglage persistant au redemarrage avec un LaunchDaemon `/Library/LaunchDaemons/fr.local.iogpu-wired-limit.plist` qui lance cette commande au boot (RunAtLoad). Verifie la syntaxe avec `plutil -lint`.

## Etape 3 : telecharger les modeles

Modele principal :
- Depot cible : `unsloth/Qwen3.8-Flash-Next-GGUF` (alternative si absent : `bartowski/Qwen3.8-Flash-Next-GGUF`).
- Liste les quantizations disponibles avec leur taille totale (les gros modeles sont decoupes en plusieurs fichiers, additionne-les).
- Choisis la meilleure quantization dont la taille totale reste sous 85 Go (pour garder de la place au cache KV et a macOS). Ordre de preference : UD-Q4_K_XL, Q4_K_M, IQ4_XS, UD-Q3_K_XL. Annonce-moi ton choix et la taille avant de telecharger.
- Telecharge dans `/Users/amaury/DEV/SETUP-LLM/models/qwen3.8-flash-next/` avec `hf download`.

Modele de secours :
- Depot cible : `unsloth/Qwen3.8-27B-GGUF` (verifie qu'il existe), quantization Q8_0 (~30 Go).
- Telecharge dans `/Users/amaury/DEV/SETUP-LLM/models/qwen3.8-27b/`.

## Etape 4 : test en local uniquement

Lance d'abord le modele principal en ecoute sur 127.0.0.1 seulement :

```
llama-server -m <premier fichier .gguf> --alias qwen3.8-flash-next \
  --host 127.0.0.1 --port 8080 -ngl 99 -fa on --jinja \
  -c 65536 -np 1
```

(Ce premier test sert juste a valider que le modele tourne. Le decodage speculatif est regle a l'etape 4 bis et le contexte a l'etape 4 ter.)

Puis verifie :
- `curl http://127.0.0.1:8080/v1/models`
- Une requete chat en francais ("Explique le filtre de Kalman etendu en 5 lignes") et une en anglais (une fonction C++ templatee avec test), via `/v1/chat/completions`.
- Note la vitesse de generation (tokens/s, visible dans les logs de llama-server) et la memoire utilisee (`memory_pressure`, Moniteur d'activite en CLI via `top -l 1 -o mem | head -20`).
- Si la pression memoire devient critique, baisse `-c` ou passe a la quantization inferieure.

Fais la meme verification rapide avec Qwen3.8-27B Q8_0.

## Etape 4 bis : decodage speculatif (gain de vitesse sans perte de qualite)

Principe : un petit "drafter" propose plusieurs tokens, le gros modele les verifie en une passe. La sortie est identique, seule la vitesse change. Il faut un drafter entraine pour le modele cible.

### A. Qwen3.8-Flash-Next : tete MTP native (prioritaire)

Ce modele embarque sa propre tete MTP (multi-token prediction), c'est l'equivalent de DSpark pour lui. Unsloth publie le drafter en GGUF.
- Verifie dans le depot `unsloth/Qwen3.8-Flash-Next-GGUF` la presence du dossier `MTP/` et du fichier `mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf` (version "shared", plus legere). Telecharge-le a cote du modele.
- Verifie si le llama.cpp installe supporte `--spec-type draft-mtp` pour l'architecture qwen4exp (`llama-server --help | grep -i spec`, puis test reel). Le support a d'abord ete dans le fork Unsloth (github.com/unslothai/llama.cpp) avant d'arriver dans le llama.cpp principal. Si le build Homebrew ne le gere pas, compile le fork Unsloth (ou le llama.cpp principal s'il l'a integre) avec Metal, dans `/Users/amaury/DEV/SETUP-LLM/llama.cpp-mtp/`, sans toucher a l'install Homebrew.
- Lance avec en plus : `-md <chemin du fichier mtp> --spec-type draft-mtp --spec-draft-n-max 3`
- Benchmark : meme prompt de code C++ (environ 500 tokens de sortie) et meme prompt en prose francaise, avec et sans MTP, puis avec `--spec-draft-n-max` a 2, 3 et 5. Donne-moi un tableau tokens/s et taux d'acceptation.
- Garde MTP seulement si le gain est reel sur le code. Retiens la meilleure valeur de n-max dans `models.conf`.

### B. Qwen3.8-27B : DSpark / DFlash via mlx-dspark (optionnel)

Pour le modele de secours, des drafters DSpark et DFlash existent, et le projet mlx-dspark les fait tourner nativement en MLX avec un serveur compatible OpenAI.
- Trouve le depot de reference de mlx-dspark sur GitHub (plusieurs forks existent, prends celui qui a l'activite la plus recente et le plus d'etoiles, montre-moi ton choix avant d'installer).
- Installe-le dans un venv dedie `/Users/amaury/DEV/SETUP-LLM/venv-dspark` (pas dans le Python systeme).
- Teste : `mlx-dspark serve --model mlx-community/Qwen3.8-27B-8bit --host 127.0.0.1 --port 8081` (mode auto, qui choisit le meilleur drafter), puis compare les tokens/s avec le 27B sous llama.cpp.
- Si c'est nettement plus rapide, ajoute dans `start.sh` / `switch.sh` une option `27b-dspark` qui lance mlx-dspark sur le port 8080 avec `--host 0.0.0.0 --api-key <mot de passe lu dans le fichier password>` a la place de llama-server, avec le meme alias de modele pour que les clients n'aient rien a changer.

Rappel : un seul serveur a la fois sur le port 8080.

## Etape 4 ter : dimensionner le contexte pour 2 utilisateurs simultanes

Objectif : 2 utilisateurs en parallele maximum pour cette premiere phase de test, chacun avec le plus grand contexte possible. On passera peut-etre a 3 plus tard : prevois que ce soit un simple changement de parametre dans `models.conf`.

Points a comprendre et a verifier dans la doc de la version installee :
- Dans llama-server, `-np N` cree N slots (N requetes traitees en parallele) et `-c` est la taille TOTALE du cache KV. Sans option particuliere, chaque slot n'a que `c / N` tokens.
- Avec `--kv-unified` (`-kvu`), les slots partagent un seul pool de cache : un utilisateur seul peut utiliser presque tout `-c`, et la place se repartit quand ils sont plusieurs. C'est le mode voulu ici. Verifie qu'il existe (`llama-server --help | grep -i unified`) et regarde dans les logs de demarrage la taille de contexte effective par slot (ligne `n_ctx_slot` ou equivalent, ou `GET /props`).
- Quantifier le cache KV en q8_0 (`-ctk q8_0 -ctv q8_0`) divise sa taille par 2 environ pour une perte de qualite negligeable. A tester. Ne descends pas en dessous de q8_0.
- Le contexte natif de Qwen3.8-Flash-Next est de 262144 tokens. Ne depasse pas cette valeur par slot (au-dela il faut du YaRN, qui degrade la qualite).

Budget : limite GPU d'environ 110 Go (etape 2) moins les poids du modele moins une marge de 5 Go = memoire disponible pour le cache KV. Annonce-moi ce budget.

Methode :
1. Lance avec `-np 2 -kvu -ctk q8_0 -ctv q8_0 -c 131072`. Note la memoire allouee au cache KV dans les logs et deduis le cout par token.
2. Calcule la valeur de `-c` maximale qui tient dans le budget, arrondie a un multiple de 16384, plafonnee a 524288 (2 x 262144).
3. Relance avec cette valeur et fais un test de charge reel : 2 requetes simultanees (2 `curl` en arriere-plan), chacune avec un prompt long (par exemple un gros fichier source C++ concatene pour atteindre environ 60 % du contexte par slot vise), qui generent chacune environ 500 tokens. Surveille `memory_pressure` pendant le test. Aucun swap, aucun crash.
4. Mesure le debit par utilisateur et total avec 1 et 2 requetes simultanees, et le temps de traitement du prompt long (prefill). Donne-moi un tableau.
5. Refais le test de charge avec le MTP active (etape 4 bis) : le decodage speculatif avec plusieurs slots peut etre instable ou moins efficace sur certaines versions. Si ca casse ou si c'est plus lent a 2 utilisateurs, propose-moi de garder le MTP desactive ou de le reserver au mode 1 utilisateur.
6. Si le budget est trop juste pour un contexte confortable (moins de 128K par utilisateur quand ils sont 2), propose-moi le compromis : quantization du modele un cran en dessous pour liberer de la memoire au profit du contexte, avec le gain chiffre.

Retiens dans `models.conf` les valeurs finales de `-c`, `-np`, `-kvu`, `-ctk/-ctv` pour chaque modele, et ecris dans le README le contexte max garanti par utilisateur quand ils sont 2, le contexte max pour un utilisateur seul, et ce que donnerait le passage a 3 utilisateurs (contexte par utilisateur estime avec le meme budget, sans le tester).

Fais la meme chose pour Qwen3.8-27B Q8_0 (modele plus petit, donc plus de place pour le contexte).

## Etape 5 : mot de passe partage

Le Mac sera utilise sur plusieurs reseaux (maison et travail, avec des plages d'IP differentes), donc pas de filtrage par IP. A la place, un mot de passe unique que je partage avec les utilisateurs.

- Techniquement, c'est la cle API de llama-server : n'importe quelle chaine de caracteres convient, pas besoin d'une cle aleatoire illisible.
- Demande-moi le mot de passe que je veux utiliser. Si je n'en donne pas, propose une phrase de passe facile a dicter (4 mots francais separes par des tirets, par exemple). Refuse un mot de passe de moins de 12 caracteres et explique pourquoi en une phrase (le serveur sera visible par tout le reseau du travail).
- Stocke-le dans `/Users/amaury/DEV/SETUP-LLM/password` avec `chmod 600`.
- llama-server le lit via `--api-key-file /Users/amaury/DEV/SETUP-LLM/password` et ecoute sur toutes les interfaces (`--host 0.0.0.0`), pour fonctionner quel que soit le reseau.
- Cree `/Users/amaury/DEV/SETUP-LLM/set-password.sh <nouveau_mot_de_passe>` qui remplace le mot de passe et redemarre le service, pour pouvoir le changer facilement.
- Teste : une requete sans mot de passe doit renvoyer 401, une requete avec `Authorization: Bearer <mot de passe>` doit repondre.

## Etape 6 : scripts de lancement

Cree :
- `/Users/amaury/DEV/SETUP-LLM/models.conf` : pour chaque modele, chemin du .gguf, alias, et parametres retenus aux etapes 4 bis et 4 ter (`-c`, `-np`, `-kvu`, `-ctk/-ctv`, MTP).
- `/Users/amaury/DEV/SETUP-LLM/start.sh <flash|27b>` : lance llama-server avec `--host 0.0.0.0 --port 8080 --api-key-file /Users/amaury/DEV/SETUP-LLM/password`, les bons parametres du modele choisi, et logs dans `/Users/amaury/DEV/SETUP-LLM/logs/`.
- `/Users/amaury/DEV/SETUP-LLM/switch.sh <flash|27b>` : change le modele actif (met a jour le modele par defaut puis redemarre le service).
- `/Users/amaury/DEV/SETUP-LLM/status.sh` : dit si le service tourne, quel modele est charge, l'IP et l'URL d'acces, et l'occupation memoire.

## Etape 7 : demarrage automatique

- Cree un LaunchAgent `~/Library/LaunchAgents/fr.local.llm-server.plist` qui lance `start.sh` avec le modele par defaut, avec `RunAtLoad` et `KeepAlive` (redemarrage automatique en cas de crash), stdout/stderr vers `/Users/amaury/DEV/SETUP-LLM/logs/`.
- Valide avec `plutil -lint`, charge avec `launchctl bootstrap gui/$(id -u) <plist>`, verifie avec `launchctl print gui/$(id -u)/fr.local.llm-server`.
- `switch.sh` doit utiliser `launchctl kickstart -k` pour redemarrer proprement.

## Etape 8 : empecher la mise en veille (sur secteur)

Apres mon accord :
- `sudo pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 0`
- Garde la batterie en reglages normaux (`-b`), ne touche pas.
- Rappelle-moi dans le README qu'un MacBook ecran rabattu se met en veille sauf s'il est branche sur secteur ET sur un ecran externe (mode clamshell). Sans ecran externe, il faut laisser l'ecran ouvert.

## Etape 9 : pare-feu macOS

- Verifie l'etat : `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`
- S'il est actif, autorise le binaire reel de llama-server (resous le lien symbolique Homebrew avec `realpath $(which llama-server)`, ou le binaire compile) avec `--add` puis `--unblockapp` (sudo, apres mon accord).
- Ne desactive pas le pare-feu.

## Etape 10 : test depuis le reseau

- Depuis ce Mac, teste via l'IP LAN (pas 127.0.0.1) : `curl -H "Authorization: Bearer $(cat /Users/amaury/DEV/SETUP-LLM/password)" http://<IP>:8080/v1/models`
- Donne-moi la commande exacte a lancer depuis un autre PC pour verifier (version PowerShell et version bash).
- Dans CLIENTS.md, explique comment definir la variable d'environnement `MAC_LLM_PASSWORD` sur le PC client (PowerShell, bash et WSL2).
- Note dans le README : WSL2 ne resout pas toujours les noms `.local`, donc pour Hermes sous WSL2 utiliser l'IP. L'IP du Mac change selon le reseau (maison, travail) : indique dans le README comment la retrouver avec `status.sh`, et conseille une reservation DHCP sur la box de la maison.

## Etape 11 : guide de connexion pour tous les clients

Ecris `/Users/amaury/DEV/SETUP-LLM/CLIENTS.md`, un guide destine aux utilisateurs (pas a moi), adapte a l'IP, au port et aux alias reels. Pour chaque client, verifie la syntaxe actuelle dans sa documentation officielle avant de l'ecrire (ces outils changent vite), et signale ce que tu n'as pas pu tester toi-meme.

Structure du guide :

1. **Les 3 infos a connaitre** (valables pour tous les clients) : base URL `http://<IP_DU_MAC>:8080/v1`, mot de passe partage a mettre dans le champ "API key", nom du modele (les alias exposes, liste visible via `GET /v1/models`). Comment definir la variable `MAC_LLM_PASSWORD` sous PowerShell, bash et WSL2. Commande `curl` de test (PowerShell et bash).

2. **Sans rien installer** : l'interface web integree a llama-server, accessible a `http://<IP_DU_MAC>:8080` dans un navigateur. Verifie comment elle gere le mot de passe et explique-le. C'est l'option pour les collegues qui veulent juste discuter avec le modele.

3. **Agents de code en terminal**, une section courte par client avec installation, fichier de config et commande de lancement :
   - OpenCode (le client open source le plus utilise actuellement) : provider `@ai-sdk/openai-compatible` dans `opencode.json`, comme ci-dessous.
   - Qwen Code : fork open source de Gemini CLI, concu pour les modeles Qwen et compatible avec n'importe quel endpoint OpenAI. C'est l'equivalent de Gemini CLI pour ce serveur.
   - Gemini CLI : explique en deux phrases qu'il parle uniquement l'API Google (pas l'API OpenAI) et ne peut donc pas se brancher directement sur ce serveur, et renvoie vers Qwen Code qui offre la meme interface.
   - Aider : pair-programming dans le terminal, oriente git.
   - Hermes Agent (utilise sous WSL2) : endpoint personnalise compatible OpenAI.
   - OpenAI Codex CLI : verifie s'il fonctionne avec ce serveur (il utilise l'API Responses `/v1/responses` ; teste si llama-server l'expose). S'il ne marche pas, dis-le clairement plutot que de donner une config fausse.
   - Claude Code : verifie si llama-server expose un endpoint compatible Anthropic (`/v1/messages`). Si oui, documente l'usage via `ANTHROPIC_BASE_URL` et `ANTHROPIC_AUTH_TOKEN`. Si non, dis-le.

4. **Dans l'editeur** (VS Code et JetBrains) : Cline, Continue, Kilo Code. Pour chacun, ou trouver le reglage "OpenAI Compatible" et quoi y mettre. Precise que Continue peut aussi faire de l'autocompletion.

5. **Depannage** : 401 (mauvais mot de passe), timeout (mauvaise IP ou Mac en veille ou pas sur le meme reseau), reponses lentes (autre utilisateur en cours, 2 slots maximum), erreurs de tool calling (verifier que le client est en mode OpenAI-compatible et pas Ollama), contexte depasse.

6. **Bonnes pratiques** : le serveur est partage par 2 personnes en meme temps maximum, eviter de laisser tourner des agents en boucle pendant des heures, pas de donnees sensibles (le trafic n'est pas chiffre).

Exemple OpenCode (`opencode.json` du projet ou `~/.config/opencode/opencode.json` sur le PC client) :

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "mac-m5": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Mac M5 Max",
      "options": {
        "baseURL": "http://<IP_DU_MAC>:8080/v1",
        "apiKey": "{env:MAC_LLM_PASSWORD}"
      },
      "models": {
        "qwen3.8-flash-next": { "name": "Qwen3.8 Flash Next" },
        "qwen3.8-27b": { "name": "Qwen3.8 27B" }
      }
    }
  },
  "model": "mac-m5/qwen3.8-flash-next"
}
```

### Guides detailles : OpenCode, Qwen Code et Hermes Agent

En plus de CLIENTS.md, ecris deux guides pas-a-pas dedies, dans `/Users/amaury/DEV/SETUP-LLM/clients/` :
- `OPENCODE.md`
- `QWEN-CODE.md`
- `HERMES.md`

Chaque guide doit permettre a un collegue de partir de zero sur son PC et d'arriver a une session fonctionnelle, sans lire autre chose. Contenu de chacun :
1. Prerequis (version de Node.js ou autre runtime, OS supportes : Windows natif, WSL2, Linux, macOS).
2. Installation (commande officielle, verification de la version installee).
3. Configuration pour ce serveur : fichier de config complet a copier-coller avec l'IP, le port et les alias reels, emplacement exact du fichier selon l'OS, et le mot de passe via la variable `MAC_LLM_PASSWORD` (jamais en clair dans le fichier).
4. Premier lancement : commande, comment choisir le modele (Flash-Next par defaut, 27B en secours), et un premier prompt de test.
5. Usage au quotidien : les commandes et raccourcis utiles (changer de modele, reprendre une session, valider ou refuser une modification de fichier, fichier d'instructions projet du type AGENTS.md ou QWEN.md).
6. Reglages recommandes pour un modele local : limite de contexte coherente avec ce que le serveur offre a 2 utilisateurs (valeur mesuree a l'etape 4 ter), temperature, desactivation des fonctions qui appellent des services cloud si c'est possible.
7. Depannage specifique a ce client.

Pour Qwen Code en particulier :
- C'est un fork de Gemini CLI publie par l'equipe Qwen, installe en general via npm (`@qwen-code/qwen-code`, commande `qwen`) : verifie le nom du paquet et la commande dans le depot officiel QwenLM/qwen-code.
- Il se configure pour un endpoint compatible OpenAI, historiquement via les variables `OPENAI_BASE_URL`, `OPENAI_API_KEY` et `OPENAI_MODEL`, ou via un fichier `.env` / `settings.json` dans `~/.qwen/`. Verifie la methode recommandee dans la version actuelle et documente-la, avec l'alternative si elle existe.
- Au premier lancement il peut proposer une connexion a un compte Qwen ou Google : explique comment choisir l'option "OpenAI compatible" a la place et ne jamais passer par un compte cloud.

Pour Hermes Agent en particulier :
- C'est l'agent open source de Nous Research (depot NousResearch/hermes-agent, doc sur hermes-agent.nousresearch.com/docs). Ce n'est pas qu'un agent de code : il a une memoire entre les sessions, des "skills" qu'il apprend et reutilise, et une passerelle vers des messageries. Explique ces points en quelques lignes en tete du guide pour que les collegues comprennent ce qui le distingue d'OpenCode.
- Installation : documente le script officiel pour Linux / WSL2 / macOS et celui pour Windows PowerShell, ainsi que l'application Desktop si elle existe toujours. Verifie les commandes sur le site officiel. Precise que mon usage principal est sous WSL2.
- Configuration pour ce serveur : via l'assistant `hermes model` (option "Custom endpoint"), et en alternative la config manuelle dans `~/.hermes/config.yaml` (provider `custom`, `base_url`, modele par defaut) avec le mot de passe dans `~/.hermes/.env`. Verifie les noms de cles exacts dans la version actuelle et donne un fichier complet a copier-coller.
- Confidentialite : la doc indique que certains outils (vision, resume de pages web, mixture of agents) passent par OpenRouter meme quand on utilise un endpoint personnalise. Explique comment desactiver ces outils ou verifier qu'aucun appel ne part vers un service cloud, pour que tout reste sur le Mac.
- Contexte : Hermes envoie un prompt systeme et des definitions d'outils volumineux. Mesure la taille du premier prompt envoye (logs de llama-server) et indique combien de contexte il reste a l'utilisateur.
- Commandes utiles : `hermes`, `hermes model`, `hermes config`, `hermes config check`, `hermes update`, plus les commandes de session et de memoire. Montre aussi le backend de terminal (local, docker, ssh) et donne un exemple ou Hermes tourne sous WSL2 mais execute ses commandes sur une autre machine Linux via ssh.
- Teste avec Hermes une tache simple qui utilise ses outils (lire un fichier, en modifier un, lancer une commande), pour verifier que le tool calling fonctionne avec Qwen3.8-Flash-Next via llama-server.

Teste les trois guides toi-meme sur ce Mac en suivant les etapes a la lettre, depuis une installation propre de chaque client, contre le serveur via l'IP LAN et avec le mot de passe. Corrige le guide la ou une etape ne marche pas telle qu'ecrite.

### Pour tous les guides

Ecris les guides en francais, sur un ton simple, avec des blocs de commande copiables. Teste aussi Aider contre le serveur (via l'IP LAN, avec le mot de passe) : une question simple et une petite modification de fichier dans un dossier de test. Indique dans le guide quels clients ont ete testes et lesquels ne l'ont pas ete.

## Etape 12 : recap

Termine par :
- le contenu de `/Users/amaury/DEV/SETUP-LLM/README.md`
- les vitesses mesurees (tokens/s) pour chaque modele et le contexte retenu
- la liste de tout ce qui a ete modifie au niveau systeme (sysctl, pmset, pare-feu, LaunchDaemon, LaunchAgent) avec la commande pour annuler chaque modification
