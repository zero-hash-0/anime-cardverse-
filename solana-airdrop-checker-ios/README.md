# Solana Airdrop Radar (iOS)

This is a SwiftUI iOS app that monitors Solana token balance changes and flags likely airdrops with a built-in risk score.

## Implemented now

- Manual wallet connect/disconnect with persisted wallet session
- Solana JSON-RPC integration (`getTokenAccountsByOwner`) for SPL balances
- Snapshot-based delta detection for newly received/increased token balances
- Token metadata enrichment from a token list endpoint
- On-device claim risk scoring (`low`, `medium`, `high`) with human-readable reasons
- Local notification alerts after scans
- Unit tests for validator, risk scoring, and monitor delta logic

## Project status

The source code is complete, but this folder does not yet include an `.xcodeproj`.

## Create and run the Xcode app

1. In Xcode, create a new **iOS App** project named `AirdropChecker` (SwiftUI, Swift).
2. Save it in: `/Users/hectorruiz/Documents/New project/solana-airdrop-checker-ios`.
3. Replace generated app files with the files in `/Users/hectorruiz/Documents/New project/solana-airdrop-checker-ios/AirdropChecker`.
4. Add test files from `/Users/hectorruiz/Documents/New project/solana-airdrop-checker-ios/AirdropCheckerTests` to the test target.
5. Set deployment target to iOS 16+.
6. Build and run.

## Deep link format for wallet handoff

The app accepts wallet deep links in this format:

`airdropchecker://wallet?address=<SOLANA_WALLET_ADDRESS>`

## Important security note

Risk scoring is heuristic only and not a guarantee. Never sign unknown transactions and always verify claim domains and token provenance.

## Next upgrades to implement

- Wallet adapter/deep links for Phantom, Solflare, and Backpack connect flows
- Server-backed threat intel (domain + mint reputation)
- Push notifications via backend jobs for background monitoring
- Rich token detail view with trusted links and explorer actions
