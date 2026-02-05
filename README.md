# bitrise-watcher

Simple macOS app scaffolded with XcodeGen.

## Prerequisites
- Xcode (macOS 26 SDK)
- XcodeGen (`brew install xcodegen`)

## Generate the Xcode project
```sh
make generate
```

Then open `BitriseWatcher.xcodeproj` and run the `BitriseWatcher` scheme.

## What it does (for now)
- Shows a mocked list of Bitrise builds for a mocked `appSlug` + `workflowID`.
- Has a `Refresh` button that re-fetches mocked data (with a short delay) and updates the list.
