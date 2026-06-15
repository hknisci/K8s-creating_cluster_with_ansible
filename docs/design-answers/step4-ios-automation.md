# Step 4.2 — iOS Build Lifecycle Automation (fastlane)

## Problem

iOS builds involve: code signing, building, testing, archiving, App Store submission.
Manual process is slow and error-prone.

## Solution: fastlane Pipeline

```
git push
    │
    ▼
GitHub Actions / Jenkins triggers
    │
    ▼
fastlane lanes:
  ① match          → sync certificates & profiles from encrypted Git repo
  ② gym            → build & archive the IPA
  ③ scan           → run unit + UI tests
  ④ pilot/deliver  → upload to TestFlight or App Store
```

### Fastfile

```ruby
default_platform(:ios)

platform :ios do

  desc "Sync certificates and provisioning profiles"
  lane :sync_certs do
    match(
      type: "appstore",
      app_identifier: "com.dreamgames.app",
      git_url: "https://github.com/dreamgames/ios-certs",
      readonly: true              # CI only reads, never regenerates
    )
  end

  desc "Build and test"
  lane :build do
    sync_certs
    scan(
      scheme: "DreamGamesApp",
      clean: true,
      output_directory: "test-results"
    )
    gym(
      scheme: "DreamGamesApp",
      export_method: "app-store",
      output_directory: "build",
      output_name: "DreamGamesApp.ipa"
    )
  end

  desc "Upload to TestFlight for QA"
  lane :beta do
    build
    pilot(
      ipa: "build/DreamGamesApp.ipa",
      skip_waiting_for_build_processing: true,
      changelog: ENV["CHANGELOG"] || "Internal beta build"
    )
  end

  desc "Release to App Store"
  lane :release do
    build
    deliver(
      ipa: "build/DreamGamesApp.ipa",
      submit_for_review: true,
      automatic_release: false,
      force: true
    )
  end

end
```

### Key Automation Points

| Step | Tool | Notes |
|------|------|-------|
| Code signing | `fastlane match` | Certs in encrypted Git repo; CI fetches with read-only key |
| Build | `fastlane gym` (xcodebuild wrapper) | Reproducible builds, export options plist |
| Tests | `fastlane scan` | JUnit XML output → CI test reporting |
| TestFlight upload | `fastlane pilot` | Automatic external tester distribution |
| App Store | `fastlane deliver` | Metadata, screenshots, phased release |

### Secret Management

```yaml
# GitHub Actions secrets (or AWS Secrets Manager)
MATCH_GIT_BASIC_AUTHORIZATION: <base64 git user:token>
MATCH_PASSWORD: <encryption password for certs repo>
APP_STORE_CONNECT_API_KEY_ID: <key id>
APP_STORE_CONNECT_API_ISSUER_ID: <issuer id>
APP_STORE_CONNECT_API_KEY_CONTENT: <p8 private key>
```

## Reviewer Defense

> "fastlane match is the industry standard for team code signing because it eliminates
> the 'certificate on one machine' problem. All engineers and all CI runners use the
> same certificate from the encrypted Git repo. App Store Connect API keys replace
> Apple ID 2FA friction. The Fastfile is version-controlled alongside the app code,
> so the build process is as auditable as the app itself."
