# Prompt pour Claude Code

Développe une app macOS en barre de menu, SwiftUI natif, qui affiche mon usage de quota Claude en temps réel. Va jusqu'au bout d'une traite : projet complet, compilable, README inclus. Si un point te bloque vraiment, pose-moi la question ; sinon tranche toi-même et documente ton choix dans le README.

## Objectif

Trois informations, visibles sans ouvrir de terminal :
1. Le temps restant avant le reset de la fenêtre glissante de 5 h (compte à rebours).
2. Le % de quota consommé sur cette fenêtre de 5 h.
3. Le % de quota consommé sur la fenêtre hebdomadaire, avec son propre compte à rebours.

## Contexte technique — déjà vérifié, ne le redécouvre pas

La source de données est l'endpoint OAuth non documenté qu'utilise `/usage` dans Claude Code :

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <access_token>
anthropic-beta: oauth-2025-04-20
```

Le header `anthropic-beta` est obligatoire : sans lui, l'API répond 401. C'est un abonnement Max, pas une clé API à la consommation — n'introduis nulle part `ANTHROPIC_API_KEY`, elle ne fonctionnerait pas sur cet endpoint.

Forme de la réponse (tous les champs peuvent être `null` ou absents) :

```json
{
  "five_hour":        { "utilization": 35.0, "resets_at": "2026-02-06T22:00:00+00:00" },
  "seven_day":        { "utilization": 14.0, "resets_at": "2026-02-12T20:00:00+00:00" },
  "seven_day_sonnet": { "utilization": 39.0, "resets_at": "2026-02-09T14:00:00+00:00" },
  "seven_day_opus":   null,
  "extra_usage":      { "is_enabled": true, "monthly_limit": 100000, "used_credits": 0.0, "utilization": null }
}
```

- `utilization` est attendu sur une échelle 0–100. **Première tâche : lance le curl ci-dessous, regarde la valeur réelle, et si elle sort en 0–1 adapte la normalisation avant d'écrire les vues.** Centralise cette conversion dans un seul endroit du code.
- `resets_at` est en ISO 8601, tantôt sans fraction de seconde, tantôt avec 6 décimales (`...T07:00:00.528743+00:00`). Le décodeur de dates doit gérer les deux, sinon il casse aléatoirement.

```bash
security find-generic-password -s "Claude Code-credentials" -w \
  | jq -r '.claudeAiOauth.accessToken' \
  | xargs -I{} curl -s -H "Authorization: Bearer {}" \
      -H "anthropic-beta: oauth-2025-04-20" \
      https://api.anthropic.com/api/oauth/usage | jq
```

### Token

Vérifié sur ma machine : le token vit dans le **trousseau macOS**, entrée générique de service `Claude Code-credentials`, dont le contenu est le JSON `{ "claudeAiOauth": { "accessToken": "...", "expiresAt": ..., "refreshToken": "..." } }`. C'est la source à implémenter en priorité (via `SecItemCopyMatching`, `kSecClassGenericPassword`).

Implémente quand même cette chaîne de résolution, dans cet ordre :
1. Token manuel collé par l'utilisateur dans l'app, stocké en `~/Library/Application Support/<AppName>/token` avec permissions 0600. Il proviendra de `claude setup-token` (validité un an).
2. Le trousseau ci-dessus.
3. `~/.claude/.credentials.json`, même structure JSON. Respecte `$CLAUDE_CONFIG_DIR` s'il est défini.

Le token du trousseau expire en ~1 h et Claude Code le rafraîchit tout seul : relis-le à chaque appel réseau, ne le mets jamais en cache en mémoire.

**Friction connue à traiter dès le départ** : macOS lie l'autorisation d'accès au trousseau à la signature du binaire, donc chaque rebuild en signature ad-hoc redéclenche la boîte de dialogue. Configure le projet en signature automatique, et rends le token manuel (source 1) facilement accessible dans l'UI comme échappatoire — un champ visible, pas caché dans un sous-menu.

## Contraintes non négociables

- **Rate limiting.** Cet endpoint renvoie des 429 persistants s'il est sollicité trop souvent. Poll toutes les 90 s quand la fenêtre 5 h est entamée, 7 min sinon, backoff exponentiel plafonné à 30 min après un échec, et respect de `Retry-After` s'il est présent. Le compte à rebours, lui, s'anime localement à 1 s à partir de `resets_at` — sans appel réseau. Suspends le polling quand la session est verrouillée ou en veille (`NSWorkspace.didWake` / `sessionDidResignActive`).
- **Endpoint non documenté.** S'il change de forme ou de header beta, l'app doit dire clairement ce qui a échoué — 401, 429, schéma inattendu, réseau — au lieu d'afficher 0 % ou de planter. Garde les dernières données valides à l'écran avec un marqueur « obsolète depuis X ».
- **N'invente pas de reset.** Affiche uniquement ce que `resets_at` renvoie. Ne calcule pas toi-même « jeudi 20 h » ni « dans 7 jours » : le comportement réel de la fenêtre hebdo est instable et une prédiction fausse est pire que pas de prédiction.
- **Zéro télémétrie.** Une seule requête sortante, vers `api.anthropic.com`. Rien d'autre, aucune dépendance externe.
- **Pas de sandbox** (lecture de `~/.claude` et du trousseau), `LSUIElement = true` (pas d'icône Dock), entitlement client réseau activé.

## Interface

- **Barre de menu** : un pourcentage compact, avec un réglage pour choisir la métrique affichée entre « fenêtre 5 h », « hebdo » et « la plus contrainte des deux ». Option pour afficher le restant plutôt que le consommé. Passage en orange à 80 %, rouge à 95 %, indicateur discret quand les données sont périmées.
- **Popover** (`MenuBarExtra` en `.menuBarExtraStyle(.window)`) : une barre de progression par fenêtre — 5 h, hebdo global, hebdo Sonnet si non nul — chacune avec son % et son compte à rebours. Masque proprement les fenêtres que l'API renvoie à `null`, ne laisse pas de lignes vides.
- **Pied du popover** : source du token utilisée, heure du dernier rafraîchissement réussi, message d'erreur lisible le cas échéant, bouton Rafraîchir, champ pour coller un token manuel, Quitter.
- **Notifications locales** à 80 % et 95 % de chaque fenêtre, une seule fois par fenêtre, ré-armées au reset. Désactivables.
- Lancement au démarrage via `SMAppService`, activable depuis le popover.

## Livrable

Projet Xcode qui compile et se lance, macOS 14+, Swift 5.9+, SwiftUI uniquement, zéro dépendance. Sépare nettement le réseau, la résolution du token, le modèle observable et les vues. Ajoute un `README.md` couvrant : ouverture dans Xcode, réglages de signature, la demande d'autorisation du trousseau au premier lancement, ce qu'il faut modifier le jour où le header beta change, et les décisions que tu as prises seul.

Quand c'est fini, dis-moi précisément quoi cliquer dans Xcode pour lancer l'app la première fois.
