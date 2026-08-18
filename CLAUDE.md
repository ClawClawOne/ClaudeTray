# ClaudeTray — notes de travail

App macOS en barre de menu, SwiftUI natif, macOS 14+, **zéro dépendance externe**.
Elle affiche l'usage du quota Claude (abonnement Max) : fenêtre 5 h, fenêtre hebdomadaire,
et une colonne par modèle limité (FABLE, OPUS… selon ce que renvoie l'API).

Le cahier des charges d'origine est dans `ClaudeTray.md`. Le README couvre l'installation,
la signature et les décisions de conception. Ce fichier ne répète ni l'un ni l'autre : il liste
ce qui casse si on l'ignore.

## Prérequis utilisateur

Claude Code installé **et connecté** (`claude` puis `/login`) : c'est la connexion, pas
l'installation, qui écrit l'entrée de trousseau `Claude Code-credentials`. L'app Claude de bureau
ne convient pas — elle ne dépose qu'une clé Electron `Claude Safe Storage`, inexploitable ici.

## Règles à ne pas enfreindre

- **Une seule requête sortante**, vers `https://api.anthropic.com/api/oauth/usage`. Aucune
  télémétrie, aucun paquet tiers, aucun SDK. Toute nouvelle dépendance réseau est un bug.
- **Header `anthropic-beta: oauth-2025-04-20` obligatoire.** Sans lui, l'endpoint répond 401.
- **Jamais de `ANTHROPIC_API_KEY`.** C'est un abonnement Max, pas une clé à la consommation.
- **Le token n'est jamais mis en cache en mémoire.** Celui du trousseau expire en ~1 h et Claude
  Code le réécrit ; `TokenResolver.resolve()` est rappelé à chaque appel réseau.
- **Aucun reset calculé localement.** On affiche `resets_at` tel quel, ou « non communiqué ».
  Le comportement réel de la fenêtre hebdo est instable : une prédiction fausse est pire que rien.
- **Une erreur n'efface jamais les données.** Le dernier instantané valide reste à l'écran, avec
  un message lisible et un marqueur « obsolète depuis X » au-delà de 15 min.
- **Respecter la cadence.** L'endpoint renvoie des 429 persistants s'il est trop sollicité :
  90 s / 7 min en mode Auto, backoff exponentiel plafonné à 30 min, `Retry-After` prioritaire.
  Aucune option en dessous de la minute.

## Pièges déjà rencontrés

- **`MenuBarExtra` ne rend pas une vue sur deux lignes** : il la réduit à son premier élément.
  `MenuBarLabel` rasterise donc sa vue via `ImageRenderer` et fournit une `Image`. Conséquence :
  clair/sombre résolu à la main via `NSApp.effectiveAppearance`, rendu rafraîchi une fois par seconde.
- **`ColorPicker` est inutilisable dans un popover de barre de menu** : il ouvre `NSColorPanel`,
  qui prend le focus et referme le popover avant toute validation. D'où les pastilles de couleur.
- **Le quota par modèle n'est pas dans `seven_day_opus` / `seven_day_sonnet`** (tous deux `null`
  sur ce compte) mais dans le tableau `limits`, entrées `kind == "weekly_scoped"`, nom du modèle
  sous `scope.model.display_name`. Aucune liste de modèles n'est figée dans le code.
- **`resets_at` arrive avec ou sans fraction de seconde.** Les deux formats doivent passer, sinon
  le décodage casse au hasard des réponses.
- **L'autorisation du trousseau est liée à la signature du binaire.** Chaque rebuild ad-hoc
  redéclenche la boîte de dialogue ; d'où le token manuel accessible en un clic dans le popover.

## Où intervenir

| Sujet | Fichier |
| --- | --- |
| Échelle des pourcentages | `Models/UsageModels.swift`, `Utilization.normalize` — **seul** endroit |
| Schéma de la réponse | `Models/UsageModels.swift`, `RawUsageResponse` / `RawLimit` |
| Header beta, erreurs HTTP, dates | `Services/UsageAPIClient.swift` |
| Sources du token | `Services/TokenResolver.swift` |
| Cadence, backoff, veille | `Services/UsageStore.swift` |
| Rendu de la barre de menu | `Views/MenuBarLabel.swift` |

## Build

Le `.xcodeproj` est généré par XcodeGen depuis `project.yml`, et commité pour que l'ouverture
dans Xcode ne demande aucun outil. Après modification de `project.yml` :

```bash
xcodegen generate
xcodebuild -project ClaudeTray.xcodeproj -scheme ClaudeTray -configuration Debug build
```

Le projet doit compiler **sans aucun avertissement**. C'est le cas aujourd'hui, ça doit le rester.

Distribution : `./scripts/make-dmg.sh` (Release, signature Developer ID, DMG, notarisation,
agrafage). Voir la section « Distribuer un DMG » du README pour les deux préparatifs.

## Langue

Interface, commentaires de code et messages de commit en français. Les termes techniques, noms
d'API et chaînes d'erreur restent tels quels.
