import Foundation

/// The SDK's own few words, in the support page's languages (sdks/protocol, section 6).
public struct SupportWords: Equatable, Sendable {
    public let loading: String
    public let failed: String
    public let retry: String
    public let help: String
    public let back: String
    public let unread: String

    /// The words for `language` (`es`, `pt-BR`…), or the device's language when none is given; English otherwise.
    public static func forLanguage(_ language: String?) -> SupportWords {
        let preferred = language ?? Locale.preferredLanguages.first ?? "en"
        let code = preferred.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? "en"
        return all[code] ?? all["en"]!
    }

    static let all: [String: SupportWords] = [
        "en": SupportWords(loading: "Loading support…", failed: "Support couldn't open.", retry: "Try again", help: "Help", back: "Back", unread: "unread"),
        "es": SupportWords(loading: "Cargando soporte…", failed: "No se pudo abrir el soporte.", retry: "Reintentar", help: "Ayuda", back: "Volver", unread: "sin leer"),
        "fr": SupportWords(loading: "Chargement du support…", failed: "Le support n'a pas pu s'ouvrir.", retry: "Réessayer", help: "Aide", back: "Retour", unread: "non lus"),
        "de": SupportWords(loading: "Support wird geladen…", failed: "Der Support konnte nicht geöffnet werden.", retry: "Erneut versuchen", help: "Hilfe", back: "Zurück", unread: "ungelesen"),
        "pt": SupportWords(loading: "Carregando o suporte…", failed: "Não foi possível abrir o suporte.", retry: "Tentar de novo", help: "Ajuda", back: "Voltar", unread: "não lidas"),
    ]
}
