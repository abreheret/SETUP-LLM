# Serveur LLM local sur le MacBook Pro M5 Max

Ce Mac (M5 Max, 128 Go de mémoire unifiée, macOS 26.6) fait tourner en continu un LLM open-weight pour le code, les maths et l'ingénierie, en français et en anglais. Il l'expose sur le réseau local par une **API compatible OpenAI**, protégée par un mot de passe partagé.

Installation faite les 19 et 20 octobre 2026, en suivant `SETUP_LLM_SERVER.md`. Pour tout réinstaller : `./install.sh` (section 9).

## 1. Ce qui est installé

| Élément | Détail |
|---|---|
| Moteur principal | `llama-server` (llama.cpp **0.7.0**, Homebrew, build 11669), API OpenAI `/v1/chat/completions`, aussi `/v1/responses` et `/v1/messages` |
| Moteur secondaire | **mlx-dspark 0.20.3** (MLX 0.32.4), dans `venv-dspark/` sur un Python 3.12 géré par `uv` (`python/`) |
| Outils Homebrew | `llama.cpp`, `hf` 2.2.0 (client Hugging Face), `uv` 0.13.2 |
| Service | LaunchAgent `fr.local.llm-server` : démarre à l'ouverture de session et redémarre après un plantage |
| Réglages système | limite GPU à 110 Go (LaunchDaemon `fr.local.iogpu-wired-limit`), pas de veille sur secteur (`pmset`) |

**Modèles** (dans `models/`, un seul chargé à la fois) :

| Profil | Modèle exposé (`model`) | Fichiers | Usage |
|---|---|---|---|
| `flash` (par défaut) | `qwen3.8-flash-next` | Qwen3.8-Flash-Next **UD-Q4_K_XL** (103,7 Gio, 4 fichiers) + tête MTP Q8_0 autonome | modèle principal : MoE 125B, environ 6B actifs, plus 51B d'embedding n-gram |
| `27b` | `qwen3.8-27b` | Qwen3.8-27B **Q8_0** GGUF (29 Go) | secours, sous llama.cpp, 2 utilisateurs en parallèle |
| `27b-dspark` | `qwen3.8-27b` | Qwen3.8-27B MLX 8 bits + drafter DFlash 2 | secours rapide pour 1 utilisateur (requêtes traitées l'une après l'autre) |

**Écarts par rapport au plan initial.** Ils ont été validés pendant l'installation :
- **UD-Q4_K_XL au lieu d'une quantization de moins de 85 Go.** Le modèle fait en réalité 177B paramètres, embedding n-gram compris : aucune quantization 4 bits ne fait moins de 85 Go.
  - L'embedding n-gram (`per_layer_token_embd.weight`, 26,8 Gio) reste sur le SSD, lu à la demande (`-ot "per_layer_token_embd\.weight=CPU"`, mmap). Il n'occupe donc pas de mémoire GPU.
  - Qualité mesurée par Unsloth : 92,3 % d'accord top-1 avec BF16, contre 88,3 % pour UD-Q3_K_XL.
- **Tête MTP autonome** (`mtp-…-Q8_0.gguf`) : la version « shared » ne se charge pas avec le llama.cpp Homebrew.
- **Réflexion plafonnée à 24 576 tokens par défaut** (`--reasoning-budget`). Sans plafond, le modèle a réfléchi plus de 40 000 tokens sur un problème sans conclure. Chaque requête peut fixer son propre plafond avec `thinking_budget_tokens` : les guides clients proposent les niveaux Medium (2 048), High (8 192) et Max (24 576).

## 2. Démarrer, arrêter, changer de modèle

Le service démarre tout seul à l'ouverture de session.

