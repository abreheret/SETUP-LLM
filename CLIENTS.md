# Se connecter au serveur LLM du Mac M5 Max

Ce guide explique comment utiliser, depuis votre PC, les modèles qui tournent sur le Mac M5 Max d'Amaury.
Vous n'avez rien à installer côté serveur : il suffit de pointer votre outil vers le Mac.

## 1. Les 3 infos à connaître

Valables pour tous les clients :

| Info | Valeur |
|---|---|
| Base URL (API compatible OpenAI) | `http://192.168.1.92:8080/v1` |
| Clé API (« API key ») | le mot de passe partagé, que l'on vous a transmis |
| Nom du modèle | `qwen3.8-flash-next` (modèle principal) ou `qwen3.8-27b` (secours) |

- **Un seul modèle est chargé à la fois.** `GET /v1/models` indique lequel est disponible en ce moment.
- **L'IP change selon le réseau** (maison, bureau). Si elle a changé, demandez la nouvelle à Amaury : elle est affichée par `status.sh` sur le Mac.
- **Le nom `MacBook-Pro-de-Amaury.local`** peut marcher sur certains réseaux, mais pas sous WSL2. **Utilisez l'IP.**

### Définir la variable `MAC_LLM_PASSWORD`

Ne mettez jamais le mot de passe en clair dans un fichier de configuration. Rangez-le dans une variable d'environnement, que tous les exemples de ce guide utilisent.

**Windows PowerShell :**
```powershell
# Pour la session en cours
$env:MAC_LLM_PASSWORD = "<MOT_DE_PASSE>"

# De façon permanente pour votre compte (ouvrez un nouveau terminal ensuite)
[Environment]::SetEnvironmentVariable("MAC_LLM_PASSWORD", "<MOT_DE_PASSE>", "User")
```

**Linux / macOS (bash ou zsh) :**
```bash
# Remplacez ~/.bashrc par ~/.zshrc si votre shell est zsh
echo 'export MAC_LLM_PASSWORD="<MOT_DE_PASSE>"' >> ~/.bashrc
source ~/.bashrc
```

**WSL2.** Deux possibilités :

1. Définir la variable dans WSL, comme sous Linux :
   ```bash
   echo 'export MAC_LLM_PASSWORD="<MOT_DE_PASSE>"' >> ~/.bashrc
   source ~/.bashrc
   ```
2. Ou réutiliser la variable Windows, en la transmettant à WSL avec `WSLENV`. Dans PowerShell, après avoir défini `MAC_LLM_PASSWORD` comme ci-dessus :
   ```powershell
   $cur = [Environment]::GetEnvironmentVariable("WSLENV", "User")
   $new = if ($cur) { "$cur`:MAC_LLM_PASSWORD/u" } else { "MAC_LLM_PASSWORD/u" }
   [Environment]::SetEnvironmentVariable("WSLENV", $new, "User")
   ```
   Fermez ensuite toutes les fenêtres WSL (`wsl --shutdown`), puis rouvrez-en une.

### Tester la connexion

**PowerShell** (utilisez bien `curl.exe` : dans PowerShell, `curl` seul est un alias d'une autre commande) :
```powershell
curl.exe -H "Authorization: Bearer $env:MAC_LLM_PASSWORD" http://192.168.1.92:8080/v1/models
```
ou, sans curl :
```powershell
Invoke-RestMethod -Uri http://192.168.1.92:8080/v1/models -Headers @{ Authorization = "Bearer $env:MAC_LLM_PASSWORD" }
```

**bash / WSL2 :**
```bash
curl -H "Authorization: Bearer $MAC_LLM_PASSWORD" http://192.168.1.92:8080/v1/models
```

Une première question, en bash :
```bash
curl http://192.168.1.92:8080/v1/chat/completions \
  -H "Authorization: Bearer $MAC_LLM_PASSWORD" -H "Content-Type: application/json" \
  -d '{"model":"qwen3.8-flash-next","messages":[{"role":"user","content":"Bonjour !"}]}'
