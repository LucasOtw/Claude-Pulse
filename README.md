# Claude Pulse

Suis Claude Code depuis ton iPhone pendant qu'il travaille sur ton Mac :

- **Live Activity + Dynamic Island** : projet, ce que fait Claude (« Modifie des fichiers », « Exécute des commandes »…), étape en cours de sa liste de tâches, sous-agents actifs, workflow en arrière-plan, chrono, coût, limite 5 h.
- **Notifications** quand Claude **attend ta validation** et quand il a **terminé**.
- **Widget** (écran d'accueil et écran verrouillé) : limites d'abonnement **5 h / 7 jours**, coût estimé du jour, sessions en cours.

Fonctionne avec un **Apple ID gratuit** : pas besoin du compte développeur payant.

```
Mac : Claude Code ──hooks + status line──▶ Vercel + Upstash ◀──interroge toutes les 5 s── iPhone
      mac/hook.sh                          backend/ (gratuits)                             ios/
      mac/statusline.sh
```

## Ce qui est envoyé (et ce qui ne l'est pas)

Les scripts du Mac ne transmettent que des **métadonnées** : nom du dossier du projet, type d'événement, nom de l'outil, **nom du fichier** lu ou modifié (sans son chemin), **description courte** que Claude donne à sa commande ou à son sous-agent (« Run backend tests »), domaine d'une page web, intitulés des tâches, nom des workflows, % de contexte, % des limites. **Jamais** le texte de tes prompts, les réponses de Claude, les commandes elles-mêmes ni le contenu des fichiers. Voir le filtre `jq` dans [`mac/hook.sh`](mac/hook.sh).

## Comment ça marche sans compte développeur

Sans compte payant, pas de push Apple : le serveur ne peut pas réveiller l'iPhone. Alors c'est l'app qui fait le travail :

1. Tu ouvres Claude Pulse et tu touches **Lancer la surveillance** : une Live Activity apparaît (iOS n'autorise à la créer que depuis l'app ouverte).
2. L'app joue un **son silencieux** en boucle pour qu'iOS la laisse tourner en arrière-plan. Il se mélange à ta musique sans la couper.
3. Elle interroge le backend toutes les **5 s** quand une tâche tourne (20 s sinon), met à jour la Live Activity et t'envoie les notifications.
4. La Live Activity suit automatiquement la session importante : celle qui attend ta validation, sinon la plus récente en cours.

Les limites à connaître :

- **L'app expire au bout de 7 jours** (règle d'Apple pour les Apple ID gratuits) : rebranche l'iPhone et relance-la depuis Xcode (⌘R) une fois par semaine.
- iOS ferme une Live Activity au bout de **8 h** : relance la surveillance le matin.
- Si iOS tue l'app (rare, ou si tu la fermes depuis le sélecteur d'apps), la Live Activity se fige et affiche « Plus de nouvelles ». Rouvre l'app.
- La surveillance consomme un peu de batterie. Balaie la Live Activity ou touche **Arrêter** quand tu n'en as plus besoin.

---

## Installation (≈ 20 min)

### 1. Backend sur Vercel (plan Hobby gratuit)

1. Sur Vercel : **Add New → Project** → importe ce dépôt → **Root Directory : `backend`** → Deploy.
2. Onglet **Storage** du projet → **Upstash for Redis** (Marketplace, plan *Free*) → connecte-le au projet. Les variables `KV_REST_API_URL` et `KV_REST_API_TOKEN` sont ajoutées automatiquement.
3. **Settings → Environment Variables** → ajoute `PULSE_TOKEN` avec un secret au hasard (`openssl rand -hex 32` dans le Terminal).
4. **Redeploy**, puis vérifie :
   ```bash
   curl -H "Authorization: Bearer TON_PULSE_TOKEN" https://TON-PROJET.vercel.app/api/state
   ```

### 2. Mac (Claude Code)

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

### 3. App iPhone

1. Dans Xcode : **Réglages → Comptes → +** → connecte ton Apple ID (gratuit).
2. Sur l'iPhone : **Réglages → Confidentialité et sécurité → Mode développeur** → activer (l'iPhone redémarre).
3. Sur le Mac :
   ```bash
   brew install xcodegen
   cd ios
   ./setup.sh https://TON-PROJET.vercel.app TON_PULSE_TOKEN
   ```
   Le script écrit `ios/Shared/PulseSecrets.swift` (ignoré par git), génère `ClaudePulse.xcodeproj` et l'ouvre.
