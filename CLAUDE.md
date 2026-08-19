# ClaudeTray — notes de travail

App macOS en barre de menu, SwiftUI natif, macOS 14+, **zéro dépendance externe**.
Elle affiche l'usage du quota Claude (abonnement Max) : fenêtre 5 h, fenêtre hebdomadaire,
et une colonne par modèle limité (FABLE, OPUS… selon ce que renvoie l'API).

Version courante : **1.4**. Dépôt public sous licence MIT, releases sur GitHub.

Tout ce dépôt est public, ce fichier compris : il tient lieu de guide de contribution. Aucun secret,
aucun identifiant Apple, aucun chemin local n'y entre — les seuls identifiants du dépôt sont les
gabarits `"ton@email"` / `"XXXXXXXXXX"` du script de build.

Le cahier des charges d'origine est dans `ClaudeTray.md`. Le `README.md` — rédigé en anglais, il
s'adresse aux utilisateurs — couvre l'installation, la signature et les décisions de conception.
`CHANGELOG.md` sert de notes de release. Ce fichier ne répète aucun des trois : il liste ce qui
casse si on l'ignore.

## Prérequis utilisateur

Claude Code installé **et connecté** (`claude` puis `/login`) : c'est la connexion, pas
l'installation, qui écrit l'entrée de trousseau `Claude Code-credentials`. L'app Claude de bureau
ne convient pas — elle ne dépose qu'une clé Electron `Claude Safe Storage`, inexploitable ici.

## Règles à ne pas enfreindre

- **Deux destinations sortantes, pas une de plus** : `https://api.anthropic.com/api/oauth/usage`
  pour les quotas, et `https://api.github.com/repos/ClawClawOne/ClaudeTray/releases/latest` pour la
  vérification quotidienne de version, anonyme et débrayable (`updateCheckEnabled`). Aucune
  télémétrie, aucun paquet tiers, aucun SDK. Toute autre dépendance réseau est un bug.
- **Header `anthropic-beta: oauth-2025-04-20` obligatoire.** Sans lui, l'endpoint répond 401.
- **Jamais de `ANTHROPIC_API_KEY`.** C'est un abonnement Max, pas une clé à la consommation.
- **Le token n'est jamais mis en cache en mémoire.** Celui du trousseau expire en ~1 h et Claude
  Code le réécrit ; `TokenResolver.resolve()` est rappelé à chaque appel réseau.
- **Notifications déclenchées au franchissement, jamais sur un état.** Une notification part
  uniquement si le pourcentage était sous le seuil au relevé précédent et l'atteint au relevé
  courant. Ne jamais ré-armer sur `resets_at` : la date de reset de la fenêtre 5 h avance à chaque
  appel, ce qui renvoyait une notification à chaque rafraîchissement (bug 1.1).
- **La source du token est publiée à la résolution, pas au succès.** `UsageStore.fetchOnce` fixe
  `tokenSource` avant la requête. Sinon un token manuel refusé laisse à l'écran la source du dernier
  succès (le trousseau), et l'app a l'air d'ignorer le token collé alors qu'elle vient de l'utiliser
  et de se faire refuser (bug 1.2).
- **Le token manuel prime tant que le fichier existe**, même s'il déclenche un 401. Le seul retour
  au trousseau est la suppression du fichier via « Effacer le token manuel ». Ce bouton ne touche
  jamais l'autorisation trousseau accordée à ClaudeTray : rien dans l'app ne peut la révoquer, ça se
  fait dans Trousseaux d'accès.
- **Ne jamais toucher aux entrées de trousseau des autres.** L'item `Claude Code-credentials`
  appartient à Claude Code. `KeychainAccessRevoker` ne retire que les applications de confiance dont
  le chemin désigne ClaudeTray, et n'écrit rien s'il n'y en a aucune. La liste de partitions
  (`teamid:`, `apple-tool:`) est laissée intacte : la réécrire risquerait de couper Claude Code de
  ses propres identifiants.
- **Aucun reset calculé localement.** On affiche `resets_at` tel quel, ou « non communiqué ».
  Le comportement réel de la fenêtre hebdo est instable : une prédiction fausse est pire que rien.
- **Une erreur n'efface jamais les données.** Le dernier instantané valide reste à l'écran, avec
  un message lisible et un marqueur « obsolète depuis X » au-delà de 15 min.
- **Respecter la cadence.** L'endpoint renvoie des 429 persistants s'il est trop sollicité :
  cadence minimale 5 min, backoff exponentiel plafonné à 30 min, `Retry-After` prioritaire.
  Le mode « Auto » (90 s quand la fenêtre 5 h était entamée) a été retiré en 1.6 : il provoquait
  des 429 en série. Ne jamais réintroduire d'option sous les 5 minutes.
- **Toute chaîne visible passe par `Loc`.** Aucune chaîne d'interface écrite en dur dans une vue :
  cinq langues sont maintenues, et une chaîne oubliée est une régression visible.
- **Le token manuel s'écrit en 0600 avant de recevoir la moindre donnée.** Ne jamais revenir à
  `write(options: .atomic)` suivi d'un `chmod` : cette séquence expose le token entre les deux.

## Localisation

Anglais, français, allemand, espagnol, italien. Tout est dans `Support/Localization.swift` :

- `AppLanguage` — les six choix du sélecteur, `system` compris ; `resolved` fait correspondre les
  préférences macOS à une langue prise en charge, anglais par repli.
- `Loc` — une propriété calculée par chaîne, chacune appelant `p(en, fr, de, es, it)`. Ajouter une
  chaîne oblige donc à fournir les cinq traductions, et le compilateur refuse un oubli.

Pas de fichiers `.lproj` : `NSLocalizedString` fige la langue au lancement, alors que le sélecteur
doit s'appliquer immédiatement. Conséquences à garder en tête :

- Les vues lisent `store.loc`, jamais `Loc(...)` directement — sinon le changement de langue ne les
  redessine pas.
- Les erreurs ne portent pas de texte : `UsageAPIError` et `TokenError` exposent `message(_ loc:)`,
  et `UsageStore` stocke l'erreur, pas sa traduction. Une erreur affichée se retraduit donc toute
  seule quand la langue change.
- Les formateurs de date sont construits à la demande avec `loc.locale`, jamais mis en cache dans un
  `static let` verrouillé sur une locale.
- `5H` et `WEEK` restent en anglais dans la barre de menu : ce sont des abréviations universelles, et
  les traduire ferait varier la largeur de l'indicateur d'une langue à l'autre.
- Ajouter une langue : une valeur dans `AppLanguage`, son `nativeName`, son `localeIdentifier`, son
  préfixe dans `resolved`, un argument à `p(...)`. Le compilateur signale ensuite chaque chaîne à traduire.

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
| Source affichée, erreurs de token | `Services/UsageStore.swift`, `fetchOnce` |
| Révocation de l'accès trousseau | `Services/KeychainAccessRevoker.swift` |
| Icône de l'app | `scripts/make-icon.swift`, sortie dans `ClaudeTray/Assets.xcassets` |
| Cadence, backoff, veille | `Services/UsageStore.swift` |
| Rendu de la barre de menu | `Views/MenuBarLabel.swift` |
| Vérification de version | `Services/UpdateChecker.swift` |
| Seuils et déclenchement des notifications | `Services/NotificationManager.swift` |
| Traductions, langues | `Support/Localization.swift` |
| Réglages persistés | `Support/Preferences.swift` (clés) et `Services/UsageStore.swift` (état) |
| Palette de couleurs | `Support/ColorStorage.swift` |

## Build

Le `.xcodeproj` est généré par XcodeGen depuis `project.yml`, et commité pour que l'ouverture
dans Xcode ne demande aucun outil. Après modification de `project.yml` :

```bash
xcodegen generate
xcodebuild -project ClaudeTray.xcodeproj -scheme ClaudeTray -configuration Debug build
```

Le projet doit compiler **sans aucun avertissement**, à une exception près, documentée : les
avertissements de dépréciation `SecKeychain` de `Services/KeychainAccessRevoker.swift`. Aucune API
moderne ne sait modifier la liste d'applications de confiance d'un item ; `SecItem*` lit et écrit
l'item, pas son ACL. Ajouter un nouvel avertissement ailleurs reste interdit.

Ajout d'un fichier source ou d'une ressource : `xcodegen generate` avant de compiler, sinon le
fichier n'existe pas pour Xcode et l'erreur ressemble à un problème de code (`cannot find X in scope`).

## Publier une version

1. Bump `MARKETING_VERSION` et `CURRENT_PROJECT_VERSION` dans `project.yml`, puis `xcodegen generate`.
2. Entrée en tête de `CHANGELOG.md` — c'est ce fichier qui sert de notes de release.
3. `./scripts/make-dmg.sh` : Release, signature Developer ID, DMG, notarisation, agrafage,
   vérification `spctl`. Compter quelques minutes de file d'attente chez Apple.
4. Extraire la seule section de la version — `CHANGELOG.md` entier ferait des notes de release
   illisibles :

   ```bash
   awk '/^## X\.Y /{f=1;next} /^## /{f=0} f' CHANGELOG.md > /tmp/notes.md
   gh release create vX.Y dist/ClaudeTray-X.Y.dmg --title "ClaudeTray X.Y" --notes-file /tmp/notes.md
   ```

5. Installer la nouvelle version localement : `cp -R build/DerivedData/Build/Products/Release/ClaudeTray.app /Applications/`
   après avoir tué l'instance en cours. La signature Developer ID change par rapport à un build de
   développement, donc macOS redemande l'accès au trousseau une fois.

**La release conditionne la vérification de version** : `UpdateChecker` lit `releases/latest`, donc
une version publiée sans release GitHub reste invisible pour les installations existantes. Le tag
doit être `vX.Y` — le préfixe `v` est retiré avant comparaison.

Pour l'agent : `notarytool submit --wait` dépasse souvent le délai d'un appel d'outil. Le lancer en
tâche de fond plutôt que de le relancer, sinon la soumission repart de zéro. `SKIP_NOTARIZE=1`
permet de construire d'abord le DMG signé, puis de notariser à part.

La signature expose le nom du compte développeur : `codesign -dv` sur le DMG affiche
`Developer ID Application: Pascal Tourres (…)`, quel que soit l'affichage TheUnnamedCompany dans
l'app et le README. Le masquer demanderait un compte Apple Developer d'organisation.

Le script échoue proprement s'il manque le certificat *Developer ID Application* ou le profil de
notarisation (`xcrun notarytool store-credentials claudetray …`). `SKIP_NOTARIZE=1` s'arrête après
le DMG signé, pour un essai local.

`dist/` et `build/` sont ignorés par git. Les captures du README vivent dans `docs/` :
`menubar.png` montre la barre avec le logo, `popover.png` le popover complet, réglages compris —
donc à regénérer dès qu'un réglage est ajouté, sinon la capture ment sur ce que l'app propose.

## Conventions

- **Commentaires de code et messages de commit en français.** Les termes techniques, noms d'API et
  chaînes d'erreur restent tels quels.
- **Documentation destinée aux utilisateurs en anglais** : `README.md`, `CHANGELOG.md`, notes de
  release, description du dépôt.
- **Interface : les cinq langues, jamais de chaîne en dur.** Voir la section Localisation.
- Le lien de soutien (`buymeacoffee.com/theunnamedcompany`) figure dans le README, dans
  `.github/FUNDING.yml` et, depuis la 1.2, en pied de popover — une ligne discrète en 10 pt gris,
  jamais une bannière ni une relance.
