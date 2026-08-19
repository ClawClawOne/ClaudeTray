import Foundation

/// Langue de l'interface. `system` suit les préférences de macOS ;
/// les autres valeurs forcent une langue quel que soit le réglage système.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case french
    case german
    case spanish
    case italian

    var id: String { rawValue }

    /// Nom affiché dans le sélecteur, dans la langue concernée.
    var nativeName: String {
        switch self {
        case .system: return "Système / System"
        case .english: return "English"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        case .italian: return "Italiano"
        }
    }

    /// Code ISO utilisé pour les formats de date et d'heure.
    var localeIdentifier: String {
        switch self {
        case .system: return Locale.current.identifier
        case .english: return "en_US"
        case .french: return "fr_FR"
        case .german: return "de_DE"
        case .spanish: return "es_ES"
        case .italian: return "it_IT"
        }
    }

    /// Langue effective : `system` est résolu contre les préférences de macOS,
    /// avec l'anglais en repli quand aucune langue prise en charge ne correspond.
    var resolved: AppLanguage {
        guard self == .system else { return self }
        for identifier in Locale.preferredLanguages {
            switch identifier.prefix(2) {
            case "fr": return .french
            case "de": return .german
            case "es": return .spanish
            case "it": return .italian
            case "en": return .english
            default: continue
            }
        }
        return .english
    }
}

/// Toutes les chaînes de l'interface, dans les cinq langues prises en charge.
///
/// Pas de fichiers `.lproj` : la langue doit pouvoir changer sans relancer l'app, ce que
/// `NSLocalizedString` ne permet pas sans manipuler les bundles à la main. Ici, chaque chaîne
/// est une propriété calculée — le compilateur garantit qu'aucune traduction ne manque.
struct Loc {
    let language: AppLanguage

    init(_ requested: AppLanguage) {
        self.language = requested.resolved
    }

    var locale: Locale { Locale(identifier: language.localeIdentifier) }

    /// Ordre des arguments : anglais, français, allemand, espagnol, italien.
    private func p(_ en: String, _ fr: String, _ de: String, _ es: String, _ it: String) -> String {
        switch language {
        case .english, .system: return en
        case .french: return fr
        case .german: return de
        case .spanish: return es
        case .italian: return it
        }
    }

    // MARK: - Réglages

    var settingsLanguage: String { p("Language", "Langue", "Sprache", "Idioma", "Lingua") }
    var settingsRefresh: String { p("Refresh", "Rafraîchissement", "Aktualisierung", "Actualización", "Aggiornamento") }
    var refreshNow: String { p("Refresh now", "Rafraîchir maintenant", "Jetzt aktualisieren", "Actualizar ahora", "Aggiorna ora") }
    var showLogo: String { p("Show Claude logo", "Afficher le logo Claude", "Claude-Logo anzeigen", "Mostrar el logotipo de Claude", "Mostra il logo di Claude") }
    var showAllWindows: String { p("Menu bar: show all windows", "Barre de menu : afficher toutes les fenêtres", "Menüleiste: alle Fenster anzeigen", "Barra de menús: mostrar todas las ventanas", "Barra dei menu: mostra tutte le finestre") }
    var singleMetric: String { p("Single metric", "Métrique unique", "Einzelne Kennzahl", "Métrica única", "Metrica singola") }
    var showRemaining: String { p("Show remaining instead of used", "Afficher le restant plutôt que le consommé", "Verbleibend statt verbraucht anzeigen", "Mostrar lo restante en vez de lo consumido", "Mostra il rimanente invece del consumato") }
    var notificationsSetting: String { p("Notifications at 80% and 95%", "Notifications à 80 % et 95 %", "Benachrichtigungen bei 80 % und 95 %", "Notificaciones al 80 % y 95 %", "Notifiche all'80 % e 95 %") }
    var launchAtLogin: String { p("Launch at login", "Lancer au démarrage", "Beim Anmelden starten", "Abrir al iniciar sesión", "Avvia all'accesso") }
    var edgeMargin: String { p("Edge margin", "Marge extérieure", "Außenabstand", "Margen exterior", "Margine esterno") }
    var spacing: String { p("Spacing", "Espacement", "Abstand", "Espaciado", "Spaziatura") }
    var percentColor: String { p("Percentage colour", "Couleur des pourcentages", "Farbe der Prozentwerte", "Color de los porcentajes", "Colore delle percentuali") }

