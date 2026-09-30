import Testing

@testable import HouseholdHub

/// Sprint 24 (item 4): the ten contextual tips are plain, static declarations, so there's little pure logic to test.
/// This checks every tip has what a tip needs to be useful — a stable id, a title and a message — and that the ids
/// are unique, so two tips can never collide in TipKit's datastore.
struct TutorialTipsTests {
    @Test func everyTipHasANonEmptyIDTitleAndMessage() {
        #expect(TutorialTipCatalog.all.count == 10)
        for tip in TutorialTipCatalog.all {
            #expect(!tip.id.isEmpty, "a tip has an empty id")
            #expect(!String(describing: tip.title).isEmpty, "\(tip.id) has an empty title")
            #expect(tip.message != nil, "\(tip.id) has no message")
            if let message = tip.message {
                #expect(!String(describing: message).isEmpty, "\(tip.id) has an empty message")
            }
        }
    }

    @Test func everyTipHasAUniqueID() {
        let ids = TutorialTipCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyIDIsNamespacedUnderTip() {
        for tip in TutorialTipCatalog.all {
            #expect(tip.id.hasPrefix("tip."), "\(tip.id) isn't namespaced")
        }
    }
}
