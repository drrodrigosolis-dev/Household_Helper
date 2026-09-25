# Household Helper

A SwiftUI iOS app.

## Requirements

- macOS with Xcode 16+ (this project cannot be built or run on Linux/CI containers — Xcode's iOS toolchain doesn't exist there)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Why XcodeGen instead of a committed `.xcodeproj`

The `.xcodeproj` file is generated from `project.yml` and is git-ignored. This
avoids the constant merge-conflict noise `.pbxproj` files cause and keeps the
project definition (targets, settings, dependencies) readable and diffable.

## Getting started

```bash
git clone <this repo>
cd Household_Helper
xcodegen generate
open HouseholdHelper.xcodeproj
```

Then build and run the `HouseholdHelper` scheme on a simulator or device from
Xcode.

Whenever you add/remove source files or change target settings, edit
`project.yml` and re-run `xcodegen generate` (do this after every `git pull`
that touches `project.yml` too).

## Project layout

```
project.yml                          # XcodeGen spec (source of truth for the Xcode project)
Sources/HouseholdHelper/
  HouseholdHelperApp.swift           # @main App entry point
  Views/                             # SwiftUI views
  Models/                            # Data models
  Resources/Assets.xcassets/         # App icon, colors, images
  Info.plist
Tests/HouseholdHelperTests/          # Unit tests
.github/workflows/ios.yml            # CI: generates project, builds, tests
```

## CI

`.github/workflows/ios.yml` runs on `macos-15` GitHub-hosted runners (the only
place this project actually builds), regenerating the Xcode project with
XcodeGen and running `xcodebuild build`/`test` against an iPhone 16 simulator.
