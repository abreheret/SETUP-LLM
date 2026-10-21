# OpenCode avec le serveur LLM du Mac M5 Max

OpenCode est un agent de code open source qui s'utilise dans le terminal. Il lit votre projet, propose et applique des modifications, et lance des commandes. Ce guide vous mène de zéro à une session qui fonctionne avec le modèle du Mac.

> Testé le 20 octobre 2026 avec OpenCode **1.19.3**, sur macOS, en suivant ce guide à la lettre : lecture d'un fichier, modification, commande shell. Les instructions Windows et Linux viennent de la documentation officielle et n'ont pas été testées. Commande de création du fichier et niveaux de réflexion testés le 21 octobre 2026 (bash et zsh, `Ctrl+T` non testé) ; la version PowerShell n'a pas été testée.

## 1. Prérequis

- **Système** : Linux, macOS, ou Windows. Sous Windows, OpenCode recommande **WSL2**, mais une installation native est possible.
- **Un terminal récent** : Windows Terminal, iTerm2, WezTerm, Ghostty, Kitty… Le Terminal de base de macOS marche aussi.
- **Node.js** seulement si vous installez par `npm`. Le script d'installation officiel n'en a pas besoin.
- **Être sur le même réseau que le Mac**, et connaître le mot de passe partagé.

## 2. Installation

**Linux, macOS, WSL2** (script officiel) :
```bash
curl -fsSL https://opencode.ai/install | bash
```
ou, avec Node.js :
```bash
npm install -g opencode-ai
```

**Windows natif** : `scoop install opencode`, `choco install opencode` ou `npm install -g opencode-ai`.

Vérifiez l'installation :
```bash
opencode --version
```

## 3. Configuration pour ce serveur

### 3.1 Le mot de passe et le réglage réseau

Le mot de passe ne va jamais dans le fichier de configuration : il est lu dans la variable `MAC_LLM_PASSWORD`.

Ajoutez aussi `OPENCODE_DISABLE_MODELS_FETCH=1`. Sans elle, OpenCode télécharge au démarrage le catalogue des modèles cloud (`models.dev`), qui ne sert à rien ici. Pendant nos tests, ce téléchargement l'a bloqué 2 fois sur 4.

**Linux / macOS / WSL2** (remplacez `~/.bashrc` par `~/.zshrc` sous zsh) :
```bash
echo 'export MAC_LLM_PASSWORD="<MOT_DE_PASSE>"' >> ~/.bashrc
echo 'export OPENCODE_DISABLE_MODELS_FETCH=1' >> ~/.bashrc
source ~/.bashrc
```

**Windows PowerShell** (rouvrez le terminal ensuite) :
```powershell
[Environment]::SetEnvironmentVariable("MAC_LLM_PASSWORD", "<MOT_DE_PASSE>", "User")
[Environment]::SetEnvironmentVariable("OPENCODE_DISABLE_MODELS_FETCH", "1", "User")
```

### 3.2 Le fichier de configuration

Emplacement :

| Système | Fichier |
|---|---|
| Linux, macOS, WSL2 | `~/.config/opencode/opencode.json` |
| Windows natif | `%USERPROFILE%\.config\opencode\opencode.json` (emplacement non vérifié sous Windows) |
| Un seul projet | `opencode.json` à la racine du projet ; il complète le fichier global |

La commande ci-dessous crée le fichier en une fois. Elle sauvegarde d'abord l'ancien fichier, s'il existe, en `opencode.json.bak`. L'IP `192.168.1.92` est celle du Mac à la maison : changez `MAC_IP` si on vous en donne une autre.

