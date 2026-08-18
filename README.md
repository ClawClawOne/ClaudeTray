# ClaudeTray

App macOS en barre de menu, SwiftUI natif, zéro dépendance. Affiche l'usage du quota Claude
(abonnement Max) en temps réel : fenêtre glissante de 5 h, fenêtre hebdomadaire, et les fenêtres
par modèle quand l'API les renvoie — chacune avec son pourcentage et son compte à rebours.

## Prérequis : Claude Code connecté

ClaudeTray lit le token OAuth écrit par **Claude Code**, le client en ligne de commande. C'est un
prérequis, pas une option : l'app Claude de bureau ne crée pas ce token — elle ne dépose au trousseau
qu'une clé de chiffrement Electron (`Claude Safe Storage`), inexploitable ici.

Sur une machine neuve :

```bash
npm install -g @anthropic-ai/claude-code   # ou l'installeur officiel
claude                                     # puis /login
```

**Installer ne suffit pas : c'est la connexion qui écrit l'entrée de trousseau.** Une fois connecté,
Claude Code n'a plus besoin d'être utilisé — il rafraîchit simplement le token quand il tourne.
Alternative sans trousseau : `claude setup-token` produit un token d'un an, à coller dans le popover.

L'app cible un abonnement Claude (vérifiée sur un compte Max). Le comportement de l'endpoint sur les
autres formules n'a pas été testé.

## Ouvrir dans Xcode

