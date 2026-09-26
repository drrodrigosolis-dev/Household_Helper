---
name: household-migration-audit
description: Audit SwiftData schema changes for safe migration — VersionedSchema, SchemaMigrationPlan, no destructive migration, backup compatibility. Use whenever a @Model, stored property, relationship, or Codable persisted value changes.
---

# household-migration-audit

1. Diff every `@Model` type and persisted Codable value (Money, RecurrenceRule, ColorToken, enums) against the
   last committed `VersionedSchema`.
2. Any stored change after the first schema ships requires a new `VersionedSchema` and a `MigrationStage`
   (lightweight if possible, custom otherwise). No destructive migration, ever (§5.3).
3. Renamed properties use `@Attribute(originalName:)`; enum raw values are never reused or renumbered.
4. Write a migration test: build a store with the previous schema (in a temp directory), migrate, assert data
   and relationships survived.
5. Backup: if the change affects the §26 DTO, bump `schemaVersion`, keep a decoder for the old version, and add a
   restore test from an old-version fixture.
6. Record the decision in `docs/research/apple-api-decisions.md` if it relied on version-specific SwiftData
   behavior. Report risks explicitly.
