import CoreData
import SwiftData
import Testing

@testable import HouseholdHubCore

/// Installed schemas must never change: SchemaV1 (`063a510`), SchemaV2 (`fd7e67e`) and SchemaV3 (`8a9ec36`) are on
/// the owner's iPhone, and SwiftData finds an installed store's version by these hashes. Any edit to a frozen model
/// (a stored property, its type or an attribute) changes its hash and fails here; make a new schema version instead.
/// The values were read on the Mac from the installed commits (L-020 step 5, `docs/coordination/TO-CLOUD.md`).
struct FrozenSchemaTests {
    private static let v1: [String: String] = [
        "Account": "z8vYhvnjK/te4y7y6DljMmwO+2iy1UuwpSEpB6yfsqE=",
        "AppSettings": "PclbrgFUgnyPFx/XBhB/qKu92jpbLQm1COGAXlhf8DA=",
        "BoardColumn": "otW/nUsNm6JmixgMPaSfXzQKcN4TpRQPPUGsn7jnXCc=",
        "CategoryBudget": "VAEI6gouN4/Rxh1sazObIrp0WmXZkaJGB1U2nLhNQ+A=",
        "CategoryRecord": "cUsNCAgPc2gpLihb3KPSdaNKvFO7/B4U9Vl+JpBMpUw=",
        "Merchant": "s6+cFd3vZXSEfg7LVPwvIgyni9MzWu0zbh7rFZUjNzU=",
        "RecurringTransaction": "oijWj8kd4Qliu8X7ya4opWf6YHpcszEX9uqplqLYJdA=",
        "SavingsGoal": "mUZ5lA3rraIbpy7Wa46GGYVKa+Y0V370fRnsYN0UATY=",
        "SubtaskItem": "vZQ3n0NYJGO8BxsXX4uo3anzMtE0fKjDyV46vRtmHnU=",
        "TaskItem": "zSCRBvZul4FQCWPnYOzgXEGlpyDbzbi73NGZo+Dhulo=",
        "TransactionRecord": "9eg/co5II3NEWXB1AlD8Tjiu7K1d4lP9xi5cCoyiE20=",
        "WishlistItem": "bPgBJmmAIe2iJw9B3LFaHmdIJSBZZgJ+vxJH74SqYPo=",
    ]

    /// SchemaV2 changed only `TransactionRecord` (refunds).
    private static let v2 = v1.merging(["TransactionRecord": "2g9ao8KCDDqQBAa3ERmZEHquayXhZfIjTQzbqhK+Nm0="]) { $1 }

    /// SchemaV3 changed only `RecurringTransaction` (its kind).
    private static let v3 = v2.merging(["RecurringTransaction": "Ah+kRpqWLOcB/TVzas/mI6QzL9RoRU2wsiRDA2BS7M4="]) { $1 }

    private func hashes(_ models: [any PersistentModel.Type]) throws -> [String: String] {
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: models))
        return Dictionary(
            uniqueKeysWithValues: model.entities.compactMap { entity in
                entity.name.map { ($0, entity.versionHash.base64EncodedString()) }
            })
    }

    @Test func schemaV1IsAsInstalled() throws {
        #expect(try hashes(SchemaV1.models) == Self.v1)
    }

    @Test func schemaV2IsAsInstalled() throws {
        #expect(try hashes(SchemaV2.models) == Self.v2)
    }

    @Test func schemaV3IsAsInstalled() throws {
        #expect(try hashes(SchemaV3.models) == Self.v3)
    }
}