Le projet Xcode est généré par [XcodeGen](https://github.com/yonaskolb/XcodeGen) depuis `project.yml`.
`ClaudeTray.xcodeproj` est déjà présent dans le dépôt : ouvrir directement suffit.

```bash
open ClaudeTray.xcodeproj
```

Si `project.yml` est modifié (nouveau fichier, réglage de build) :

```bash
brew install xcodegen   # une seule fois
xcodegen generate
```

Build en ligne de commande :

```bash
xcodebuild -project ClaudeTray.xcodeproj -scheme ClaudeTray -configuration Debug build
```

### Premier lancement — quoi cliquer

1. `open ClaudeTray.xcodeproj`
2. Dans le navigateur de projet (colonne de gauche), sélectionner le projet **ClaudeTray** tout en haut,
   puis la cible **ClaudeTray** au centre.
3. Onglet **Signing & Capabilities** : cocher **Automatically manage signing**, et choisir ton
   compte dans **Team**. Sans équipe, la signature reste ad-hoc et macOS redemandera l'accès au
   trousseau à chaque rebuild (voir plus bas).
4. Barre du haut : vérifier que le schéma affiché est **ClaudeTray** et la destination **My Mac**.
5. **⌘R**.

L'app n'a pas d'icône dans le Dock (`LSUIElement = true`). Elle apparaît dans la barre de menu, en haut
à droite, sous la forme d'un pourcentage. Cliquer dessus ouvre le popover. Pour l'arrêter : bouton
**Quitter** dans le popover, ou **⌘.** dans Xcode.

## Autorisation du trousseau au premier lancement

Au premier appel réseau, l'app lit l'entrée de trousseau générique de service `Claude Code-credentials`
(celle qu'écrit Claude Code) via `SecItemCopyMatching`. macOS affiche alors une boîte de dialogue :
choisir **Toujours autoriser** pour ne plus être sollicité.

macOS lie cette autorisation à la signature du binaire. Chaque rebuild en signature ad-hoc produit un
binaire différent et redéclenche la boîte de dialogue. Deux parades :

- signature automatique avec une équipe de développement (étape 3 ci-dessus) ;
- **token manuel** : bouton « Coller un token manuel » dans le popover. Générer le token avec
  `claude setup-token` (validité un an), le coller, Enregistrer. Il est stocké en `0600` dans
  `~/Library/Application Support/ClaudeTray/token` et prend la priorité sur le trousseau. Le bouton
  « Effacer » revient au trousseau.

Ordre de résolution du token, à chaque appel réseau :

1. `~/Library/Application Support/ClaudeTray/token` (token manuel)
2. Trousseau macOS, service `Claude Code-credentials`
3. `~/.claude/.credentials.json` (ou `$CLAUDE_CONFIG_DIR/.credentials.json`)

Le token du trousseau expire en ~1 h et Claude Code le rafraîchit seul : il est relu à chaque appel,
jamais mis en cache en mémoire.

## Source de données

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <access_token>
anthropic-beta: oauth-2025-04-20
```

C'est l'endpoint OAuth non documenté qu'utilise `/usage` dans Claude Code. Le header `anthropic-beta`
est obligatoire — sans lui, l'API répond 401. Il ne s'agit pas d'une clé API à la consommation :
`ANTHROPIC_API_KEY` n'apparaît nulle part dans le code et ne fonctionnerait pas ici.

Vérification manuelle :

```bash
security find-generic-password -s "Claude Code-credentials" -w \
  | jq -r '.claudeAiOauth.accessToken' \
  | xargs -I{} curl -s -H "Authorization: Bearer {}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      https://api.anthropic.com/api/oauth/usage | jq
```

C'est la **seule** requête sortante de l'app. Aucune télémétrie, aucune dépendance externe.

## Cadence de polling

L'endpoint renvoie des 429 persistants s'il est sollicité trop souvent.

- Mode **Auto** (défaut) : 90 s quand la fenêtre 5 h est entamée (`utilization > 0`), 7 min sinon.
- Cadence fixe au choix dans les réglages : 1 min, 5 min, 15 min, 30 min, 1 h. Changer la cadence
  ne déclenche pas d'appel immédiat — le prochain appel est replanifié à partir du dernier.
- Backoff exponentiel après échec, plafonné à 30 min, et `Retry-After` respecté s'il est présent.
- Polling suspendu en veille et session verrouillée (`NSWorkspace.willSleep` /
  `sessionDidResignActive` / `com.apple.screenIsLocked`), repris par un appel immédiat au réveil.
- Le compte à rebours s'anime localement à 1 s à partir de `resets_at`, sans aucun appel réseau.

## Le jour où ça casse

L'endpoint n'est pas documenté ; il peut changer de forme ou de header sans préavis. L'app ne montre
jamais 0 % en cas de problème : elle garde le dernier instantané valide à l'écran, ajoute un message
d'erreur lisible en pied de popover (401, 429, schéma inattendu, réseau) et un marqueur
« Données obsolètes depuis X » au-delà de 15 min sans succès.

Points à modifier selon le symptôme :

| Symptôme | Où intervenir |
| --- | --- |
| 401 permanent alors que le token est bon | `UsageAPIClient.betaHeader` — la valeur du header beta a changé |
| « Réponse au format inattendu » | `RawUsageResponse` dans `Models/UsageModels.swift` — les clés de fenêtres ont changé |
| Pourcentages ×100 ou ÷100 | `Utilization.normalize` dans `Models/UsageModels.swift` — seul endroit qui décide de l'échelle |
| Date de reset non décodée | `UsageAPIClient.decodeISODate` |
| 429 récurrents | `activeInterval` / `idleInterval` / `maxBackoff` dans `Services/UsageStore.swift` |

## Structure

```
ClaudeTray/
├── ClaudeTrayApp.swift          MenuBarExtra, style .window
├── Models/UsageModels.swift     décodage brut, normalisation, instantané affichable
├── Services/
│   ├── TokenResolver.swift      les trois sources de token, dans l'ordre
│   ├── UsageAPIClient.swift     unique appel réseau, mapping des erreurs, dates ISO
│   ├── UsageStore.swift         état observable, cadence, backoff, veille, horloge 1 s
│   ├── NotificationManager.swift  seuils 80 % / 95 %, une fois par fenêtre
│   └── LaunchAtLogin.swift      SMAppService
├── Support/Preferences.swift    réglages persistés, seuils
└── Views/                       barre de menu, popover, ligne de fenêtre, formatage
```

Le réseau, la résolution du token, le modèle observable et les vues ne se connaissent que par leurs
interfaces : `UsageStore` est le seul point de contact entre les services et les vues.

## Réglages (popover)

- Rafraîchissement : Auto, 1 min, 5 min, 15 min, 30 min, 1 h.
- Barre de menu : les fenêtres côte à côte (5H / WEEK, plus une colonne par modèle limité —
  FABLE, OPUS… selon ce que renvoie l'API), ou une seule métrique — fenêtre 5 h,
  hebdomadaire, ou la plus contrainte des deux.
- Couleur des pourcentages : huit pastilles cliquables (vert par défaut).
- Logo Claude affiché ou masqué. Masqué, les colonnes gardent la même marge des deux côtés.
- Espacement entre les éléments de la barre de menu, de 2 à 24 pt (10 pt par défaut).
- Marge extérieure gauche et droite, de 0 à 24 pt (0 par défaut). À 0, il ne reste que la marge
  que macOS impose lui-même au bouton de la barre de menu ; l'app n'en ajoute aucune.
- Afficher le restant plutôt que le consommé.
- Notifications à 80 % et 95 % de chaque fenêtre, une seule fois par fenêtre, ré-armées au reset.
- Lancement au démarrage (`SMAppService`).

## Décisions prises seul

- **Échelle de `utilization` : aucune heuristique.** Vérifié sur l'API le 2026-08-18, les valeurs
  sortent déjà en 0–100 (`31.0`, `33.0`). Une bascule automatique « si ≤ 1 alors ×100 » afficherait
  100 % pour un usage réel de 1 % — la pire fausse alerte possible, dans le cas le plus fréquent. La
  conversion reste centralisée dans `Utilization.normalize`, avec la ligne à décommenter si l'API
  repasse un jour en 0–1.
- **Barre de menu par défaut : les deux fenêtres.** Logo Claude, puis une colonne « 5h » et une
  colonne « Week », intitulé au-dessus du pourcentage. Le mode métrique unique reste disponible et
  utilise alors « la plus contrainte » par défaut — le seul chiffre qui ne peut pas mentir par
  omission quand une seule des deux fenêtres est proche de la limite.
- **Label de barre de menu rasterisé.** `MenuBarExtra` ne rend pas une vue composée sur deux
  lignes : il la réduit à son premier élément. `MenuBarLabel` rend donc sa vue via `ImageRenderer`
  et fournit une `Image`. Contrepartie assumée : le clair/sombre est résolu à la main
  (`NSApp.effectiveAppearance`), et le rendu est rafraîchi une fois par seconde.
- **Logo Claude dessiné en `Path`** (`Views/ClaudeGlyph.swift`), pas en asset : rien à embarquer et
  rendu net à toutes les tailles.
- **Pastilles de couleur plutôt qu'un `ColorPicker`.** Le `ColorPicker` ouvre `NSColorPanel`,
  qui prend le focus et referme aussitôt le popover de la barre de menu : le choix était
  impossible à valider. Huit pastilles cliquables règlent le problème sans quitter le popover.
- **Fenêtres par modèle lues dans `limits`.** `seven_day_sonnet` et `seven_day_opus` sont `null`
  sur ce compte ; le quota par modèle n'existe que dans le tableau `limits`, entrées
  `kind == "weekly_scoped"`, avec le nom du modèle dans `scope.model.display_name`. La colonne
  FABLE en vient. Aucune liste de modèles n'est figée dans le code : l'app affiche ce que l'API nomme.
- **Couleur personnalisable pour le confort seulement.** Le `ColorPicker` change la couleur sous
  80 % ; les seuils orange 80 % et rouge 95 % ne sont pas modifiables, ce sont eux qui alertent.
- **Cadence fixe autorisée jusqu'à 1 min.** L'endpoint renvoie des 429 s'il est trop sollicité : en
  dessous de la minute, aucune option n'est proposée, et le backoff exponentiel plafonné à 30 min
  s'applique de toute façon par-dessus la cadence choisie.
- **Fenêtres affichées : celles que l'API renvoie non nulles.** `seven_day_sonnet` et
  `seven_day_opus` sont donc masquées quand elles valent `null` (c'est le cas sur ce compte).
  Aucune ligne vide n'est laissée.
- **Champs ignorés.** La réponse contient aussi `limits`, `spend`, `extra_usage` et une série de
  clés à noms de code (`nimbus_quill`, `tangelo`, …). Elles ne sont pas décodées : hors périmètre des
  trois informations demandées, et instables par nature.
- **Détection du changement de schéma.** Si aucune des quatre fenêtres connues n'est présente dans une
  réponse 200, l'app lève « format inattendu » plutôt que d'afficher un popover vide.
- **Obsolescence à 15 min.** Au-delà, le pourcentage de la barre de menu reçoit un marqueur discret et
  le popover indique depuis combien de temps.
- **Couleur pilotée par le consommé.** Même en mode « restant », les seuils orange 80 % / rouge 95 %
  suivent le pourcentage consommé : c'est lui qui porte l'alerte.
- **Ne survit pas à un reset inventé.** Aucune date de reset n'est calculée localement. Quand
  `resets_at` est `null`, l'app écrit « Reset non communiqué par l'API ».
- **Langue de l'interface : français**, alignée sur la langue du cahier des charges.
- **Projet généré par XcodeGen.** `project.yml` est la source de vérité et se relit en trente
  secondes ; le `.xcodeproj` est commité pour que l'ouverture dans Xcode ne demande aucun outil.

## Prérequis

macOS 14+, Swift 5.9+, Xcode 15+. Pas de sandbox (lecture du trousseau et de `~/.claude`),
entitlement client réseau activé, `LSUIElement = true`.