```

Ce que vous devez obtenir :
- **Une réponse JSON avec `"id":"qwen3.8-flash-next"`** (ou `qwen3.8-27b`) : tout fonctionne.
- **`401`** : le mot de passe est faux, ou la variable n'est pas définie dans ce terminal.
- **Rien, puis un délai dépassé (timeout)** : mauvaise IP, Mac en veille, ou vous n'êtes pas sur le même réseau.

### Niveau de réflexion

Qwen3.8 réfléchit avant de répondre. Chaque requête peut fixer deux réglages :
- **`reasoning_effort`** dit au modèle à quel point réfléchir : `medium`, `high` ou `xhigh`. N'envoyez jamais `max` : le modèle refuse la requête avec une erreur 500.
- **`thinking_budget_tokens`** fixe le plafond : une fois atteint, le serveur arrête la réflexion et le modèle écrit sa réponse.

| Niveau | `reasoning_effort` | `thinking_budget_tokens` |
|---|---|---|
| Medium | `medium` | 2048 |
| High | `high` | 8192 |
| Max (**conseillé par défaut**) | `xhigh` | 24576 |
| rien envoyé | `xhigh` | 24576 (plafond par défaut du serveur, = Max) |

Les guides OpenCode, Qwen Code et Hermes configurent Max par défaut, avec une commande pour changer de niveau. Exemple en bash :
```bash
curl http://192.168.1.92:8080/v1/chat/completions \
  -H "Authorization: Bearer $MAC_LLM_PASSWORD" -H "Content-Type: application/json" \
  -d '{"model":"qwen3.8-flash-next","messages":[{"role":"user","content":"Bonjour !"}],"reasoning_effort":"medium","thinking_budget_tokens":2048}'
```

**Dans l'interface web**, le bouton de réflexion (icône ampoule, à gauche du nom du modèle) propose Low (512), Medium (2 048), High (8 192) et Max. Max n'envoie aucun plafond : c'est celui du serveur qui s'applique, 24 576 tokens.

## Ce qui a été testé

Tests faits le 20 octobre 2026, depuis le Mac lui-même mais via l'IP du réseau (`192.168.1.92`) et avec le mot de passe, à partir d'une installation neuve de chaque client :

| Client | Version | Résultat |
|---|---|---|
| OpenCode | 1.19.3 | ✅ testé : lecture, modification de fichier, commande shell |
| Qwen Code | 0.25.3 | ✅ testé : lecture, modification de fichier, commande shell |
| Hermes Agent | 0.22.2 | ✅ testé : lecture, modification de fichier, commande shell, aucune connexion hors du Mac |
| Aider | 0.86.2 | ✅ testé : question, puis modification de fichier avec commit git |
| Codex CLI | 0.163.0 | ✅ testé : lecture, modification de fichier, commande shell (API `/v1/responses`) |
| Claude Code | 2.1.304 | ❌ ne fonctionne pas avec le modèle principal (voir plus bas) |
| Interface web | intégrée | ⚠️ gestion du mot de passe vérifiée dans le code de la page, pas en cliquant |
| Cline, Continue, Kilo Code | – | ⚠️ non testés (extensions d'éditeur), configuration tirée de leur documentation officielle |
| Gemini CLI | – | ❌ incompatible (voir plus bas) |
| Clients Windows, PowerShell | – | ⚠️ non testés (pas de PC Windows pendant l'installation) |

## 2. Sans rien installer : l'interface web

Ouvrez **`http://192.168.1.92:8080`** dans un navigateur. C'est l'interface de chat intégrée au serveur, la bonne option pour discuter avec le modèle sans rien installer.

- **Au premier accès**, le serveur répond « accès refusé » et l'interface affiche une fenêtre **« Enter API Key »**. Tapez le mot de passe partagé. L'interface le vérifie, puis se connecte.
- **Le mot de passe est mémorisé dans votre navigateur**, dans les réglages de l'interface. Vous pouvez le changer dans **Settings → API Key**.
- **Les conversations restent dans votre navigateur**, pas sur le serveur.
- **Cette documentation est disponible dans l'interface** : entrée **Documentation** sous Settings, ou directement `http://192.168.1.92:8080/?docs`. Elle est lisible sans mot de passe. On y trouve ce guide, puis les guides pas à pas OpenCode, Qwen Code et Hermes.

## 3. Agents de code en terminal

### OpenCode

Le client open source le plus utilisé. **Guide pas à pas : [`clients/OPENCODE.md`](clients/OPENCODE.md).**

