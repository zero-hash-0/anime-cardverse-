# TestFlight Release Checklist

## Required Account Setup

- Active Apple Developer Program membership
- App Store Connect app created with bundle id: `com.hectorruiz.radar`
- Team selected in Xcode Signing settings

## Xcode Release Settings

- Open `/Users/hectorruiz/Documents/New project/solana-airdrop-checker-ios/AirdropChecker.xcodeproj`
- Set `DEVELOPMENT_TEAM` in `/Users/hectorruiz/Documents/New project/solana-airdrop-checker-ios/Config/Common.xcconfig`
- Bump version values in `Common.xcconfig`:
  - `MARKETING_VERSION`
  - `CURRENT_PROJECT_VERSION`
- Confirm `Release` configuration uses automatic signing

## Preflight QA

- Run on iPhone simulator and physical iPhone
- Validate wallet input, scan, demo mode, history, risk labels
- Validate icon appears on home screen
- Validate deep link handling:
  - `airdropchecker://wallet?address=<WALLET_ADDRESS>`

## Archive & Upload

1. Select `Any iOS Device (arm64)` destination in Xcode
2. Product -> Archive
3. Distribute App -> App Store Connect -> Upload
4. In App Store Connect, add internal testers and submit build for testing

## Metadata / Compliance

- App description, keywords, support URL, privacy policy URL
- Age rating questionnaire
- Export compliance answers
- Upload screenshots for required device classes
