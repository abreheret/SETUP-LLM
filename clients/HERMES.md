# Hermes Agent avec le serveur LLM du Mac M5 Max

## Ce qui distingue Hermes d'OpenCode

Hermes Agent est l'agent open source de Nous Research ([NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)). Comme OpenCode, il lit et modifie des fichiers et lance des commandes. Mais ce n'est pas qu'un agent de code :

- **Mémoire entre les sessions.** Il retient ce qu'il apprend sur vous et vos projets, et s'en sert les fois suivantes.
- **Skills.** Quand il réussit une tâche, il peut en tirer une « compétence » réutilisable, qu'il améliore avec le temps.
- **Passerelle vers les messageries** (Telegram, Discord, Slack, WhatsApp…). On peut lui écrire depuis son téléphone, et il travaille sur la machine où il tourne.
- **Exécution sur une autre machine.** Ses commandes peuvent tourner en local, dans Docker, ou sur une autre machine via SSH (voir section 5).

Ce guide vous mène de zéro à une session qui fonctionne avec le modèle du Mac, **sans qu'aucune donnée ne parte vers un service cloud**.

> Testé le 20 octobre 2026 avec Hermes Agent **0.22.2**, sur macOS, avec le script officiel et la configuration manuelle de la section 3.2 : lecture d'un fichier, modification, commande shell. Pendant le test, Hermes ne s'est connecté qu'au Mac (`192.168.1.92`). L'assistant `hermes model`, l'installation Windows, l'application Desktop et le backend SSH n'ont pas été testés. Amaury l'utilise surtout sous **WSL2**. Commande de création de `config.yaml` et niveaux de réflexion testés le 21 octobre 2026 (bash et zsh) ; `/reasoning` non testé.

## 1. Prérequis

- **Système** : Linux, **WSL2** (recommandé sous Windows), macOS, ou Windows natif.
- **`git` et `curl`**. Le script d'installation se charge lui-même de Python et du reste.
- **Être sur le même réseau que le Mac**, et connaître le mot de passe partagé.
- **Sous WSL2, utilisez l'IP du Mac** et non `MacBook-Pro-de-Amaury.local` : WSL2 ne résout pas toujours les noms `.local`.

## 2. Installation

**Linux, WSL2, macOS** (script officiel) :
```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```
Le script installe Hermes dans `~/.hermes/` et la commande `hermes` dans `~/.local/bin`, qu'il ajoute à votre `PATH`. À la fin, il propose un assistant de configuration : vous pouvez le passer, la section 3 s'en occupe.

**Windows natif (PowerShell)** :
```powershell
iex (irm https://hermes-agent.nousresearch.com/install.ps1)
```

