# Qwen Code avec le serveur LLM du Mac M5 Max

Qwen Code est un agent de code en terminal publié par l'équipe Qwen. C'est un fork de Gemini CLI : même interface, mais il sait parler à n'importe quel serveur compatible OpenAI, donc à notre Mac. Ce guide vous mène de zéro à une session qui fonctionne.

> Testé le 20 octobre 2026 avec Qwen Code **0.25.3**, sur macOS, en suivant ce guide à la lettre : lecture d'un fichier, modification, commande shell. Les instructions Windows et Linux viennent de la documentation officielle et n'ont pas été testées. Commande de création du fichier et niveaux de réflexion testés le 21 octobre 2026 (bash et zsh) ; la version PowerShell n'a pas été testée.

## 1. Prérequis

- **Node.js 22 ou plus récent** : vérifiez avec `node --version`. Installation sur [nodejs.org](https://nodejs.org), avec `brew install node` (macOS) ou le gestionnaire de paquets de votre distribution.
- **Système** : Windows natif, WSL2, Linux ou macOS.
- **Être sur le même réseau que le Mac**, et connaître le mot de passe partagé.

## 2. Installation

```bash
npm install -g @qwen-code/qwen-code@latest
```
Sur macOS ou Linux, `brew install qwen-code` marche aussi.

Vérifiez l'installation (la commande s'appelle `qwen`) :
```bash
qwen --version
```

## 3. Configuration pour ce serveur

Qwen Code peut se configurer par variables d'environnement (`OPENAI_BASE_URL`, `OPENAI_API_KEY`, `OPENAI_MODEL`) ou par un fichier `settings.json`. **La méthode recommandée est le fichier**, qui permet de déclarer les deux modèles et de passer de l'un à l'autre avec `/model`. Les variables d'environnement sont l'alternative, en fin de section.

### 3.1 Le mot de passe

Il ne va jamais dans le fichier : `settings.json` donne seulement le **nom** de la variable qui le contient.

**Linux / macOS / WSL2** (remplacez `~/.bashrc` par `~/.zshrc` sous zsh) :
```bash
echo 'export MAC_LLM_PASSWORD="<MOT_DE_PASSE>"' >> ~/.bashrc
source ~/.bashrc
```
**Windows PowerShell** (rouvrez le terminal ensuite) :
```powershell
[Environment]::SetEnvironmentVariable("MAC_LLM_PASSWORD", "<MOT_DE_PASSE>", "User")
```

### 3.2 Le fichier `settings.json`

| Système | Fichier |
|---|---|
| Linux, macOS, WSL2 | `~/.qwen/settings.json` |
| Windows natif | `%USERPROFILE%\.qwen\settings.json` |
| Un seul projet | `.qwen/settings.json` à la racine du projet |

La commande ci-dessous crée le fichier en une fois. Elle sauvegarde d'abord l'ancien fichier, s'il existe, en `settings.json.bak`. Réglez les deux variables en tête :
- **`MAC_IP`** : `192.168.1.92` est l'IP du Mac à la maison ; changez-la si on vous en donne une autre ;
- **`NIVEAU`** : le niveau de réflexion, `medium`, `high` ou `max` (par défaut ; voir 3.3).

**Linux / macOS / WSL2** (bash ou zsh) :
```bash
MAC_IP=192.168.1.92
NIVEAU=max   # medium, high ou max
case $NIVEAU in
  medium) EFFORT=medium; BUDGET=2048 ;;
  high)   EFFORT=high;   BUDGET=8192 ;;
  *)      EFFORT=xhigh;  BUDGET=24576 ;;
esac
mkdir -p ~/.qwen
[ -f ~/.qwen/settings.json ] && cp ~/.qwen/settings.json ~/.qwen/settings.json.bak
cat > ~/.qwen/settings.json <<EOF
{
  "modelProviders": {
    "openai": [
      {
        "id": "qwen3.8-flash-next",
        "name": "Qwen3.8 Flash Next (Mac M5)",
        "baseUrl": "http://${MAC_IP}:8080/v1",
        "envKey": "MAC_LLM_PASSWORD",
        "generationConfig": {
          "timeout": 600000,
          "contextWindowSize": 262144,
          "samplingParams": { "temperature": 1.0, "top_p": 0.95, "max_tokens": 32768 },
          "extra_body": { "reasoning_effort": "${EFFORT}", "thinking_budget_tokens": ${BUDGET} }
        }
      },
      {
        "id": "qwen3.8-27b",
        "name": "Qwen3.8 27B (Mac M5)",
        "baseUrl": "http://${MAC_IP}:8080/v1",
        "envKey": "MAC_LLM_PASSWORD",
        "generationConfig": {
          "timeout": 600000,
          "contextWindowSize": 262144,
          "samplingParams": { "temperature": 1.0, "top_p": 0.95, "max_tokens": 32768 },
          "extra_body": { "reasoning_effort": "${EFFORT}", "thinking_budget_tokens": ${BUDGET} }
        }
      }
    ]
  },
  "security": { "auth": { "selectedType": "openai" } },
  "model": { "name": "qwen3.8-flash-next" },
  "privacy": { "usageStatisticsEnabled": false },
  "telemetry": { "enabled": false }
}
EOF
```