    var intervalAuto: String { p("Auto", "Auto", "Auto", "Automático", "Auto") }
    var intervalOneHour: String { p("1 h", "1 h", "1 Std", "1 h", "1 h") }

    var metricFiveHour: String { p("5-hour window", "Fenêtre 5 h", "5-Stunden-Fenster", "Ventana de 5 h", "Finestra di 5 h") }
    var metricWeekly: String { p("Weekly", "Hebdomadaire", "Wöchentlich", "Semanal", "Settimanale") }
    var metricMostConstrained: String { p("Most constrained", "La plus contrainte", "Am stärksten ausgelastet", "La más restringida", "La più vincolata") }

    // MARK: - Couleurs

    func colorName(_ key: String) -> String {
        switch key {
        case "green": return p("Green", "Vert", "Grün", "Verde", "Verde")
        case "cyan": return p("Cyan", "Cyan", "Cyan", "Cian", "Ciano")
        case "blue": return p("Blue", "Bleu", "Blau", "Azul", "Blu")
        case "purple": return p("Purple", "Violet", "Violett", "Morado", "Viola")
        case "pink": return p("Pink", "Rose", "Rosa", "Rosa", "Rosa")
        case "yellow": return p("Yellow", "Jaune", "Gelb", "Amarillo", "Giallo")
        case "orange": return p("Claude orange", "Orange Claude", "Claude-Orange", "Naranja Claude", "Arancione Claude")
        default: return p("White", "Blanc", "Weiß", "Blanco", "Bianco")
        }
    }

    // MARK: - Fenêtres de quota

    func weeklyModel(_ model: String) -> String {
        p("Weekly \(model)", "Hebdo \(model)", "Wöchentlich \(model)", "Semanal \(model)", "Settimanale \(model)")
    }

    func resetIn(_ countdown: String) -> String {
        p("Resets in \(countdown)", "Reset dans \(countdown)", "Zurücksetzung in \(countdown)",
          "Se reinicia en \(countdown)", "Reset tra \(countdown)")
    }

    var resetUnknown: String {
        p("Reset not reported by the API", "Reset non communiqué par l'API", "Zurücksetzung von der API nicht gemeldet",
          "La API no informa del reinicio", "Reset non comunicato dall'API")
    }

    var resetImminent: String { p("resetting now", "reset imminent", "gleich", "inminente", "imminente") }

    var unitDay: String { p("d", "j", "T", "d", "g") }
    var unitHour: String { p("h", "h", "Std", "h", "h") }
    var unitMinute: String { p("min", "min", "Min", "min", "min") }
    var unitSecond: String { p("s", "s", "Sek", "s", "s") }

    // MARK: - Pied du popover

    var noData: String {
        p("No usage data yet.", "Aucune donnée d'usage pour l'instant.", "Noch keine Nutzungsdaten.",
          "Aún no hay datos de uso.", "Nessun dato di utilizzo per ora.")
    }

    func staleSince(_ duration: String) -> String {
        p("Data stale for \(duration).", "Données obsolètes depuis \(duration).", "Daten seit \(duration) veraltet.",
          "Datos obsoletos desde hace \(duration).", "Dati obsoleti da \(duration).")
    }

    var tokenLabel: String { p("Token:", "Token :", "Token:", "Token:", "Token:") }
    var tokenUnresolved: String { p("not resolved", "non résolu", "nicht gefunden", "sin resolver", "non risolto") }

    func lastRefresh(_ time: String) -> String {
        p("Last successful refresh: \(time)", "Dernier rafraîchissement réussi : \(time)",
          "Letzte erfolgreiche Aktualisierung: \(time)", "Última actualización correcta: \(time)",
          "Ultimo aggiornamento riuscito: \(time)")
    }

    var noRefreshYet: String {
        p("No successful refresh yet.", "Aucun rafraîchissement réussi.", "Noch keine erfolgreiche Aktualisierung.",
          "Ninguna actualización correcta.", "Nessun aggiornamento riuscito.")
    }

    var pollingPaused: String {
        p("Polling paused (sleep or locked session).", "Polling suspendu (veille ou session verrouillée).",
          "Abfrage pausiert (Ruhezustand oder gesperrte Sitzung).", "Sondeo en pausa (suspensión o sesión bloqueada).",
          "Interrogazione sospesa (stop o sessione bloccata).")
    }

