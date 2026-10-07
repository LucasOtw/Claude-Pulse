# Claude Pulse

Suis Claude Code depuis ton iPhone pendant qu'il travaille sur ton Mac :

- **Live Activity + Dynamic Island** : projet, ce que fait Claude (« Modifie des fichiers », « Exécute des commandes »…), étape en cours de sa liste de tâches, sous-agents actifs, workflow en arrière-plan, chrono, coût. Alerte quand Claude **attend ta validation** et quand il a **terminé**.
- **Widget** (écran d'accueil et écran verrouillé) : limites d'abonnement **5 h / 7 jours**, coût estimé du jour, sessions en cours.

```
Mac : Claude Code ──hooks + status line──▶ Vercel (gratuit) ──push Apple──▶ iPhone
      mac/hook.sh                          backend/                          ios/
      mac/statusline.sh                    + Upstash Redis (gratuit)         app + widget + Live Activity
```

## Ce qui est envoyé (et ce qui ne l'est pas)

Les scripts du Mac ne transmettent que des **métadonnées** : nom du dossier du projet, type d'événement, nom de l'outil, intitulés des tâches, nom des workflows, coût, % de contexte, % des limites. **Jamais** le texte de tes prompts, les réponses de Claude, les commandes ni le contenu des fichiers. Voir le filtre `jq` dans [`mac/hook.sh`](mac/hook.sh).

---

## Installation (≈ 30 min)

### 1. Clé de push Apple

1. [developer.apple.com](https://developer.apple.com/account) → *Certificates, IDs & Profiles* → **Keys** → **+**.
2. Coche **Apple Push Notifications service (APNs)**, enregistre, puis **télécharge le `.p8`** (une seule fois possible !) et note le **Key ID**.
3. Ton **Team ID** est dans *Membership details*.

### 2. Backend sur Vercel (plan Hobby gratuit)

1. Sur Vercel : **Add New → Project** → importe ce dépôt → **Root Directory : `backend`** → Deploy.
2. Onglet **Storage** du projet → **Upstash for Redis** (Marketplace, plan *Free*) → connecte-le au projet. Les variables `KV_REST_API_URL` et `KV_REST_API_TOKEN` sont ajoutées automatiquement.
3. **Settings → Environment Variables** :

   | Variable | Valeur |
   | --- | --- |
   | `PULSE_TOKEN` | un secret au hasard : `openssl rand -hex 32` |
   | `APNS_TEAM_ID` | ton Team ID |
   | `APNS_KEY_ID` | le Key ID de la clé `.p8` |
   | `APNS_KEY` | tout le contenu du `.p8` (avec les lignes `-----BEGIN PRIVATE KEY-----`) |
   | `APNS_BUNDLE_ID` | `com.lucasotw.claudepulse` |
   | `APNS_ENV` | `development` tant que l'app est installée depuis Xcode, `production` pour TestFlight |

4. **Redeploy**, puis vérifie :
   ```bash
   curl -H "Authorization: Bearer TON_PULSE_TOKEN" https://TON-PROJET.vercel.app/api/state
   ```

### 3. App iPhone

```bash
brew install xcodegen
cd ios
xcodegen            # génère ClaudePulse.xcodeproj
open ClaudePulse.xcodeproj
```

1. Dans Xcode, cibles **ClaudePulse** et **ClaudePulseWidgets** → *Signing & Capabilities* → choisis ton équipe (ou renseigne `DEVELOPMENT_TEAM` dans `project.yml`).
2. Branche l'iPhone, choisis-le comme destination, **Run** (⌘R).
3. Dans l'app : ⚙️ → URL du backend + `PULSE_TOKEN` → **Tester : démarrer** → verrouille l'iPhone : la Live Activity de démo doit apparaître. Puis **Tester : attente de validation**, puis **Tester : terminer**.
4. Ajoute le widget : appui long sur l'écran d'accueil → **+** → *Claude Pulse*.

> Si le bundle ID `com.lucasotw.claudepulse` est refusé, change-le dans `project.yml`, dans `APNS_BUNDLE_ID`, et l'App Group `group.com.lucasotw.claudepulse` dans `project.yml` + `ios/Shared/PulseConfig.swift`.

### 4. Mac (Claude Code)

```bash
jq --version || brew install jq     # jq est inclus dans macOS 15+
cd mac
./install.sh https://TON-PROJET.vercel.app TON_PULSE_TOKEN
```

Le script :
- copie `hook.sh` et `statusline.sh` dans `~/.claude/claude-pulse/` (config en `chmod 600`) ;
- ajoute les hooks dans `~/.claude/settings.json` (après en avoir fait une sauvegarde), pour **tous tes projets** ;
- installe la status line : `[Opus] · ctx 42% · 5h 23% · 7j 41% · $1.23`. Si tu en avais déjà une, elle continue de s'afficher.

Relance tes sessions Claude Code. Pour tout retirer : `./uninstall.sh`.

---

## Comment ça marche

| Événement Claude Code | Effet sur l'iPhone |
| --- | --- |
| `UserPromptSubmit` | début d'une tâche (chrono) |
| `PreToolUse` (au plus 1 fois / 30 s, sauf TodoWrite / Agent / Workflow) | « ce que fait Claude », progression TodoWrite, nom et phases du workflow |
| `TaskCreated` / `TaskCompleted` | progression de la liste de tâches |
| `SubagentStart` / `SubagentStop` | nombre de sous-agents actifs |
| `Notification` (`permission_prompt`…) | **alerte « attend ta validation »** |
| `Stop` | **fin + alerte**, sauf si un workflow / des tâches tournent encore en arrière-plan |
| `StopFailure` | fin en erreur (rate limit, surcharge…) |
| status line (1 relevé / min) | coût, % contexte, limites 5 h / 7 jours |

- Une Live Activity ne démarre que si la tâche dure **plus de 30 s** (ou tout de suite si Claude attend ta validation) : pas de spam pour les questions rapides.
- Les mises à jour sans changement de statut sont limitées à **une toutes les 5 s**.
- Si tu fermes une Live Activity à la main, elle ne revient pas avant ton prochain message.

Réglages (dans `~/.claude/claude-pulse/config`) : `PULSE_HEARTBEAT=30`, `PULSE_USAGE_EVERY=60`.
Seuils côté serveur : `DEFAULTS` dans [`backend/lib/state.js`](backend/lib/state.js).

## Limites connues

- **Phase exacte d'un workflow** : Claude Code n'émet pas d'événement par phase. On affiche le nom du workflow, ses phases déclarées, les sous-agents actifs et le fait qu'il tourne en arrière-plan.
- **Limites 5 h / 7 jours** : fournies par Claude Code uniquement avec un abonnement Pro / Max, après le premier message d'une session.
- **Coût** : estimation de Claude Code au prix public de l'API, pas ta facture réelle.
- iOS limite la durée d'une Live Activity (≈ 8 h) et la fréquence de rafraîchissement des widgets (toutes les 5 à 15 min environ).
- Quotas gratuits : un hook ≈ 1 appel de fonction Vercel + ≈ 7 commandes Redis. Avec les réglages par défaut, une journée de travail intensif reste dans les plans gratuits.

## Développement

```bash
cd backend && npm test   # machine à états + test de bout en bout (faux Redis + faux APNs)
```

```
backend/
  api/hook.js     événements des hooks → machine à états → push
  api/usage.js    relevés de la status line
  api/device.js   jetons push de l'iPhone
  api/state.js    lu par l'app et le widget
  api/test.js     démo depuis l'app
  lib/state.js    machine à états (pure, testée)
  lib/live.js     action → payload Live Activity
  lib/apns.js     HTTP/2 + JWT ES256, sans dépendance
  lib/redis.js    Upstash REST, sans dépendance
ios/
  Shared/         modèles, API, réglages (App Group), styles
  ClaudePulse/    app : sessions, limites, réglages, jetons push
  ClaudePulseWidgets/  widget + Live Activity / Dynamic Island
mac/
  hook.sh  statusline.sh  install.sh  uninstall.sh
```