En résumé :
1. Installez-le avec `npm install -g opencode-ai`.
2. Copiez la configuration ci-dessous dans `~/.config/opencode/opencode.json`, ou dans `opencode.json` à la racine du projet. Le guide donne une commande qui crée ce fichier, avec en plus les niveaux de réflexion Medium, High et Max (**Ctrl+T** pour changer).
3. Lancez `opencode`.

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "mac-m5": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Mac M5 Max",
      "options": {
        "baseURL": "http://192.168.1.92:8080/v1",
        "apiKey": "{env:MAC_LLM_PASSWORD}"
      },
      "models": {
        "qwen3.8-flash-next": { "name": "Qwen3.8 Flash Next", "limit": { "context": 262144, "output": 32768 } },
        "qwen3.8-27b": { "name": "Qwen3.8 27B", "limit": { "context": 262144, "output": 32768 } }
      }
    }
  },
  "model": "mac-m5/qwen3.8-flash-next",
  "small_model": "mac-m5/qwen3.8-flash-next"
}
```

### Qwen Code

Un fork de Gemini CLI publié par l'équipe Qwen, qui accepte n'importe quel serveur compatible OpenAI. C'est l'équivalent de Gemini CLI pour ce serveur. **Guide pas à pas : [`clients/QWEN-CODE.md`](clients/QWEN-CODE.md).**

En résumé :
1. Installez-le avec `npm install -g @qwen-code/qwen-code@latest` (Node.js 22 ou plus).
2. Créez `~/.qwen/settings.json` avec la commande du guide, qui règle aussi le niveau de réflexion.
3. Lancez `qwen`.

### Gemini CLI

Gemini CLI ne parle qu'aux services de Google (compte Google, clé Gemini API ou Vertex AI). Il ne sait pas utiliser une API compatible OpenAI, donc il ne peut pas se brancher sur ce serveur. Utilisez **Qwen Code**, qui offre la même interface.

### Aider

Du pair-programming dans le terminal, très orienté git : chaque modification est commitée.

```bash
python -m pip install aider-install
aider-install
```

Configuration :
```bash
export OPENAI_API_BASE=http://192.168.1.92:8080/v1
export OPENAI_API_KEY=$MAC_LLM_PASSWORD
```
Sous PowerShell, pour la session en cours :
```powershell
$env:OPENAI_API_BASE = "http://192.168.1.92:8080/v1"
$env:OPENAI_API_KEY = $env:MAC_LLM_PASSWORD
```

Pour qu'Aider connaisse la taille de contexte, créez `~/.aider.model.metadata.json` :
```json
{
  "openai/qwen3.8-flash-next": { "max_input_tokens": 262144, "max_output_tokens": 32768, "input_cost_per_token": 0, "output_cost_per_token": 0, "litellm_provider": "openai", "mode": "chat" },
  "openai/qwen3.8-27b": { "max_input_tokens": 262144, "max_output_tokens": 32768, "input_cost_per_token": 0, "output_cost_per_token": 0, "litellm_provider": "openai", "mode": "chat" }
}
```

Lancement, depuis le dossier du projet (le préfixe `openai/` est obligatoire) :
```bash
aider --model openai/qwen3.8-flash-next --analytics-disable
```
Aider affiche aussi la réflexion du modèle avant sa réponse : c'est normal.

### Hermes Agent

L'agent de Nous Research : mémoire d'une session à l'autre, compétences (« skills ») réutilisables, passerelle vers les messageries. **Guide pas à pas, avec la configuration qui garde tout sur le Mac : [`clients/HERMES.md`](clients/HERMES.md).**

### OpenAI Codex CLI

Il fonctionne : le serveur expose l'API Responses (`/v1/responses`) dont Codex a besoin.

```bash
npm install -g @openai/codex
```

Fichier `~/.codex/config.toml` (sous Windows : `%USERPROFILE%\.codex\config.toml`) :
```toml
model = "qwen3.8-flash-next"
model_provider = "mac-m5"
model_context_window = 262144

[model_providers.mac-m5]
name = "Mac M5 Max"
base_url = "http://192.168.1.92:8080/v1"
env_key = "MAC_LLM_PASSWORD"
wire_api = "responses"
```

Lancez `codex`, ou `codex exec "votre demande"` pour une seule tâche.

### Claude Code

Le serveur expose bien un point d'accès compatible Anthropic (`/v1/messages`). **Pourtant, Claude Code ne fonctionne pas avec le modèle principal**, testé avec Claude Code 2.1.304 : la première requête échoue avec `Jinja Exception: System message must be at the beginning`. Claude Code envoie des messages système au milieu de la conversation, et le modèle de conversation de Qwen les refuse.

De plus, Anthropic ne prend pas en charge l'utilisation de Claude Code avec des modèles autres que Claude. **Utilisez OpenCode ou Qwen Code à la place.**

## 4. Dans l'éditeur (VS Code, JetBrains)

Ces extensions n'ont pas été testées. Leur configuration vient de leur documentation officielle.

**Cline** (VS Code ; une version JetBrains existe aussi) :
1. Cliquez sur l'icône ⚙️ du panneau Cline.
2. Choisissez **API Provider : OpenAI Compatible**.
3. Remplissez les champs :
   - **Base URL** : `http://192.168.1.92:8080/v1`
   - **API Key** : le mot de passe partagé
   - **Model ID** : `qwen3.8-flash-next`