    var pasteToken: String { p("Paste a manual token", "Coller un token manuel", "Token manuell einfügen", "Pegar un token manual", "Incolla un token manuale") }
    var hideToken: String { p("Hide the manual token", "Masquer le token manuel", "Token-Feld ausblenden", "Ocultar el token manual", "Nascondi il token manuale") }
    var clear: String { p("Clear", "Effacer", "Löschen", "Borrar", "Cancella") }
    var save: String { p("Save", "Enregistrer", "Sichern", "Guardar", "Salva") }
    var quit: String { p("Quit", "Quitter", "Beenden", "Salir", "Esci") }

    // MARK: - Mises à jour et soutien

    var settingCheckUpdates: String {
        p("Check for updates daily", "Vérifier les mises à jour chaque jour", "Täglich nach Updates suchen",
          "Buscar actualizaciones a diario", "Cerca aggiornamenti ogni giorno")
    }

    func updateAvailable(_ version: String) -> String {
        p("Version \(version) is available", "La version \(version) est disponible", "Version \(version) ist verfügbar",
          "La versión \(version) está disponible", "La versione \(version) è disponibile")
    }

    var supportProject: String {
        p("Buy me a coffee", "Offrez-moi un café", "Spendier mir einen Kaffee",
          "Invítame a un café", "Offrimi un caffè")
    }

    var tokenHint: String {
        p("From “claude setup-token”. Stored 0600 in Application Support.",
          "Issu de « claude setup-token ». Stocké en 0600 dans Application Support.",
          "Aus „claude setup-token“. Mit 0600 in Application Support gespeichert.",
          "Generado con «claude setup-token». Guardado con 0600 en Application Support.",
          "Da «claude setup-token». Salvato con 0600 in Application Support.")
    }

    // MARK: - Sources de token

    var sourceManual: String { p("Manual token", "Token manuel", "Manueller Token", "Token manual", "Token manuale") }
    var sourceKeychain: String { p("macOS keychain", "Trousseau macOS", "macOS-Schlüsselbund", "Llavero de macOS", "Portachiavi macOS") }
    var sourceFile: String { "~/.claude/.credentials.json" }

    // MARK: - Erreurs

    var errorNoToken: String {
        p("No token found. ClaudeTray needs Claude Code installed and logged in: run “claude” in Terminal, then “/login”. Otherwise, paste a token from “claude setup-token” here.",
          "Aucun token trouvé. ClaudeTray a besoin de Claude Code installé et connecté : lance « claude » dans le Terminal puis « /login ». Sinon, colle ici un token issu de « claude setup-token ».",
          "Kein Token gefunden. ClaudeTray benötigt ein installiertes und angemeldetes Claude Code: „claude“ im Terminal starten, dann „/login“. Alternativ hier einen Token aus „claude setup-token“ einfügen.",
          "No se encontró ningún token. ClaudeTray necesita Claude Code instalado y con sesión iniciada: ejecuta «claude» en el Terminal y luego «/login». Si no, pega aquí un token de «claude setup-token».",
          "Nessun token trovato. ClaudeTray richiede Claude Code installato e con accesso effettuato: esegui «claude» nel Terminale, poi «/login». In alternativa, incolla qui un token da «claude setup-token».")
    }

    func errorKeychainDenied(_ detail: String) -> String {
        p("Keychain access denied (\(detail)). Allow ClaudeTray, or paste a manual token.",
          "Accès au trousseau refusé (\(detail)). Autorise ClaudeTray, ou colle un token manuel.",
          "Schlüsselbund-Zugriff verweigert (\(detail)). ClaudeTray erlauben oder Token manuell einfügen.",
          "Acceso al llavero denegado (\(detail)). Autoriza ClaudeTray o pega un token manual.",
          "Accesso al portachiavi negato (\(detail)). Autorizza ClaudeTray o incolla un token manuale.")
    }

    func errorMalformedToken(_ origin: String) -> String {
        p("Unreadable token from \(origin): unexpected JSON structure.",
          "Token illisible depuis \(origin) : structure JSON inattendue.",
          "Token aus \(origin) nicht lesbar: unerwartete JSON-Struktur.",
          "Token ilegible desde \(origin): estructura JSON inesperada.",
          "Token illeggibile da \(origin): struttura JSON inattesa.")
    }

