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
- Default view shows only successful builds; toggle to show all statuses.

## Real Bitrise API mode
The app reads configuration from scheme environment variables:
- `BITRISE_API_TOKEN`: your Bitrise Personal Access Token (required for real mode)
- `BITRISE_APP_SLUG`: the Bitrise app slug to query
- `BITRISE_WORKFLOW_ID`: workflow id to filter builds (optional)

If `BITRISE_API_TOKEN` is missing, the app shows an error when refreshing.

## Mock mode scheme
There is a dedicated scheme `BitriseWatcher-Mock` which sets:
- `BITRISE_WATCHER_USE_MOCKS=1`
- mock `BITRISE_APP_SLUG` / `BITRISE_WORKFLOW_ID`