**Application Desktop** : un installeur Windows et macOS, qui contient aussi la ligne de commande, est disponible sur [hermes-agent.nousresearch.com](https://hermes-agent.nousresearch.com).

Rechargez votre shell (`source ~/.bashrc`, ou ouvrez un nouveau terminal), puis vérifiez :
```bash
hermes --version
```

## 3. Configuration pour ce serveur

Les secrets vont dans `~/.hermes/.env`, et tout le reste dans `~/.hermes/config.yaml`.

### 3.1 Méthode rapide : l'assistant `hermes model`

```bash
hermes model
```
1. Choisissez **« Custom endpoint (self-hosted / VLLM / etc.) »**.
2. Remplissez :
   - **Base URL** : `http://192.168.1.92:8080/v1`
   - **API key** : le mot de passe partagé
   - **Modèle** : `qwen3.8-flash-next`
3. **Faites ensuite les étapes de confidentialité de la section 3.3.** L'assistant ne les fait pas.

### 3.2 Méthode manuelle : fichiers complets à copier-coller (méthode testée)

**`~/.hermes/.env`** : le mot de passe, lisible par vous seul.
```bash
echo 'MAC_LLM_PASSWORD=<MOT_DE_PASSE>' >> ~/.hermes/.env
chmod 600 ~/.hermes/.env
```

**`~/.hermes/config.yaml`** : la commande ci-dessous remplace tout son contenu, après l'avoir sauvegardé en `config.yaml.bak`. Réglez les deux variables en tête :
- **`MAC_IP`** : `192.168.1.92` est l'IP du Mac à la maison ; changez-la si on vous en donne une autre ;
- **`NIVEAU`** : le niveau de réflexion, `medium`, `high` ou `max` (par défaut ; voir 3.4).

```bash
MAC_IP=192.168.1.92
NIVEAU=max   # medium, high ou max
case $NIVEAU in
  medium) EFFORT=medium; BUDGET=2048 ;;
  high)   EFFORT=high;   BUDGET=8192 ;;
  *)      EFFORT=xhigh;  BUDGET=24576 ;;
esac
mkdir -p ~/.hermes
[ -f ~/.hermes/config.yaml ] && cp ~/.hermes/config.yaml ~/.hermes/config.yaml.bak
cat > ~/.hermes/config.yaml <<EOF
# ~/.hermes/config.yaml - Hermes Agent relie au serveur LLM du Mac M5 Max
model:
  provider: custom
  base_url: http://${MAC_IP}:8080/v1
  default: qwen3.8-flash-next
  key_env: MAC_LLM_PASSWORD
  context_length: 262144

# Niveau de reflexion ($NIVEAU) : effort demande au modele...
agent:
  reasoning_effort: ${EFFORT}

# ... et plafond de reflexion, envoye avec chaque requete vers le Mac.
custom_providers:
  - name: mac-m5
    base_url: http://${MAC_IP}:8080/v1
    extra_body:
      thinking_budget_tokens: ${BUDGET}

# Taches annexes : tout passe par le Mac, jamais par OpenRouter ou Nous Portal.
auxiliary:
  vision: { provider: main }
  web_extract: { provider: main }
  compression: { provider: main }
  session_search: { provider: main }
  title_generation: { provider: main }
  tts_audio_tags: { provider: main }
  background_review: { provider: main }

# Outils du terminal : ceux qui dependent de services cloud sont retires
# (web, browser, vision, image_gen, tts, computer_use).
platform_toolsets:
  cli: [clarify, code_execution, connections, cronjob, delegation, file, memory, session_search, skills, terminal, todo]

terminal:
  backend: local

telemetry:
  shared_metrics:
    enabled: false
    send: false
EOF
```

Puis complétez les options par défaut. Cette commande garde vos réglages ; répondez `N` à « Configure new keys? » :
```bash
hermes config migrate
hermes config check
```
`config check` doit afficher `Config version: … ✓`. La longue liste de variables marquées `○` (Telegram, e-mail, WhatsApp…) correspond à des options non utilisées : c'est normal.

### 3.3 Confidentialité : tout garder sur le Mac

La documentation de Hermes prévient que certaines **tâches annexes** passent par défaut par **OpenRouter**, puis par Nous Portal, et seulement en dernier recours par votre serveur :
- l'analyse d'images ;
- le résumé de pages web ;
- la compression du contexte ;
- la génération des titres de session.

Certains **outils** appellent aussi des services cloud : recherche web, navigateur, génération d'images, synthèse vocale.

Le `config.yaml` de la section 3.2 règle ces deux points :
- **`auxiliary.*.provider: main`** envoie chaque tâche annexe vers le Mac.
- **`platform_toolsets.cli`** ne garde que les outils locaux : fichiers, terminal, mémoire, skills…
- **`telemetry.shared_metrics.enabled: false`** coupe l'envoi de statistiques à Nous Research (c'est déjà la valeur par défaut).

Si vous êtes passé par l'assistant `hermes model` (méthode 3.1), faites-le en ligne de commande :
```bash
for t in vision web_extract compression session_search title_generation tts_audio_tags background_review; do
  hermes config set auxiliary.$t.provider main
done
hermes tools disable web browser vision image_gen tts computer_use
```

