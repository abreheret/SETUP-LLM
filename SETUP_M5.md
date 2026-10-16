# Setup MacBook Pro M5 Max 128 Go - instructions pour Claude Code

## Contexte

Machine neuve : MacBook Pro M5 Max, 128 Go de mémoire unifiée, SSD 2 To, macOS.
Utilisateur : ingénieur C++ senior en computer vision / ADAS (OpenCV, Eigen, CMake, pybind11).

Objectif : installer en ligne de commande une stack complète avec deux volets.
1. LLM local sur macOS : Ollama (backend MLX), LM Studio, modèles de code, agent OpenCode.
2. Dev C++ Linux : OrbStack + conteneur Ubuntu 20.04 ARM64 avec GCC 9.4, utilisé via VS Code Dev Containers. Pas de GUI Linux : le debug visuel passe par des images écrites sur disque et un flux MJPEG sur localhost.

## Règles de travail

- Avance phase par phase. A la fin de chaque phase, lance les commandes de vérification et fais-moi un court bilan avant de passer à la suivante.
- Ne devine jamais un nom de paquet, de cask, de modèle ou une clé de config. Si tu as un doute, vérifie dans la doc officielle ou avec `brew search`, `brew info`, la page ollama.com/library, etc. Si tu ne trouves pas, dis-le et propose une alternative au lieu d'inventer.
- Les noms de modèles bougent vite : vérifie ce qui existe réellement aujourd'hui avant chaque `ollama pull`. Si un modèle listé ici n'existe pas sous ce nom, prends l'équivalent le plus proche et explique ton choix.
- Avant de télécharger un modèle, vérifie l'espace disque libre (`df -h /`) et annonce la taille approximative du téléchargement.
- Toute commande qui demande `sudo` ou un mot de passe : ne la lance pas toi-même, affiche-la et demande-moi de la lancer.
- N'écrase aucun fichier de config existant (`~/.zshrc`, configs existantes) sans en faire une sauvegarde `.bak` avant.
- Idempotence : si un outil est déjà installé, ne le réinstalle pas, contente-toi de vérifier sa version.

## Phase 0 - Vérification des prérequis

Ces éléments sont normalement déjà installés à la main par l'utilisateur. Vérifie-les seulement :

```bash
xcode-select -p
brew --version
git --version
uname -m            # doit afficher arm64
sysctl -n hw.memsize
df -h /
```

Si Homebrew n'est pas dans le PATH, vérifie que `~/.zprofile` contient bien `eval "$(/opt/homebrew/bin/brew shellenv)"`.

## Phase 1 - Outils de base

```bash
brew update
brew install cmake ninja wget jq htop tree git-lfs
brew install --cask visual-studio-code
brew install --cask orbstack
brew install --cask lm-studio
```