    var errorUnauthorized: String {
        p("401 — token rejected or expired. Run Claude Code once to refresh it, or paste a manual token.",
          "401 — token refusé ou expiré. Lance Claude Code pour le rafraîchir, ou colle un token manuel.",
          "401 — Token abgelehnt oder abgelaufen. Claude Code einmal starten oder Token manuell einfügen.",
          "401 — token rechazado o caducado. Ejecuta Claude Code para renovarlo o pega un token manual.",
          "401 — token rifiutato o scaduto. Avvia Claude Code per rinnovarlo o incolla un token manuale.")
    }

    func errorRateLimited(_ seconds: Int?) -> String {
        guard let seconds else {
            return p("429 — too many requests. Automatically slowing down.",
                     "429 — trop de requêtes. Ralentissement automatique en cours.",
                     "429 — zu viele Anfragen. Automatische Drosselung läuft.",
                     "429 — demasiadas solicitudes. Reduciendo la frecuencia automáticamente.",
                     "429 — troppe richieste. Rallentamento automatico in corso.")
        }
        return p("429 — too many requests. Retrying in \(seconds) s.",
                 "429 — trop de requêtes. Nouvelle tentative dans \(seconds) s.",
                 "429 — zu viele Anfragen. Nächster Versuch in \(seconds) s.",
                 "429 — demasiadas solicitudes. Nuevo intento en \(seconds) s.",
                 "429 — troppe richieste. Nuovo tentativo tra \(seconds) s.")
    }

    var errorUnexpectedSchema: String {
        p("Unexpected response format: the endpoint has probably changed. See “Under the hood” in the README.",
          "Réponse au format inattendu : l'endpoint a probablement changé. Voir « Sous le capot » dans le README.",
          "Unerwartetes Antwortformat: der Endpunkt hat sich vermutlich geändert. Siehe „Under the hood“ in der README.",
          "Formato de respuesta inesperado: el endpoint probablemente ha cambiado. Consulta «Under the hood» en el README.",
          "Formato di risposta inatteso: l'endpoint è probabilmente cambiato. Vedi «Under the hood» nel README.")
    }

    func errorHTTP(_ status: Int) -> String {
        p("HTTP error \(status) from api.anthropic.com.",
          "Erreur HTTP \(status) depuis api.anthropic.com.",
          "HTTP-Fehler \(status) von api.anthropic.com.",
          "Error HTTP \(status) desde api.anthropic.com.",
          "Errore HTTP \(status) da api.anthropic.com.")
    }

    func errorNetwork(_ detail: String) -> String {
        p("Network unavailable: \(detail)", "Réseau indisponible : \(detail)", "Netzwerk nicht verfügbar: \(detail)",
          "Red no disponible: \(detail)", "Rete non disponibile: \(detail)")
    }

    func errorLaunchAtLogin(_ detail: String) -> String {
        p("Launch at login: \(detail)", "Lancement au démarrage : \(detail)", "Beim Anmelden starten: \(detail)",
          "Abrir al iniciar sesión: \(detail)", "Avvio all'accesso: \(detail)")
    }

    func errorManualTokenWrite(_ detail: String) -> String {
        p("Could not write the manual token: \(detail)",
          "Écriture du token manuel impossible : \(detail)",
          "Manueller Token konnte nicht geschrieben werden: \(detail)",
          "No se pudo escribir el token manual: \(detail)",
          "Impossibile scrivere il token manuale: \(detail)")
    }

    // MARK: - Notifications

    func notificationTitle(_ window: String, _ threshold: Int) -> String {
        p("\(window) at \(threshold)%", "\(window) à \(threshold) %", "\(window) bei \(threshold) %",
          "\(window) al \(threshold) %", "\(window) al \(threshold) %")
    }

    func notificationBody(percent: Int, reset: String?) -> String {
        guard let reset else {
            return p("\(percent)% used.", "\(percent) % consommé.", "\(percent) % verbraucht.",
                     "\(percent) % consumido.", "\(percent) % consumato.")
        }
        return p("\(percent)% used. Resets \(reset).", "\(percent) % consommé. Reset \(reset).",
                 "\(percent) % verbraucht. Zurücksetzung \(reset).", "\(percent) % consumido. Se reinicia \(reset).",
                 "\(percent) % consumato. Reset \(reset).")
    }
}