**Windows PowerShell** :
```powershell
$MacIp = "192.168.1.92"
$Niveau = "max"   # medium, high ou max
$Effort, $Budget = switch ($Niveau) { "medium" { "medium", 2048 } "high" { "high", 8192 } default { "xhigh", 24576 } }
$Dir = "$env:USERPROFILE\.qwen"
New-Item -ItemType Directory -Force $Dir | Out-Null
if (Test-Path "$Dir\settings.json") { Copy-Item "$Dir\settings.json" "$Dir\settings.json.bak" }
$Models = foreach ($m in @(@("qwen3.8-flash-next", "Qwen3.8 Flash Next (Mac M5)"), @("qwen3.8-27b", "Qwen3.8 27B (Mac M5)"))) {
  [ordered]@{
    id = $m[0]; name = $m[1]; baseUrl = "http://${MacIp}:8080/v1"; envKey = "MAC_LLM_PASSWORD"
    generationConfig = [ordered]@{
      timeout = 600000; contextWindowSize = 262144
      samplingParams = [ordered]@{ temperature = 1.0; top_p = 0.95; max_tokens = 32768 }
      extra_body = [ordered]@{ reasoning_effort = $Effort; thinking_budget_tokens = $Budget }
    }
  }
}
$Settings = [ordered]@{
  modelProviders = @{ openai = @($Models) }
  security = @{ auth = @{ selectedType = "openai" } }
  model = @{ name = "qwen3.8-flash-next" }
  privacy = @{ usageStatisticsEnabled = $false }
  telemetry = @{ enabled = $false }
}
# WriteAllText ecrit en UTF-8 sans BOM.
[IO.File]::WriteAllText("$Dir\settings.json", ($Settings | ConvertTo-Json -Depth 10))
```

- **`selectedType: openai`** : Qwen Code démarre directement sur ce serveur, sans écran de connexion.
- **`envKey`** : le nom de la variable qui contient le mot de passe.
- **`timeout` de 10 minutes** : la lecture d'un très long prompt peut prendre plusieurs minutes quand le serveur est occupé.
- **`extra_body`** : le niveau de réflexion, envoyé avec chaque requête (voir 3.3).
- **`privacy` et `telemetry`** : coupent l'envoi de statistiques d'usage à l'équipe Qwen.

### 3.3 Niveau de réflexion : Medium, High ou Max

Qwen3.8 réfléchit avant de répondre. Comme dans l'interface web du serveur, vous choisissez combien de temps :

| `NIVEAU` | Plafond de réflexion | Pour quoi |
|---|---|---|
| `medium` | 2 048 tokens | questions simples, réponses rapides |
| `high` | 8 192 tokens | usage courant |
| `max` (**par défaut**) | 24 576 tokens | problèmes difficiles, débogage |

- **Changer de niveau** : relancez la commande de la section 3.2 avec une autre valeur de `NIVEAU`, puis redémarrez `qwen`.
- **`/effort` ne marche pas avec ce serveur.** Qwen Code n'envoie rien au serveur pour un modèle personnalisé, et de toute façon `extra_body` passe avant.
- **Chaque niveau envoie deux réglages au serveur.** `reasoning_effort` dit au modèle à quel point réfléchir. `thinking_budget_tokens` fixe le plafond : une fois atteint, le serveur arrête la réflexion et le modèle écrit sa réponse.
- **Pourquoi pas de niveau « illimité »** : sans plafond, le modèle a déjà réfléchi plus de 40 000 tokens sur un problème sans jamais conclure.
- N'écrivez jamais `max` dans `reasoning_effort` : le modèle n'accepte que `low`, `medium`, `high` et `xhigh`, et refuse la requête avec une erreur 500.

### 3.4 Alternative : variables d'environnement

