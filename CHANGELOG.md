# Journal des modifications

## 1.0 — 18 août 2026

Première version.

### Fonctionnalités

- Barre de menu : logo Claude monochrome (masquable) et une colonne par fenêtre de quota —
  `5H`, `WEEK`, plus une colonne par modèle limité (`FABLE`…). Intitulé en capitales au-dessus,
  pourcentage consommé en dessous, aligné à gauche.
- Popover : une barre de progression par fenêtre avec son pourcentage et son compte à rebours,
  source du token utilisée, heure du dernier rafraîchissement réussi, message d'erreur lisible,
  bouton Rafraîchir, champ de token manuel, Quitter.
- Notifications locales à 80 % et 95 % de chaque fenêtre, une seule fois par fenêtre,
  ré-armées au reset, désactivables.
- Lancement au démarrage via `SMAppService`.

### Réglages

- Cadence de rafraîchissement : Auto, 1 min, 5 min, 15 min, 30 min, 1 h.
- Affichage du logo Claude.
- Une ou toutes les fenêtres dans la barre de menu ; en mode fenêtre unique, choix entre
  5 h, hebdomadaire et la plus contrainte des deux.
- Consommé ou restant.
- Couleur des pourcentages : huit pastilles.
- Espacement entre éléments (2–24 pt) et marge extérieure (0–24 pt).

### Robustesse

- Trois sources de token, dans l'ordre : fichier manuel, trousseau macOS, `.credentials.json`.
- Backoff exponentiel plafonné à 30 min, `Retry-After` respecté.
- Polling suspendu en veille et session verrouillée, repris au réveil.
- Dernier instantané valide conservé en cas d'erreur, avec marqueur d'obsolescence.
