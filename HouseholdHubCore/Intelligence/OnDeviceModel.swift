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
                Use only information in the note. Leave a field empty when the note does not say it. \
                Never guess an amount or a date the note does not state.
                """
            let prompt = """
                Note: \(text)
                Category names you may choose from: \(categoryNames.joined(separator: ", "))
                """
            do {
                let session = LanguageModelSession(instructions: instructions)
                let guess = try await session.respond(to: prompt, generating: QuickAddGuess.self).content
                return QuickAddSuggestion(
                    amount: guess.amount.isEmpty ? nil : guess.amount,
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

    /// A short narrative written only from `facts`, with figures as `facts` placeholders; `NarrativeValidator`
    /// checks it and fills them in.
    /// - Parameter language: the language to write in, named in English ("Spanish"), so the summary matches the app
    ///   (Sprint 16). If the model can't write it, it fails and the deterministic summary shows instead.
    public static func narrate(_ facts: AnalyticsFacts, language: String = "English") async -> String? {
        #if canImport(FoundationModels)
            guard isAvailable else { return nil }
            let instructions = """
                You write two or three plain sentences summarising a household's spending for a period. \
                Each figure is given as a placeholder in braces, such as {income}. Write figures only by copying \
                those placeholders exactly; never write a digit or a number in words. Do not give advice. \
                Write in \(language).
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

/// The on-device model behind the Siri intents' `SiriDraftModel` seam (Sprint 25). It only turns the dictated sentence
/// into a guess; `SiriRefinement` validates it and falls back to the grammar when it throws, and the intent asks the
/// person before anything is saved.
public struct OnDeviceSiriModel: SiriDraftModel {
    public enum Failure: Error, Equatable, Sendable {
        case unavailable
    }

    public init() {}

    public func transaction(_ text: String, categoryNames: [String]) async throws -> SiriTransactionGuess {
        #if canImport(FoundationModels)
            guard OnDeviceModel.isAvailable else { throw Failure.unavailable }
            let instructions = """
                You read one spoken sentence about a household expense or income and fill in fields. \
                Use only information in the sentence. Leave a field empty when the sentence does not say it. \
                Never guess an amount or a day the sentence does not state.
                """
            let prompt = """
                Sentence: \(text)
                Category names you may choose from: \(categoryNames.joined(separator: ", "))
                """
            let session = LanguageModelSession(instructions: instructions)
            let guess = try await session.respond(to: prompt, generating: SiriTransactionGeneration.self).content
            return SiriTransactionGuess(
                amount: guess.amount, kind: guess.kind, merchant: guess.merchant, datePhrase: guess.datePhrase,
                category: guess.category)
        #else
            throw Failure.unavailable
        #endif
    }

    public func wishlist(_ text: String) async throws -> SiriWishlistGuess {
        #if canImport(FoundationModels)
            guard OnDeviceModel.isAvailable else { throw Failure.unavailable }
            let instructions = """
                You read one spoken sentence about something a household wants to buy and fill in fields. \
                Use only information in the sentence. Leave the price empty when the sentence does not say one.
                """
            let prompt = "Sentence: \(text)"
            let session = LanguageModelSession(instructions: instructions)
            let guess = try await session.respond(to: prompt, generating: SiriWishlistGeneration.self).content
            return SiriWishlistGuess(name: guess.name, price: guess.price)
        #else
            throw Failure.unavailable
        #endif
    }
}

#if canImport(FoundationModels)
    @Generable
    struct SiriTransactionGeneration {
        @Guide(description: "The amount as a plain number copied from the sentence, such as 40 or 9.50, or empty")
        var amount: String
        @Guide(description: "expense or income, or empty")
        var kind: String
        @Guide(description: "The shop or payee in the sentence's own words, such as Safeway, or empty")
        var merchant: String
        @Guide(description: "The word in the sentence that names the day, such as yesterday or monday, or empty")
        var datePhrase: String
        @Guide(description: "Exactly one of the given category names, or empty")
        var category: String
    }

    @Generable
    struct SiriWishlistGeneration {
        @Guide(description: "What the household wants, in the sentence's own words, without the price")
        var name: String
        @Guide(description: "The price as a plain number copied from the sentence, such as 149.99, or empty")
        var price: String
    }
#endif

#if canImport(FoundationModels)
    @Generable
    struct QuickAddGuess {
        @Guide(description: "The amount as a plain number such as 47.50, or empty")
        var amount: String
        @Guide(description: "expense or income, or empty")
        var kind: String
        @Guide(description: "Exactly one of the given category names, or empty")
        var category: String
        @Guide(description: "Days from today the note refers to: 0 today or not stated, -1 yesterday")
        var dayOffset: Int
        @Guide(description: "A short description using the note's own words, without the amount, or empty")
        var summary: String
    }
#endif