Puis les extensions VS Code utiles (vérifie que la commande `code` est disponible, sinon indique-moi comment l'activer) :

```bash
code --install-extension ms-vscode-remote.remote-containers
code --install-extension llvm-vs-code-extensions.vscode-clangd
code --install-extension ms-vscode.cmake-tools
code --install-extension ms-python.python
```

Vérification : versions de cmake, ninja, `code --list-extensions`, présence des apps OrbStack et LM Studio dans /Applications.

## Phase 2 - Ollama

Installe Ollama (vérifie s'il vaut mieux la formule ou le cask selon la doc actuelle) et lance-le en service de fond :

```bash
brew install ollama
brew services start ollama
curl -s http://localhost:11434/api/version
```

Vérifie dans la doc ou les notes de version qu'Ollama utilise bien le backend MLX sur M5 et si une option est nécessaire pour l'activer.

Contexte par défaut : Ollama démarre avec une fenêtre de contexte trop petite pour un usage agentique. Vérifie dans la doc actuelle la bonne méthode (variable d'environnement type `OLLAMA_CONTEXT_LENGTH` pour le service, ou `num_ctx` dans un Modelfile). Cible : 32768 tokens minimum, 65536 si possible.

## Phase 3 - Modèles

Vérifie d'abord les noms exacts disponibles, puis télécharge dans cet ordre (annonce la taille avant chaque pull) :

1. Qwen 3.6 35B-A3B (MoE, modèle agent par défaut, rapide)
2. Qwen 3.6 27B dense (qualité max pour le code)
3. Devstral (Mistral, bon en tool calling, bon en français)

Pour chaque modèle utilisé par l'agent, crée une variante avec contexte étendu si le réglage global ne suffit pas :

```bash
mkdir -p ~/llm/modelfiles
cat > ~/llm/modelfiles/qwen-agent.Modelfile <<'EOF'
FROM <nom_exact_du_modele_qwen_moe>
PARAMETER num_ctx 32768
EOF
ollama create qwen-agent -f ~/llm/modelfiles/qwen-agent.Modelfile
```

Fais la même chose pour le 27B dense (`qwen-dense-agent`) et pour Devstral (`devstral-agent`).

Vérification : `ollama list`, puis un test rapide en français sur chaque modèle, par exemple :

```bash
ollama run qwen-agent "Ecris une fonction C++17 qui calcule l'IoU de deux cv::Rect2f. Réponds en français."
```

Mesure et rapporte le débit (tokens/s) affiché avec `ollama run --verbose`.

## Phase 4 - OpenCode

Installe OpenCode avec la méthode recommandée par la doc officielle (opencode.ai), puis configure le provider Ollama local dans la config globale (`~/.config/opencode/opencode.json`, vérifie l'emplacement et le schéma exact dans la doc). Configuration visée :

- provider local Ollama, compatible OpenAI, baseURL `http://localhost:11434/v1`
- modèles déclarés : `qwen-agent` (défaut), `qwen-dense-agent`, `devstral-agent`
- pas de clé API nécessaire pour le local

Vérification : lancer `opencode` dans un dossier de test vide, lui demander de créer un `hello.cpp` et un `CMakeLists.txt`, vérifier que les fichiers sont bien écrits (preuve que le tool calling fonctionne). Si l'agent s'arrête au milieu d'une réponse JSON, c'est en général la fenêtre de contexte : revenir à la phase 2.

## Phase 5 - Environnement C++ Linux (OrbStack)

Vérifie qu'OrbStack tourne et que `docker` répond :

```bash
docker version
docker run --rm --platform linux/arm64 ubuntu:20.04 uname -m
```

Vérifie aussi que l'émulation x86_64 via Rosetta est active (réglage OrbStack), pour les libs qui n'existent qu'en amd64 :

```bash
docker run --rm --platform linux/amd64 ubuntu:20.04 uname -m
```

Crée ensuite un template de projet dans `~/dev/templates/cpp-ubuntu2004/` avec :

1. `.devcontainer/Dockerfile` basé sur `ubuntu:20.04` (ARM64), avec `DEBIAN_FRONTEND=noninteractive`, installant `build-essential` (GCC 9.4 par défaut), `cmake`, `ninja-build`, `gdb`, `git`, `pkg-config`, `clangd`, `libopencv-dev`, `libeigen3-dev`, `python3-dev`, `python3-pip`, `pybind11-dev`. Ajoute un utilisateur non root dont l'UID/GID correspond à celui du Mac pour éviter les problèmes de droits sur les fichiers montés. Note : sur Ubuntu 20.04 la version de cmake d'apt est ancienne, propose une solution (pip ou dépôt Kitware) si besoin.
2. `.devcontainer/devcontainer.json` : build à partir du Dockerfile, montage d'un dossier `debug/` du projet sur `/debug`, port 8080 forwardé, extensions clangd et CMake Tools installées dans le conteneur.
3. `CMakeLists.txt` minimal avec une option `DEBUG_VIEW` (valeurs `disk`, `stream`, `none`) qui définit la macro correspondante.
4. `include/debug_view.hpp` : interface `IDebugView` avec `show(name, cv::Mat)`, une implémentation disque (`cv::imwrite` numéroté dans `/debug`), une implémentation stream (serveur MJPEG sur le port 8080 avec cpp-httplib header-only, à récupérer depuis le dépôt officiel yhirose/cpp-httplib en version taguée), et une implémentation no-op.
5. `src/main.cpp` de démo qui génère des images synthétiques (pas de webcam dans le conteneur) et les affiche via `DebugView`.
6. Un `README.md` court qui explique comment copier le template pour un nouveau projet.

Le code doit compiler avec GCC 9.4 : reste en C++17, pas de fonctionnalités C++20.

Vérification complète :

```bash
cd ~/dev/templates/cpp-ubuntu2004
docker build -t cpp-ubuntu2004 -f .devcontainer/Dockerfile .
docker run --rm -v "$PWD":/src -w /src cpp-ubuntu2004 bash -c "gcc --version && cmake -B build -G Ninja -DDEBUG_VIEW=disk && cmake --build build && ./build/demo"
ls debug/
```

Puis teste le mode stream avec `-p 8080:8080` et donne-moi l'URL à ouvrir dans Safari.

## Phase 6 - Bilan final

Donne-moi un récapitulatif avec :
- la liste des outils installés et leurs versions
- les modèles installés, leur taille disque et le débit mesuré
- l'emplacement des fichiers de config créés ou modifiés (et des sauvegardes .bak)
- les points qui n'ont pas pu être faits ou vérifiés, et pourquoi
- les commandes à retenir pour l'usage quotidien (démarrer/arrêter Ollama, lancer OpenCode, ouvrir un projet dans le Dev Container)