Pour un essai rapide sans fichier :
```bash
export OPENAI_BASE_URL=http://192.168.1.92:8080/v1
export OPENAI_API_KEY=$MAC_LLM_PASSWORD
export OPENAI_MODEL=qwen3.8-flash-next
qwen
```
Ces variables peuvent aussi être rangées dans `~/.qwen/.env`. Qwen Code lit le premier `.env` trouvé : `.qwen/.env` ou `.env` du projet, puis `~/.qwen/.env`, puis `~/.env`. Avec cette méthode, `/model` ne propose pas les deux modèles.

### 3.5 Ne jamais passer par un compte cloud

Avec le fichier ci-dessus, Qwen Code ne demande aucune connexion au démarrage. Si un écran vous propose de vous connecter (compte Qwen, Google, Alibaba Cloud…) :
- refusez ou fermez-le ;
- tapez `/auth` et choisissez **OpenAI** (compatible OpenAI) ;
- vérifiez que `"selectedType": "openai"` est bien dans `settings.json`.

N'entrez jamais d'identifiants cloud : tout doit passer par le Mac.

## 4. Premier lancement

```bash
cd ~/mon-projet
qwen
```

- **Le modèle** : Flash-Next est choisi par défaut. Pour changer, tapez **`/model`**, puis choisissez **Qwen3.8 Flash Next (Mac M5)** (principal) ou **Qwen3.8 27B (Mac M5)** (secours).
- **Un seul modèle est chargé à la fois sur le Mac** : si vous choisissez l'autre, vous aurez une erreur.

Premier prompt de test :
```
Liste les fichiers de ce projet et résume en 3 lignes à quoi il sert.
```

Test sans interface, en une ligne :
```bash
qwen "Réponds juste : prêt"
```

## 5. Usage au quotidien

| Action | Commande |
|---|---|
| Changer de modèle | `/model` |
| Reprendre une ancienne session | `/resume` |
| Compacter la conversation quand elle devient longue | `/compress` |
| Consommation de tokens de la session | `/stats` |
| Fichier d'instructions du projet | `/init` crée un **`QWEN.md`** à la racine : décrivez-y le projet, les commandes de build et de test, les conventions. Commitez-le. `/memory` permet de le consulter. |
| Mode de validation | `/approval-mode` |
| Revenir avant une modification | `/restore` |
| Effacer l'écran / quitter | `/clear`, `/quit` |

**Valider ou refuser les modifications.** En mode `default`, Qwen Code demande votre accord avant chaque modification de fichier ou commande. Répondez oui, non, ou « toujours » pour ce type d'action. Les autres modes, choisis avec `/approval-mode` ou au lancement avec `--approval-mode` :
- **`plan`** : analyse sans rien modifier ;
- **`auto-edit`** : applique les modifications de fichiers sans demander, mais demande toujours avant une commande ;
- **`yolo`** : accepte tout. À éviter, sauf dans un dossier de test.

## 6. Réglages recommandés pour ce serveur

- **Contexte : 262 144 tokens** (`contextWindowSize`). Le serveur garantit cette taille par utilisateur, même quand deux personnes l'utilisent en même temps.
- **Température** : `1.0` et `top_p 0.95`, les valeurs recommandées par l'équipe Qwen, déjà dans le fichier ci-dessus.
- **`max_tokens` : 32 768**, au-dessus du plafond de réflexion du niveau Max (24 576 tokens), pour laisser la place à la réponse.
- **Fonctions cloud désactivées** : statistiques d'usage et télémétrie (`privacy`, `telemetry`), aucun compte cloud.

## 7. Dépannage

| Problème | Solution |
|---|---|
| Écran de connexion au démarrage | `security.auth.selectedType` absent ou faux dans `settings.json` ; voir 3.5 |
| `401` / `Invalid API Key` | `MAC_LLM_PASSWORD` est vide dans ce terminal (`echo $MAC_LLM_PASSWORD`) ou mal orthographiée dans `envKey` |
| `model not found` | l'autre modèle est chargé sur le Mac ; changez avec `/model` |
| Erreur 500 `Unexpected reasoning effort` | `reasoning_effort` a une valeur refusée par le modèle (`max`…) ; relancez la commande de la section 3.2 |
| Requête interrompue après un long moment | augmentez `generationConfig.timeout` ; un autre utilisateur occupe peut-être le serveur |
| `settings.json` ignoré | erreur de syntaxe JSON ; vérifiez avec `python3 -m json.tool ~/.qwen/settings.json` |
| Avertissement « running headless with --yolo » | normal avec `--approval-mode yolo` ; évitez ce mode hors d'un dossier de test |
