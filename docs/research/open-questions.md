# Open questions

- **GitHub default branch** is `claude/friendly-cori-6ymhxr`, not `main`. Only the owner can change it
  (Settings → Branches). Harmless for the `build/v1 → main` PR, but `main` should be the default.
- **macos-latest image and Xcode 26:** whether the image in use ships Xcode 26 with an iOS 26 simulator runtime is
  confirmed only by the first verify run. If not, the fix is a different `runs-on` image or a runtime download.
- **Bundle identifier prefix** is a placeholder (`dev.householdhub`, `project.yml` `BUNDLE_ID_PREFIX`). Change it
  before any physical-device install under a Personal Team.