4. Dans Xcode, pour les cibles **ClaudePulse** et **ClaudePulseWidgets** : *Signing & Capabilities* → **Team** = ton *Personal Team*. Une seule fois : `update.sh` la retient ensuite. Si Xcode refuse le bundle ID, remplace `com.lucasotw` par autre chose dans `project.yml` et relance `./setup.sh`.
5. Branche l'iPhone, choisis-le comme destination, **Run** (⌘R).
6. Au premier lancement, iOS bloque l'app : **Réglages → Général → VPN et gestion de l'appareil** → ton Apple ID → **Faire confiance**.
7. Dans l'app : **Lancer la surveillance** → accepte les notifications → ⚙️ → **Démo : tâche en cours** → verrouille l'iPhone.
8. Ajoute le widget : appui long sur l'écran d'accueil → **+** → *Claude Pulse*.

### Mettre à jour

Une seule commande, puis ⌘R dans Xcode :

```bash
~/claude-pulse/update.sh
```

Elle récupère la dernière version, met à jour les scripts Claude Code, régénère le projet Xcode en gardant ton équipe de signature et l'ouvre. Le backend se redéploie tout seul sur Vercel à chaque push sur `main`.

---

## Ce que voit l'iPhone

| Événement Claude Code | Effet |
| --- | --- |
| `UserPromptSubmit` | début d'une tâche (chrono) |
| `PreToolUse` (au plus 1 fois / 30 s, sauf TodoWrite / Agent / Workflow) | « ce que fait Claude », progression TodoWrite, nom et phases du workflow |
| `TaskCreated` / `TaskCompleted` | progression de la liste de tâches |
| `SubagentStart` / `SubagentStop` | nombre de sous-agents actifs |
| `Notification` (`permission_prompt`…) | **notification « attend ta validation »** |
| `Stop` | **notification « terminé »** si la tâche a duré plus de 30 s, sauf si un workflow tourne encore en arrière-plan |
| `StopFailure` | erreur (rate limit, surcharge…) |
| status line (1 relevé / min) | coût, % contexte, limites 5 h / 7 jours |

Une session « en cours » sans nouvelles depuis 20 min passe en inactive : interrompre Claude avec Échap ne déclenche aucun hook.

Réglages côté Mac (`~/.claude/claude-pulse/config`) : `PULSE_HEARTBEAT=30`, `PULSE_USAGE_EVERY=60`.
Rythme côté iPhone : `activeInterval` / `idleInterval` dans [`ios/ClaudePulse/LiveMonitor.swift`](ios/ClaudePulse/LiveMonitor.swift).

## Quotas gratuits

Chaque lecture de l'iPhone coûte 5 commandes Redis, chaque événement du Mac environ 7. Une journée de 8 h de surveillance avec Claude actif la moitié du temps représente environ 15 000 commandes, soit de l'ordre de 300 000 par mois : ça tient dans le plan gratuit d'Upstash. Si tu approches de la limite, augmente `activeInterval` et `PULSE_HEARTBEAT`, ou arrête la surveillance quand tu ne t'en sers pas.

## Limites connues

- **Phase exacte d'un workflow** : Claude Code n'émet pas d'événement par phase. On affiche le nom du workflow, ses phases déclarées, les sous-agents actifs et le fait qu'il tourne en arrière-plan.
- **Limites 5 h / 7 jours** : fournies par Claude Code uniquement avec un abonnement Pro / Max, après le premier message d'une session.
- **Coût en dollars** : Claude Code calcule ce que ta session coûterait au tarif public de l'API. Avec un abonnement Pro / Max, ce n'est pas ce que tu paies : l'app ne l'affiche donc pas, seules les limites 5 h / 7 jours comptent.
- **Temps restant** : estimé à partir de la liste de tâches de Claude (durée moyenne des étapes déjà faites × étapes restantes). Il n'apparaît qu'une fois la première étape terminée, et seulement quand Claude a fait une liste.
- **Widget** : iOS décide de son rythme de rafraîchissement (≈ toutes les 5 à 15 min) ; l'app le force quand un statut change pendant la surveillance.

## Développement

```bash
cd backend && npm test   # machine à états + test de bout en bout (faux Redis)
```

```
backend/
  api/hook.js     événements des hooks → état de la session
  api/usage.js    relevés de la status line
  api/state.js    lu par l'app et le widget (1 requête Redis)
  api/test.js     démo depuis l'app
  lib/state.js    machine à états (pure, testée)
  lib/store.js    clés Redis
  lib/redis.js    Upstash REST, sans dépendance
ios/
  setup.sh        écrit PulseSecrets.swift, génère et ouvre le projet
  generate.sh     régénère le projet en gardant l'équipe (Local.xcconfig)
  Shared/         modèles, API, config, styles, attributs de la Live Activity
  ClaudePulse/    app : surveillance (LiveMonitor), son silencieux, notifications
  ClaudePulseWidgets/  widget + Live Activity / Dynamic Island
mac/
  hook.sh  statusline.sh  install.sh  uninstall.sh
update.sh         met tout à jour sur le Mac
```