| Action | Commande |
|---|---|
| État, modèle chargé, IP, mémoire | `./status.sh` |
| Changer de modèle | `./switch.sh flash`, `./switch.sh 27b` ou `./switch.sh 27b-dspark` (10 à 30 s de rechargement) |
| Redémarrer | `launchctl kickstart -k gui/$(id -u)/fr.local.llm-server` |
| Arrêter (jusqu'au prochain démarrage) | `launchctl bootout gui/$(id -u)/fr.local.llm-server` |
| Relancer après un arrêt | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/fr.local.llm-server.plist` |
| Lancer à la main, sans le service | `./start.sh [flash|27b|27b-dspark]` (service arrêté avant) |
| Changer le mot de passe | `./set-password.sh <nouveau>` (12 caractères minimum, sans espace ; redémarre le service) |
| Journaux | `logs/llm-server.log` (serveur), `logs/launchd.*.log` (lancement) |

Tous les paramètres sont dans **`models.conf`** :
- le profil par défaut ;
- la taille du contexte ;
- le nombre d'utilisateurs simultanés (`-np`) ;
- le MTP ;
- le plafond de réflexion.

## 3. Se connecter

- **API** : `http://<IP_DU_MAC>:8080/v1`, avec l'en-tête `Authorization: Bearer <mot de passe>`. Le mot de passe est dans `password` (droits 600, exclu de git).
- **Interface web** : `http://<IP_DU_MAC>:8080`. Elle demande le mot de passe au premier accès.
- **Documentation dans l'interface web** : entrée **Documentation** sous Settings, ou directement `http://<IP_DU_MAC>:8080/?docs`. Elle reprend `CLIENTS.md` et les guides `clients/*.md`, et reste lisible sans mot de passe.
  - **D'où vient la page** : llama-server sert `webui/` (`--path`), une copie de son interface intégrée à laquelle `tools/build-webui.py` ajoute l'entrée de menu et la doc. La doc est intégrée à `index.html` : llama-server ne sert sans mot de passe que les fichiers de son interface intégrée, un fichier ajouté (`docs/…`) demanderait la clé.
  - **Navigateurs déjà venus** : l'interface est mise en cache par un service worker. Au premier passage après une modification, elle affiche « Update available » : cliquez sur **Reload**.
  - **Après une modification des fichiers `.md`** : relancez `uv run --no-project --with markdown python tools/build-webui.py`. Pas besoin de redémarrer le service.
  - **Après une mise à jour de llama.cpp** : `start.sh` détecte que la copie vient d'une autre version et sert l'interface intégrée, sans doc. Relancez le même script, puis `launchctl kickstart -k gui/$(id -u)/fr.local.llm-server`.
- **Guides pour les utilisateurs** :
  - `CLIENTS.md` : tous les clients (OpenCode, Qwen Code, Aider, Hermes, Codex, éditeurs, dépannage) ;
  - `clients/OPENCODE.md`, `clients/QWEN-CODE.md` et `clients/HERMES.md` : les guides pas à pas.
- **Test rapide** :
  ```bash
  curl -H "Authorization: Bearer $(cat /Users/amaury/DEV/SETUP-LLM/password)" http://$(ipconfig getifaddr en0):8080/v1/models
  ```

## 4. Accès réseau

- **L'IP du Mac change selon le réseau** (maison, travail). `./status.sh` affiche l'IP de `en0`/`en1` et l'URL complète. À la maison, au moment de l'installation : `192.168.1.92`.
- **Réservation DHCP conseillée à la maison.** Dans l'interface de la box, réservez une IP fixe pour l'adresse MAC du Mac (`ifconfig en0 | grep ether`). Les clients n'auront plus à changer leur configuration.
- **Nom Bonjour** : `MacBook-Pro-de-Amaury.local`. **WSL2 ne résout pas toujours les noms `.local`** : pour Hermes sous WSL2, et en cas de doute, utilisez l'IP.
- **Pare-feu macOS** : désactivé au moment de l'installation, donc rien à autoriser. S'il est activé un jour, autorisez le vrai binaire de `llama-server` (`realpath $(which llama-server)`) et le Python de `venv-dspark` avec `socketfilterfw --add` puis `--unblockapp`. `install.sh` le fait. Ne désactivez pas le pare-feu pour contourner un blocage.
- **Le trafic n'est pas chiffré** (HTTP). N'envoyez pas de données sensibles, en particulier sur le réseau du travail.

## 5. Veille et écran

- **Sur secteur, le Mac ne se met plus en veille** (`pmset -c sleep 0`). L'écran s'éteint après 10 min, et le serveur continue de tourner.
- **Sur batterie, les réglages sont inchangés** : le Mac se met en veille, et le serveur devient injoignable.
- **Un MacBook écran rabattu se met en veille**, sauf s'il est branché **à la fois sur secteur et sur un écran externe** (mode clamshell). Sans écran externe, **laissez l'écran ouvert**.
- `start.sh` lance le serveur sous `caffeinate -s`, qui empêche aussi la veille système sur secteur tant qu'il tourne.

## 6. Performances mesurées

Mesures du 20 octobre 2026, le Mac sur secteur, avec `tools/bench.py` et `tools/load.py`. Les vitesses de génération sont en tokens/s.

**Génération, prompts courts** (environ 650 à 700 tokens générés, 3 essais chacun) :

| Configuration | Code C++ | Prose française |
|---|---|---|
| Flash-Next, sans MTP | 43,8 | 40,3 |
| **Flash-Next + MTP `n-max 2` (retenu)** | **61,4** | **45,5** |
| Flash-Next + MTP `n-max 3` | 64,3 | 40,4 |
| Flash-Next + MTP `n-max 5` | 67,3 | 34,1 |
| 27B Q8_0, llama.cpp | 14,1 | 13,1 |
| 27B 8 bits, mlx-dspark DFlash 2 | 47,5 | 25,7 |

Tokens proposés par le MTP et acceptés : 89 % sur le code, 57 % sur la prose avec `n-max 2`, et environ 61 % à 60K tokens de contexte.

**Charge, prompts longs** (500 tokens générés) :

| Scénario | Lecture du prompt | Génération | Durée totale |
|---|---|---|---|
| Flash-Next, 1 utilisateur, prompt de 60K | 650 tok/s (92 s) | 45,7 | 103 s |
| Flash-Next, 2 utilisateurs, prompts de 60K | environ 550 tok/s chacun | 33,0 au total | 225 s |
| Flash-Next, 1 utilisateur, prompt de 157K | 518 tok/s (303 s) | 31,1 | 319 s |
| Flash-Next, 2 utilisateurs, prompts de 157K | environ 405 tok/s chacun | 25,6 au total | 13 min |
| Flash-Next, 2 utilisateurs, prompts courts | – | 75,6 au total | – |
| 27B llama.cpp, 1 utilisateur, prompt de 60K | 451 tok/s | 13,6 | 169 s |
| 27B llama.cpp, 2 utilisateurs, prompts de 60K | environ 350 tok/s chacun | 9,7 au total | 386 s |
| 27B mlx-dspark, 1 utilisateur, prompt de 60K | – | – | 153 s |

**Mémoire** : Flash-Next occupe 97 Go sur le GPU (limite : 110 Go), dont 10,4 Go de cache KV et 5,5 Go de tampons de calcul. Pendant les tests de charge, il restait au moins 19 % de mémoire libre, sans swap. Le 27B Q8_0 occupe 46 Go.

## 7. Contexte retenu

Paramètres communs aux profils llama.cpp (`CTX_ARGS` dans `models.conf`) : `-np 2 -kvu --kv-unified-per-slot 262144 -ctk q8_0 -ctv q8_0 -c 524288`.

- **2 utilisateurs en même temps : 262 144 tokens garantis à chacun.** C'est le contexte natif du modèle, qu'on ne dépasse pas, pour ne pas avoir à utiliser YaRN.
- **Un utilisateur seul : 262 144 tokens**, plafonnés par `--kv-unified-per-slot`.
- **Coût du cache KV en q8_0** : environ 18,4 Kio par token pour Flash-Next (cache principal, index de l'attention creuse et MTP), et 34 Kio par token pour le 27B. Les 524 288 tokens coûtent environ 9,4 Gio pour Flash-Next.
- **Passer à 3 utilisateurs** (`-np 3` dans `CTX_ARGS`, non testé) : environ 174K tokens garantis par utilisateur avec le même `-c 524288`, et toujours 262K pour un utilisateur seul.
  - Pour donner 262K à chacun des 3, il faudrait `-c 786432`, soit environ 14 Gio de cache. Ça tient sur le GPU, mais la RAM deviendrait juste, avec l'embedding n-gram en cache disque.
  - Le 27B tiendrait 3 × 262K sans difficulté.
- **Profil `27b-dspark`** : jusqu'à 262 144 tokens par requête (`--context-window`), une requête à la fois.
- **Lecture des longs prompts** : 400 à 650 tok/s. La première requête d'une session d'agent (7 000 à 12 000 tokens d'instructions) prend 10 à 20 s, puis le serveur garde ce début en cache.

## 8. Modifications système et comment les annuler

| Modification | Annulation |
|---|---|
| `sysctl iogpu.wired_limit_mb=112640` (limite GPU, 0 par défaut) | `sudo sysctl iogpu.wired_limit_mb=0` |
| LaunchDaemon `/Library/LaunchDaemons/fr.local.iogpu-wired-limit.plist` (réapplique la limite au démarrage) | `sudo launchctl bootout system/fr.local.iogpu-wired-limit && sudo rm /Library/LaunchDaemons/fr.local.iogpu-wired-limit.plist` |
| `pmset -c sleep 0 disksleep 0 displaysleep 10 powernap 0` (avant : `sleep 1`, `disksleep 10`, `powernap 1`) | `sudo pmset -c sleep 1 disksleep 10 displaysleep 10 powernap 1` |
| Pare-feu macOS | **non modifié** (désactivé au moment de l'installation) |
| LaunchAgent `~/Library/LaunchAgents/fr.local.llm-server.plist` | `launchctl bootout gui/$(id -u)/fr.local.llm-server && rm ~/Library/LaunchAgents/fr.local.llm-server.plist` |
| Paquets Homebrew `llama.cpp` (+ `ggml`, `libomp`), `hf`, `uv` | `brew uninstall llama.cpp hf uv && brew autoremove` |
| Jeton Hugging Face `~/.cache/huggingface/token` | `hf auth logout`, puis révoquez le jeton sur huggingface.co |
| Modèles (environ 175 Go), venv, Python, journaux, mot de passe | `rm -rf models venv-dspark python logs password` dans ce dossier |

## 9. Réinstaller : `install.sh`

```bash
cd /Users/amaury/DEV/SETUP-LLM
./install.sh            # tout
./install.sh --help     # options : --no-dspark, --no-models, --no-sudo, --yes
```

Le script rejoue toute l'installation et peut être relancé sans risque : chaque étape vérifie d'abord ce qui est déjà fait. Il :
1. vérifie le matériel ;
2. installe Homebrew, `llama.cpp`, `hf` et `uv`, et contrôle que llama.cpp gère `qwen4exp` et le MTP ;
3. règle la limite GPU et le LaunchDaemon (`sudo`) ;
4. télécharge les modèles, avec vérification de la taille et du sha256, et 5 essais en cas de coupure ;
5. installe mlx-dspark et le lien `models/mlx-alias/qwen3.8-27b` ;
6. crée le mot de passe s'il n'existe pas ;
7. installe le LaunchAgent ;
8. règle la veille avec `pmset` (`sudo`) ;
9. autorise les serveurs dans le pare-feu s'il est actif (`sudo`) ;
10. vérifie l'accès via l'IP du réseau (200 avec le mot de passe, 401 sans) ;
11. construit `webui/` (interface web avec la documentation clients) et redémarre le service pour la servir.

Il demande confirmation avant chaque `sudo` et chaque gros téléchargement, sauf avec `--yes`. Installé dans un autre dossier que `/Users/amaury/DEV/SETUP-LLM`, il adapte les chemins absolus des scripts.

Avant de lancer un gros téléchargement, connectez-vous à Hugging Face, sinon le débit est limité :
```bash
hf auth login --token "$(pbpaste)"
```
Il faut un jeton de type « Read », copié dans le presse-papiers.

## 10. Fichiers du dépôt

| Fichier | Rôle |
|---|---|
| `SETUP_LLM_SERVER.md` | le plan d'installation d'origine |
| `install.sh` | installation complète et idempotente |
| `models.conf` | profils de modèles et paramètres serveur |
| `start.sh`, `switch.sh`, `status.sh`, `set-password.sh` | exploitation au quotidien |
| `system/fr.local.llm-server.plist` | modèle du LaunchAgent (`@ROOT@` remplacé par `install.sh`) |
| `system/fr.local.iogpu-wired-limit.plist` | LaunchDaemon de la limite GPU |
| `tools/bench.py` | vitesse de génération (code et prose) : `PORT=8080 MODEL=qwen3.8-flash-next python3 tools/bench.py essai 3` |
| `tools/load.py` | test de charge avec 1 puis 2 utilisateurs et prompts longs : `python3 tools/load.py essai 60000` |
| `CLIENTS.md`, `clients/*.md` | guides de connexion pour les utilisateurs |
| `tools/build-webui.py` | construit `webui/` : copie de l'interface web de llama-server, avec l'entrée Documentation et la doc clients en HTML |
| `webui-src/` | sources ajoutées à cette copie : `inject.js` (entrée de menu et affichage de la doc), `docs.css` (style de la doc) |

Ne sont pas versionnés (voir `.gitignore`) : `models/`, `logs/`, `password`, `venv-dspark/`, `python/`, `webui/` (régénéré par `tools/build-webui.py`).

## 11. Problèmes connus

- **Claude Code ne fonctionne pas** avec le modèle principal (`Jinja Exception: System message must be at the beginning`). Utilisez OpenCode ou Qwen Code.
- **Un très long prompt bloque l'autre utilisateur.** Le serveur lit les prompts l'un après l'autre : deux prompts de 157K envoyés en même temps mettent environ 13 minutes.
- **Command Line Tools** : l'éditeur de liens refuse le SDK par défaut, `MacOSX27.0.sdk` (`tapi error: malformed file`). Compilez avec `-isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`, ou mettez à jour les Command Line Tools (`softwareupdate --list`).
- **Python 3.15 Homebrew (OpenSSL 4.0)** : des délais dépassés pendant l'établissement des connexions chiffrées ont été constatés avec `pip` et `hf`. C'est pourquoi mlx-dspark tourne sur un Python 3.12 géré par `uv`.
- **Mot de passe en clair dans la liste des processus pour le profil `27b-dspark`** : mlx-dspark n'accepte la clé qu'en argument, elle est donc visible avec `ps` pour les autres comptes de ce Mac.
