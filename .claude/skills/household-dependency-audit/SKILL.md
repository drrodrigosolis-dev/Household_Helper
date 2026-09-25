---
name: household-dependency-audit
description: Evaluate a proposed third-party package, build tool, or service against Household Hub's zero-dependency, zero-cost policy. Use before adding anything to project.yml packages, Package.swift, CI tooling, or any external service.
---

# household-dependency-audit

Default answer is no (§3.2). A proposal proceeds only if all hold:

1. **Need:** name the concrete problem and why the Apple-native option (§17 matrix) is insufficient, with evidence.
2. **Cost:** free forever for this use; no account, API key, quota, or telemetry; does not move a CORE feature to
   OPTIONAL/DEFERRED (§11.3).
3. **License:** compatible permissive license, recorded.
4. **Health:** recent releases, maintained, issue responsiveness, supports iOS 26 / Swift 6 strict concurrency.
5. **Footprint:** transitive dependencies listed; binary size and privacy impact noted.
6. **Exit strategy:** how to remove or replace it.

Record the result in `docs/research/dependency-decisions.md`. Adding a package or install step needs the owner's
confirmation (the guard hook will ask); present this record when asking.
