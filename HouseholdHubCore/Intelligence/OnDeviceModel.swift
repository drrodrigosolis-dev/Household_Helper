import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Apple's on-device Foundation Models (spec §12.1), behind an availability check. Nothing here can reach SwiftData:
/// it only turns text into suggestions that the validators then filter. When the model is unavailable every call
/// returns nil and the app continues on its deterministic paths (§12.5); there is no other model to fall back to.
public enum OnDeviceModel {
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        #endif
        return false
    }

    /// Structured Quick Add proposal for `text`, choosing categories only from `categoryNames`.
    public static func suggestQuickAdd(_ text: String, categoryNames: [String]) async -> QuickAddSuggestion? {
        #if canImport(FoundationModels)
            guard isAvailable else { return nil }
            let instructions = """
                You read one short note about a household expense or income and fill in fields. \
                Use only information in the note. Leave a field empty when the note does not say it.
                """
            let prompt = """
                Note: \(text)
                Category names you may choose from: \(categoryNames.joined(separator: ", "))
                """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let guess = try await session.respond(to: prompt, generating: QuickAddGuess.self).content
                return QuickAddSuggestion(
                    amount: Decimal(string: guess.amount, locale: Locale(identifier: "en_US_POSIX")),
                    type: guess.kind.isEmpty ? nil : guess.kind,
                    categoryName: guess.category.isEmpty ? nil : guess.category,
                    dayOffset: guess.dayOffset == 0 ? nil : guess.dayOffset,
                    description: guess.summary.isEmpty ? nil : guess.summary)
            } catch {
                return nil
            }
        #else
            return nil
        #endif
    }

    /// A short narrative written only from `facts`.
    public static func narrate(_ facts: AnalyticsFacts) async -> String? {
        #if canImport(FoundationModels)
            guard isAvailable else { return nil }
            let instructions = """
                You write two or three plain sentences summarising a household's spending for a period. \
                Use only the figures given, exactly as written. Do not give advice or invent numbers.
                """
            do {
                let session = LanguageModelSession(instructions: instructions)
                return try await session.respond(to: facts.prompt).content
            } catch {
                return nil
            }
        #else
            return nil
        #endif
    }
}

#if canImport(FoundationModels)
    @Generable
    struct QuickAddGuess {
        @Guide(description: "The amount as a plain number such as 47.50, or empty")
        var amount: String
        @Guide(description: "expense or income, or empty")
        var kind: String
        @Guide(description: "Exactly one of the given category names, or empty")
        var category: String
        @Guide(description: "Days from today the note refers to: 0 today, -1 yesterday")
        var dayOffset: Int
        @Guide(description: "A few words saying what it was, or empty")
        var summary: String
    }
#endif
