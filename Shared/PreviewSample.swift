struct PreviewSample {
    private(set) var text = Self.sample(for: "en-GB")
    private(set) var isCustom = false

    mutating func edit(_ text: String) {
        self.text = text
        isCustom = true
    }

    mutating func follow(_ locale: String) {
        if !isCustom { reset(locale) }
    }

    mutating func reset(_ locale: String) {
        text = Self.sample(for: locale)
        isCustom = false
    }

    static func sample(for locale: String) -> String {
        switch locale.prefix(2).lowercased() {
        case "de": return "Guten Tag! So klingt Phonon auf Deutsch."
        case "es": return "¡Hola! Así suena Phonon en español."
        case "fr": return "Bonjour ! Voici un aperçu de Phonon en français."
        case "pt": return "Olá! Este é um exemplo da voz do Phonon em português."
        default: return "Hello! This is how Phonon sounds in English."
        }
    }
}
