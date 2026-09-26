# Config

XcodeGen writes the targets' Info.plist files here from the `info:` blocks in `project.yml` (keys that
`INFOPLIST_KEY_*` build settings can't express: the URL scheme, the App Group key, the widget's `NSExtension`).
They are generated, so they are git-ignored; edit `project.yml` instead.
