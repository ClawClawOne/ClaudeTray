# ClaudeTray

Votre quota Claude dans la barre de menu de macOS. Le temps restant avant le reset, le pourcentage
consommé sur la fenêtre glissante de 5 h, sur la fenêtre hebdomadaire, et sur chaque quota par
modèle — sans ouvrir de terminal.

![ClaudeTray dans la barre de menu](docs/menubar.png)

App native SwiftUI, macOS 14+, **zéro dépendance**, une seule connexion sortante, aucune télémétrie.

> Projet indépendant, sans lien avec Anthropic. Il s'appuie sur un endpoint non documenté, celui
> qu'utilise la commande `/usage` de Claude Code : il peut cesser de fonctionner sans préavis.

## Prérequis : Claude Code installé et connecté

ClaudeTray n'a pas de compte à lui. Il lit le token OAuth déposé par **Claude Code**, le client en
ligne de commande. Sans lui, l'app n'a aucune source de données et affichera « Aucun token trouvé ».

L'app Claude de bureau ne convient pas : elle ne dépose au trousseau qu'une clé de chiffrement
Electron (`Claude Safe Storage`), inexploitable ici.

```bash
npm install -g @anthropic-ai/claude-code   # ou l'installeur officiel
claude                                     # puis /login
```

**Installer ne suffit pas : c'est la connexion qui écrit le token.** Une fois connecté, vous n'êtes
pas obligé d'utiliser Claude Code — il se contente de rafraîchir le token quand il tourne. Si vous
ne le lancez jamais, le token du trousseau finit par expirer : utilisez alors un token durable,
`claude setup-token` en produit un valable un an, à coller dans ClaudeTray.

Testé sur un abonnement Max. Le comportement sur les autres formules n'a pas été vérifié.

## Installation

1. Téléchargez le `.dmg` depuis la page [Releases](../../releases).
2. Ouvrez-le, glissez **ClaudeTray** dans **Applications**.
3. Lancez l'app. Elle n'a pas d'icône dans le Dock : elle apparaît dans la barre de menu, en haut à droite.
4. macOS demande l'autorisation d'accéder au trousseau — c'est la lecture du token de Claude Code.
   Choisissez **Toujours autoriser** pour ne plus être sollicité.

L'app est signée Developer ID et notarisée par Apple : aucun avertissement Gatekeeper, aucune
manipulation particulière au premier lancement.

Pour la désinstaller : bouton **Quitter** dans le popover, puis supprimez
`/Applications/ClaudeTray.app` et le dossier `~/Library/Application Support/ClaudeTray`.

## Utilisation

Cliquez sur l'indicateur dans la barre de menu pour ouvrir le popover : une barre de progression par
fenêtre de quota, chacune avec son pourcentage et son compte à rebours jusqu'au reset.

Le pourcentage passe en **orange à 80 %** et en **rouge à 95 %**, dans la barre de menu comme dans le
popover. Une notification locale est envoyée à ces deux seuils, une seule fois par fenêtre, puis
réarmée au reset suivant.

### Réglages, tous dans le popover

| Réglage | Effet |
| --- | --- |
| Rafraîchissement | Auto, 1 min, 5 min, 15 min, 30 min, 1 h |
| Logo Claude | Affiché ou masqué dans la barre de menu |
| Fenêtres affichées | Toutes côte à côte, ou une seule métrique au choix |
| Métrique unique | Fenêtre 5 h, hebdomadaire, ou la plus contrainte des deux |
| Consommé / restant | Inverse la valeur affichée |
| Couleur | Huit pastilles pour les pourcentages sous le seuil d'alerte |
| Espacement | Écart entre les éléments, 2 à 24 pt |
| Marge extérieure | Marge gauche et droite, 0 à 24 pt |
| Notifications | Alertes à 80 % et 95 %, activables |
| Lancement au démarrage | Via `SMAppService` |

En mode **Auto**, l'app interroge l'API toutes les 90 s quand la fenêtre de 5 h est entamée, toutes
les 7 min sinon. Les comptes à rebours, eux, s'animent en local à la seconde : ils ne coûtent aucune
requête. Le polling est suspendu en veille et session verrouillée, et reprend au réveil.

### Colonnes affichées

`5H` et `WEEK` viennent des fenêtres principales. Les colonnes supplémentaires — `FABLE`, `OPUS`… —
correspondent aux quotas par modèle, tels que l'API les nomme. Aucune liste n'est figée dans le
code : une colonne apparaît si le compte a ce quota, disparaît sinon. Aucune ligne vide n'est laissée.

## Dépannage

| Ce que vous voyez | Cause | Solution |
| --- | --- | --- |
| « Aucun token trouvé » | Claude Code absent ou jamais connecté | `claude` puis `/login`, ou collez un token issu de `claude setup-token` |
| « 401 — token refusé ou expiré » | Token périmé, Claude Code inactif depuis longtemps | Lancez `claude` une fois, ou utilisez un token `setup-token` |
| « 429 — trop de requêtes » | API sollicitée trop souvent | Rien à faire : l'app ralentit seule, jusqu'à 30 min entre deux essais |
| « Réponse au format inattendu » | L'endpoint non documenté a changé | Ouvrez une issue ; les dernières données valides restent affichées |
| « Données obsolètes depuis X » | Aucun appel réussi depuis 15 min | Bouton **Rafraîchir**, ou vérifiez le réseau |
| La boîte de dialogue du trousseau revient sans cesse | Version non signée, compilée localement | Choisissez **Toujours autoriser**, ou collez un token manuel |
| Rien dans la barre de menu | Barre saturée | Quittez un autre élément, ou réduisez l'espacement dans les réglages |

Le pied du popover indique en permanence la source du token utilisée, l'heure du dernier
rafraîchissement réussi et le message d'erreur en cours, s'il y en a un.