4. Dans **Model Configuration**, mettez **Context Window** à `262144`. Cochez **Image Support** : le modèle principal lit les images (pas le modèle de secours `qwen3.8-27b`).

**Continue** (VS Code et JetBrains). Modifiez `~/.continue/config.yaml` (sous Windows : `%USERPROFILE%\.continue\config.yaml`) :
```yaml
name: Mac M5
version: 1.0.0
schema: v1
models:
  - name: Qwen3.8 Flash Next (Mac M5)
    provider: openai
    model: qwen3.8-flash-next
    apiBase: http://192.168.1.92:8080/v1
    apiKey: ${{ secrets.MAC_LLM_PASSWORD }}
    roles: [chat, edit, apply]
    defaultCompletionOptions:
      contextLength: 262144
```

- **Le mot de passe.** Continue doit trouver un secret nommé `MAC_LLM_PASSWORD`. Je n'ai pas pu vérifier dans sa documentation comment il le lit en local : c'est probablement dans un fichier `~/.continue/.env` contenant `MAC_LLM_PASSWORD=...`. Si ça ne marche pas, mettez le mot de passe directement à la place de `${{ secrets.MAC_LLM_PASSWORD }}`. Ce fichier est personnel : ne le mettez jamais dans un dépôt git.
- **L'autocomplétion.** Continue sait aussi faire de l'autocomplétion de code : ajoutez `autocomplete` dans `roles`. Ce n'est pas conseillé ici. Chaque frappe envoie une requête au Mac, qui sert déjà deux utilisateurs, et Qwen3.8 n'est pas un modèle spécialisé dans l'autocomplétion.

**Kilo Code** (VS Code) :
1. Ouvrez **Settings** (icône ⚙️), onglet **Providers**, puis **Custom provider** en bas de la page.
2. Remplissez les champs :
   - **Provider API** : OpenAI Compatible
   - **Base URL** : `http://192.168.1.92:8080/v1`
   - **API key** : le mot de passe partagé
3. Cliquez sur **Fetch models** et choisissez `qwen3.8-flash-next`.

## 5. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| `401` / « Invalid API Key » / « access denied » | mauvais mot de passe, ou variable `MAC_LLM_PASSWORD` absente de ce terminal | `echo $MAC_LLM_PASSWORD` (bash) ou `echo $env:MAC_LLM_PASSWORD` (PowerShell) ; rouvrez le terminal après un `SetEnvironmentVariable` |
| Délai dépassé (timeout), « connection refused » | mauvaise IP, Mac en veille ou éteint, ou pas sur le même réseau | testez avec `curl` (section 1), puis demandez l'IP actuelle à Amaury |
| Réponses lentes | un autre utilisateur est en cours : le serveur traite **2 requêtes à la fois au maximum** ; un très long prompt (plus de 100 000 tokens) prend plusieurs minutes à lire | patientez ; évitez d'envoyer des dépôts entiers d'un coup |
| Le modèle « réfléchit » longtemps | niveau Max : jusqu'à 24 576 tokens de réflexion (environ 8 minutes) | normal pour une question difficile ; pour une question simple, passez en Medium (section 1, « Niveau de réflexion ») |
| Erreurs d'appel d'outils (tool calling), JSON brut affiché | client configuré en mode « Ollama » au lieu d'« OpenAI compatible » | choisissez le fournisseur **OpenAI compatible**, avec la base URL qui finit par `/v1` |
| « context length exceeded » / contexte dépassé | la conversation dépasse 262 144 tokens | compactez (`/compact`, `/compress` selon le client) ou démarrez une nouvelle session |
| Mauvais nom de modèle | le modèle de secours est chargé à la place du principal | `GET /v1/models` (section 1) indique le modèle disponible en ce moment |

## 6. Bonnes pratiques

- **Le serveur est partagé**, avec 2 personnes servies en même temps au maximum. Une troisième requête attend son tour.
- **Ne laissez pas tourner des agents en boucle pendant des heures**, par exemple des tâches planifiées ou des boucles sans fin : ils bloquent la place des autres.
- **Pas de données sensibles.** Le trafic n'est **pas chiffré** (HTTP simple) et passe en clair sur le réseau local, mot de passe compris.
- **Ne donnez pas le mot de passe** à des personnes qui n'utilisent pas le serveur. Il peut être changé à tout moment, et l'ancien cesse alors de fonctionner.