**Linux / macOS / WSL2** (bash ou zsh) :
```bash
MAC_IP=192.168.1.92
mkdir -p ~/.config/opencode
[ -f ~/.config/opencode/opencode.json ] && cp ~/.config/opencode/opencode.json ~/.config/opencode/opencode.json.bak
cat > ~/.config/opencode/opencode.json <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "mac-m5": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Mac M5 Max",
      "options": {
        "baseURL": "http://${MAC_IP}:8080/v1",
        "apiKey": "{env:MAC_LLM_PASSWORD}"
      },
      "models": {
        "qwen3.8-flash-next": {
          "name": "Qwen3.8 Flash Next",
          "limit": { "context": 262144, "output": 32768 },
          "options": { "reasoningEffort": "xhigh", "thinking_budget_tokens": 24576 },
          "variants": {
            "medium": { "reasoningEffort": "medium", "thinking_budget_tokens": 2048 },
            "high": { "reasoningEffort": "high", "thinking_budget_tokens": 8192 },
            "max": { "reasoningEffort": "xhigh", "thinking_budget_tokens": 24576 }
          }
        },
        "qwen3.8-27b": {
          "name": "Qwen3.8 27B",
          "limit": { "context": 262144, "output": 32768 },
          "options": { "reasoningEffort": "xhigh", "thinking_budget_tokens": 24576 },
          "variants": {
            "medium": { "reasoningEffort": "medium", "thinking_budget_tokens": 2048 },
            "high": { "reasoningEffort": "high", "thinking_budget_tokens": 8192 },
            "max": { "reasoningEffort": "xhigh", "thinking_budget_tokens": 24576 }
          }
        }
      }
    }
  },
  "model": "mac-m5/qwen3.8-flash-next",
  "small_model": "mac-m5/qwen3.8-flash-next",
  "share": "disabled"
}
EOF
```