**Vérifier** :
```bash
hermes config get model          # provider: custom, base_url: http://192.168.1.92:8080/v1
hermes config get auxiliary      # provider: main partout
hermes tools list                # web, browser, vision, image_gen, tts : disabled
```

Pour contrôler pendant une session qu'aucune connexion ne part ailleurs que vers le Mac (Linux et WSL2 ; sous macOS, `lsof -nP -iTCP | grep -i python`) :
```bash
ss -tnp | grep -E 'python|hermes'
```

**Ce qu'il ne faut pas utiliser** :
- **`/moa`** (Mixture of Agents) : il fait appel à plusieurs modèles prédéfinis, en général via OpenRouter.
- **`hermes setup --portal`**, et toute connexion à Nous Portal ou à OpenRouter.

### 3.4 Niveau de réflexion : Medium, High ou Max

Qwen3.8 réfléchit avant de répondre. Comme dans l'interface web du serveur, vous choisissez combien de temps :

| `NIVEAU` | Plafond de réflexion | Pour quoi |
|---|---|---|
| `medium` | 2 048 tokens | questions simples, réponses rapides |
| `high` | 8 192 tokens | usage courant |
| `max` (**par défaut**) | 24 576 tokens | problèmes difficiles, débogage |

- **Changer de niveau** : relancez la commande de la section 3.2 avec une autre valeur de `NIVEAU`, puis `hermes config migrate`.
- **Deux réglages par niveau.** `agent.reasoning_effort` dit au modèle à quel point réfléchir. `extra_body.thinking_budget_tokens` fixe le plafond : une fois atteint, le serveur arrête la réflexion et le modèle écrit sa réponse.
- **`/reasoning medium` ou `/reasoning high`** change l'effort pendant une session, mais pas le plafond. N'utilisez jamais `/reasoning max` ni `ultra` : le modèle n'accepte que `low`, `medium`, `high` et `xhigh`, et refuse la requête avec une erreur 500.
- **Pourquoi pas de niveau « illimité »** : sans plafond, le modèle a déjà réfléchi plus de 40 000 tokens sur un problème sans jamais conclure.

## 4. Premier lancement

```bash
cd ~/mon-projet
hermes
```

- **Le modèle** : Flash-Next est le modèle par défaut. Pour le modèle de secours : `/model qwen3.8-27b` pour la session en cours, ou `/model qwen3.8-27b --global` pour l'enregistrer.
- **Un seul modèle est chargé à la fois sur le Mac.**

Premier prompt de test, qui utilise les outils :
```
Crée un fichier test.txt contenant "bonjour", relis-le, puis lance la commande ls -l et dis-moi sa taille.
```
Hermes demande votre accord avant les commandes jugées dangereuses : répondez, ou utilisez `/approve` et `/deny`.

Test sans interface, en une ligne :
```bash
hermes chat --oneshot -q "Réponds juste : prêt"
```

## 5. Usage au quotidien

**Commandes du terminal :**

| Commande | Rôle |
|---|---|
| `hermes` | démarre une session |
| `hermes --continue` (`-c`) | reprend la dernière session |
| `hermes --resume <session>` (`-r`) | reprend une session précise |
| `hermes sessions` | parcourt, renomme, exporte, supprime les sessions |
| `hermes model` | assistant de choix du fournisseur et du modèle (à lancer hors session) |
| `hermes config show` / `edit` / `get` / `set` / `check` | lit et modifie la configuration |
| `hermes tools list` / `enable` / `disable` | active ou désactive des outils |
| `hermes memory` | configure le fournisseur de mémoire |
| `hermes doctor` | diagnostic (`--fix` pour réparer) |
| `hermes update` | met à jour Hermes (`--check` pour voir sans installer) |

**Commandes dans une session :**