## Sécurité et vie privée

- **Une seule connexion sortante**, en HTTPS, vers `api.anthropic.com`. Aucune télémétrie, aucun
  service tiers, aucune dépendance externe : uniquement des frameworks Apple.
- **Aucune journalisation.** Le token n'est ni imprimé, ni écrit dans un log, ni inclus dans les
  messages d'erreur affichés.
- **Token jamais conservé en mémoire** entre deux appels : il est relu à chaque requête, parce que
  celui du trousseau expire en une heure environ.
- **Token manuel en clair sur le disque**, dans `~/Library/Application Support/ClaudeTray/token`,
  en `0600` dans un dossier `0700`. Le fichier est créé avec ses droits restrictifs avant toute
  écriture, et ses droits sont resserrés à la lecture s'ils ont dérivé. Qui préfère ne rien écrire
  sur disque laisse ce champ vide : le trousseau reste alors la seule source.
- **Sandbox désactivée**, par nécessité : lire le trousseau et `~/.claude` est impossible autrement.
  Le durcissement d'exécution est actif et aucune exception de signature n'est demandée.
- **Aucune mise à jour automatique** : l'app ne télécharge et n'exécute jamais de code.

Ordre de résolution du token, à chaque appel :

1. `~/Library/Application Support/ClaudeTray/token` — le token collé dans l'app
2. Trousseau macOS, service `Claude Code-credentials`
3. `~/.claude/.credentials.json`, ou `$CLAUDE_CONFIG_DIR/.credentials.json`

## Compiler depuis les sources

Xcode 15+, macOS 14+. Le `.xcodeproj` est généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen)
depuis `project.yml`, mais il est commité : ouvrir le projet ne demande aucun outil.

```bash
git clone https://github.com/ClawClawOne/ClaudeTray.git
cd ClaudeTray
open ClaudeTray.xcodeproj      # puis ⌘R
```

Dans **Signing & Capabilities**, cochez *Automatically manage signing* et choisissez votre équipe.
Sans équipe, la signature reste ad-hoc et macOS redemandera l'accès au trousseau à chaque rebuild —
le champ de token manuel du popover sert d'échappatoire.

Après modification de `project.yml` :

```bash
xcodegen generate
xcodebuild -project ClaudeTray.xcodeproj -scheme ClaudeTray -configuration Debug build
```

Le projet compile sans aucun avertissement, et doit le rester.

### Produire un DMG signé et notarisé

```bash
./scripts/make-dmg.sh
```

Le script construit en Release, signe avec votre certificat *Developer ID Application*, fabrique le
DMG, l'envoie à la notarisation Apple, agrafe le ticket et vérifie le tout avec `spctl`. Deux
préparatifs, une seule fois : un certificat Developer ID installé dans le trousseau, et les
identifiants de notarisation enregistrés sous un profil nommé.

```bash
xcrun notarytool store-credentials claudetray \
  --apple-id "vous@exemple.com" --team-id "XXXXXXXXXX" --password "mot-de-passe-pour-application"
```

Le mot de passe est un *mot de passe pour application* créé sur appleid.apple.com. Pour un essai
local sans notarisation : `SKIP_NOTARIZE=1 ./scripts/make-dmg.sh`.

## Sous le capot

Source de données, la même que `/usage` dans Claude Code :

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <access_token>
anthropic-beta: oauth-2025-04-20
```

Le header `anthropic-beta` est obligatoire : sans lui, l'API répond 401. Il ne s'agit pas d'une clé
API à la consommation — `ANTHROPIC_API_KEY` n'apparaît nulle part et ne fonctionnerait pas ici.

L'endpoint étant non documenté, l'app est écrite pour échouer proprement : elle garde le dernier
instantané valide à l'écran, nomme précisément ce qui a échoué (401, 429, schéma inattendu, réseau)
et marque les données comme obsolètes au-delà de 15 min. Elle n'invente jamais de date de reset :
seul `resets_at` est affiché, ou « non communiqué par l'API ».

Si l'API change, voici où intervenir :

| Symptôme | Fichier |
| --- | --- |
| 401 permanent avec un token valide | `UsageAPIClient.betaHeader` — la valeur du header beta a changé |
| « Réponse au format inattendu » | `Models/UsageModels.swift`, `RawUsageResponse` / `RawLimit` |
| Pourcentages ×100 ou ÷100 | `Utilization.normalize` — seul endroit qui décide de l'échelle |
| Date de reset non décodée | `UsageAPIClient.decodeISODate` |
| 429 récurrents | `activeInterval` / `idleInterval` / `maxBackoff` dans `UsageStore.swift` |

Structure du code :

```
ClaudeTray/
├── ClaudeTrayApp.swift          MenuBarExtra, style .window
├── Models/UsageModels.swift     décodage, normalisation, instantané affichable
├── Services/
│   ├── TokenResolver.swift      les trois sources de token, dans l'ordre
│   ├── UsageAPIClient.swift     unique appel réseau, erreurs, dates ISO
│   ├── UsageStore.swift         état observable, cadence, backoff, veille
│   ├── NotificationManager.swift  seuils 80 % / 95 %
│   └── LaunchAtLogin.swift      SMAppService
├── Support/                     réglages persistés, couleurs
└── Views/                       barre de menu, popover, formatage
```

Deux contournements valent d'être connus avant de toucher à l'interface : `MenuBarExtra` ne rend pas
une vue sur deux lignes (le label est donc rasterisé via `ImageRenderer`), et un `ColorPicker` est
inutilisable dans un popover de barre de menu (il ouvre `NSColorPanel`, qui referme le popover).
`CLAUDE.md` détaille ces pièges.

## Licence

MIT — voir [LICENSE](LICENSE).