**Windows PowerShell** :
```powershell
$MacIp = "192.168.1.92"
$Dir = "$env:USERPROFILE\.config\opencode"
New-Item -ItemType Directory -Force $Dir | Out-Null
if (Test-Path "$Dir\opencode.json") { Copy-Item "$Dir\opencode.json" "$Dir\opencode.json.bak" }
$Variants = '"options": { "reasoningEffort": "xhigh", "thinking_budget_tokens": 24576 },
          "variants": {
            "medium": { "reasoningEffort": "medium", "thinking_budget_tokens": 2048 },
            "high": { "reasoningEffort": "high", "thinking_budget_tokens": 8192 },
            "max": { "reasoningEffort": "xhigh", "thinking_budget_tokens": 24576 }
          }'
$Json = @"
{
  "`$schema": "https://opencode.ai/config.json",
  "provider": {
    "mac-m5": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Mac M5 Max",
      "options": { "baseURL": "http://${MacIp}:8080/v1", "apiKey": "{env:MAC_LLM_PASSWORD}" },
      "models": {
        "qwen3.8-flash-next": {
          "name": "Qwen3.8 Flash Next",
          "limit": { "context": 262144, "output": 32768 },
          $Variants
        },
        "qwen3.8-27b": {
          "name": "Qwen3.8 27B",
          "limit": { "context": 262144, "output": 32768 },
          $Variants
        }
      }
    }
  },
  "model": "mac-m5/qwen3.8-flash-next",
  "small_model": "mac-m5/qwen3.8-flash-next",
  "share": "disabled"
}
"@
# WriteAllText ecrit en UTF-8 sans BOM, que le lecteur JSON d'OpenCode accepte.
[IO.File]::WriteAllText("$Dir\opencode.json", $Json)
```

- **`small_model`** : OpenCode utilise un « petit modèle » pour les titres de session. Sans ce réglage, il chercherait un modèle cloud.
- **`share: disabled`** : désactive le partage de sessions par lien public, qui enverrait la conversation sur les serveurs d'OpenCode.
- **`options` et `variants`** : le niveau de réflexion, **Max par défaut**. Voir 3.3.

### 3.3 Niveau de réflexion : Medium, High ou Max

Qwen3.8 réfléchit avant de répondre. Comme dans l'interface web du serveur, vous choisissez combien de temps :

| Niveau | Plafond de réflexion | Pour quoi |
|---|---|---|
| `medium` | 2 048 tokens | questions simples, réponses rapides |
| `high` | 8 192 tokens | usage courant |
| `max` (**par défaut**) | 24 576 tokens | problèmes difficiles, débogage |

- **Dans OpenCode** : **`Ctrl+T`** passe au niveau suivant.
- **En ligne de commande** : `opencode run --variant medium "..."`.
- **Chaque niveau envoie deux réglages au serveur.** `reasoningEffort` dit au modèle à quel point réfléchir. `thinking_budget_tokens` fixe le plafond : une fois atteint, le serveur arrête la réflexion et le modèle écrit sa réponse.
- **Pourquoi pas de niveau « illimité »** : sans plafond, le modèle a déjà réfléchi plus de 40 000 tokens sur un problème sans jamais conclure. Max reste aussi sous la limite de sortie d'OpenCode (32 000 tokens), pour laisser la place à la réponse.
- N'écrivez jamais `max` dans `reasoningEffort` : le modèle n'accepte que `low`, `medium`, `high` et `xhigh`, et refuse la requête avec une erreur 500.

Vérifiez qu'OpenCode voit les modèles :
```bash
opencode models mac-m5
```
Vous devez obtenir `mac-m5/qwen3.8-27b` et `mac-m5/qwen3.8-flash-next`.

## 4. Premier lancement

```bash
cd ~/mon-projet
opencode
```

- **Le modèle** : Flash-Next est choisi par défaut. Pour changer, tapez **`/models`**, puis choisissez **Qwen3.8 Flash Next** (principal) ou **Qwen3.8 27B** (secours).
- **Un seul modèle est chargé à la fois sur le Mac.** Si vous choisissez celui qui n'est pas chargé, vous aurez une erreur. `curl` (voir `CLIENTS.md`) indique lequel est actif.

Premier prompt de test :
```
Liste les fichiers de ce projet et résume en 3 lignes à quoi il sert.
```

Test sans interface, en une ligne :
```bash
opencode run "Réponds juste : prêt"
```

## 5. Usage au quotidien

| Action | Comment |
|---|---|
| Changer de modèle | `/models` |
| Changer le niveau de réflexion (Medium, High, Max) | **Ctrl+T** |
| Mode Plan (propose sans modifier) / Build (modifie) | touche **Tab** |
| Mentionner un fichier | `@` puis le nom |
| Annuler / refaire la dernière modification | `/undo`, `/redo` |
| Reprendre une ancienne session | `/sessions` ; en ligne de commande : `opencode run -c "..."` (dernière session) |
| Nouvelle session | `/new` |
| Fichier d'instructions du projet | `/init` crée un `AGENTS.md` à la racine : décrivez-y le projet, les commandes de build et de test, les conventions. Commitez-le. |
| Aide | `/help` |

**Valider ou refuser les modifications.** Par défaut, OpenCode applique les modifications et lance les commandes sans demander. Pour qu'il demande votre accord à chaque fois, ajoutez dans `opencode.json` :
```json
"permission": { "edit": "ask", "bash": "ask" }
```

## 6. Réglages recommandés pour ce serveur

- **Contexte : 262 144 tokens** par utilisateur (`limit.context` ci-dessus). Le serveur garantit cette taille même quand deux personnes l'utilisent en même temps.
- **Premier message d'une session** : OpenCode envoie environ **7 700 tokens** d'instructions et de définitions d'outils. Le serveur les lit en 10 à 15 s, puis les garde en cache pour les messages suivants.
- **Température** : laissez la valeur par défaut. Le serveur applique les réglages recommandés pour Qwen3.8.
- **Réflexion** : Max par défaut. Passez en `medium` avec **Ctrl+T** pour les petites tâches : les réponses arrivent plus vite et le serveur est libéré plus tôt pour les autres (section 3.3).
- **Fonctions cloud à désactiver** : `share: disabled` et `OPENCODE_DISABLE_MODELS_FETCH=1`, déjà faits ci-dessus. N'utilisez pas `/connect`, qui sert aux fournisseurs cloud.

## 7. Dépannage

| Problème | Solution |
|---|---|
| OpenCode reste bloqué au démarrage, sans rien afficher | vérifiez que `OPENCODE_DISABLE_MODELS_FETCH=1` est bien défini (`echo $OPENCODE_DISABLE_MODELS_FETCH`) |
| `Unauthorized` / `Invalid API Key` | `MAC_LLM_PASSWORD` est vide ou fausse dans ce terminal (`echo $MAC_LLM_PASSWORD`) |
| `mac-m5` n'apparaît pas dans `/models` | erreur de syntaxe JSON dans `opencode.json` (virgule en trop…) ; lancez `opencode models mac-m5` pour voir l'erreur |
| Erreur 500 `Unexpected reasoning effort` | `reasoningEffort` a une valeur refusée par le modèle (`max`, `minimal`…) ; utilisez `medium`, `high` ou `xhigh` (section 3.3) |
| `model not found` | l'autre modèle est chargé sur le Mac ; choisissez-le avec `/models` |
| Timeout | mauvaise IP, Mac en veille ou pas sur le même réseau ; testez avec `curl` (`CLIENTS.md`, section 1) |
| Journaux | `~/.local/share/opencode/log/`, ou `opencode run --print-logs "..."` |