| Commande | Rôle |
|---|---|
| `/model <nom>` | change de modèle |
| `/new` | nouvelle session |
| `/sessions`, `/resume` | reprend une session |
| `/compress` | compacte le contexte |
| `/context`, `/status` | occupation du contexte, modèle, tokens |
| `/memory` | relit les écritures en mémoire en attente |
| `/skills` | gère les skills |
| `/tools` | liste, active ou désactive des outils |
| `/undo`, `/rollback` | revient en arrière (conversation, fichiers) |
| `/approve`, `/deny`, `/yolo` | valide ou refuse une commande à risque ; `/yolo` supprime les confirmations, à éviter |
| `/plan` | écrit un plan dans `.hermes/plans/` sans rien exécuter |

**Fichier d'instructions du projet** : un `AGENTS.md` à la racine du projet, décrivant le projet, les commandes de build et de test et les conventions, est lu comme par les autres agents.

### Backend de terminal : local, Docker ou SSH

Hermes peut exécuter ses commandes ailleurs que là où il tourne. Le réglage est `terminal.backend` dans `config.yaml` :
- **`local`** (par défaut) : les commandes tournent sur la même machine que Hermes.
- **`docker`** : dans un conteneur, pour isoler.
- **`ssh`** : sur une autre machine, via SSH.

**Exemple (non testé) : Hermes tourne sous WSL2, mais exécute ses commandes sur un serveur Linux `build01`.**

1. Vérifiez d'abord que la connexion SSH par clé fonctionne depuis WSL2 :
   ```bash
   ssh -i ~/.ssh/id_ed25519 amaury@build01.local 'uname -a'
   ```
2. Ajoutez dans `~/.hermes/.env` :
   ```bash
   TERMINAL_SSH_HOST=build01.local
   TERMINAL_SSH_USER=amaury
   TERMINAL_SSH_KEY=/home/amaury/.ssh/id_ed25519
   # TERMINAL_SSH_PORT=22
   ```
3. Changez le backend :
   ```bash
   hermes config set terminal.backend ssh
   ```

Le modèle reste celui du Mac. Seules les commandes partent sur `build01`.

## 6. Réglages recommandés pour ce serveur

- **Contexte : `context_length: 262144`.** Le serveur garantit cette taille par utilisateur, même quand deux personnes l'utilisent en même temps. Hermes demande au moins 64 000 tokens.
- **Taille du premier prompt.** Hermes envoie un prompt système et des définitions d'outils volumineux. Avec la configuration ci-dessus, le premier message fait **11 328 tokens**, mesurés dans les journaux du serveur. Le serveur met environ 16 s à le lire, puis le garde en cache. Il reste donc **environ 250 000 tokens** pour votre conversation. Si vous réactivez des outils, ce premier prompt grossit.
- **Température** : laissez la valeur par défaut. Le serveur applique les réglages recommandés pour Qwen3.8.
- **Réflexion** : Max par défaut ; `medium` pour les petites tâches (section 3.4).
- **Fonctions cloud** : désactivées par la section 3.3.

## 7. Dépannage

| Problème | Solution |
|---|---|
| `401` / clé refusée | `MAC_LLM_PASSWORD` absente ou fausse dans `~/.hermes/.env` ; vérifiez `hermes config get model.key_env` |
| Les appels d'outils s'affichent en JSON brut | le serveur doit tourner avec `--jinja` (c'est le cas) ; vérifiez que `model.provider` vaut `custom` et que `base_url` finit par `/v1` |
| Erreurs sur l'analyse d'images ou le web | normal : ces outils sont désactivés pour rester en local |
| Timeout sous WSL2 | utilisez l'IP du Mac, pas le nom `.local` ; testez `curl -H "Authorization: Bearer $MAC_LLM_PASSWORD" http://192.168.1.92:8080/v1/models` depuis WSL2 |
| Configuration incohérente après une mise à jour | `hermes config check`, puis `hermes config migrate` ; en dernier recours `hermes doctor --fix` |
| Journaux | `~/.hermes/logs/` (les secrets y sont masqués) |
