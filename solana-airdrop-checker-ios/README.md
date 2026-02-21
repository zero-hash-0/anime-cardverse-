# Solana Airdrop Radar (iOS)

SwiftUI iOS app that monitors Solana token balance changes, flags likely airdrops, and surfaces claim-risk hints before users interact.

## Implemented

- Wallet connect/disconnect with persisted wallet session
- Solana JSON-RPC integration (`getTokenAccountsByOwner`) for SPL balances
- Snapshot-based delta detection for newly received/increased token balances
- Token metadata enrichment with endpoint cache + fallback
- Claim risk scoring (`low`, `medium`, `high`) with reasons and score
- Local notifications for newly detected events
- Persistent airdrop history feed with search/filtering
- Event detail view with copy-mint and Solscan open actions
- Optional foreground auto-scan loop every 10 minutes
- Unit tests for validator, risk scoring, delta detection, and history store

## Project status

Source is ready to wire into an Xcode app target, but this folder still does not include an `.xcodeproj`.

## Create and run in Xcode

1. Create a new iOS App project named `AirdropChecker` (SwiftUI + Swift).
2. Save it to `/Users/hectorruiz/Documents/New project/solana-airdrop-checker-ios`.
3. Replace generated app files with files in `/Users/hectorruiz/Documents/New project/solana-airdrop-checker-ios/AirdropChecker`.
4. Add tests from `/Users/hectorruiz/Documents/New project/solana-airdrop-checker-ios/AirdropCheckerTests` to the test target.
5. Set deployment target to iOS 16+.
6. Add URL scheme `airdropchecker` to the app target.
7. Build and run.

## Deep link format

`airdropchecker://wallet?address=<SOLANA_WALLET_ADDRESS>`

## This-week release checklist

- Add signing team, bundle id, icons, launch screen, and privacy strings
- Add crash reporting + analytics (Sentry/Firebase)
- Add backend threat intel endpoint to complement local heuristics
- Add retry/backoff for RPC + metadata endpoint failures
- Run TestFlight beta with real wallets and monitor false positives

## Security note

Risk scoring is heuristic only. Never sign unknown transactions and never visit unknown claim links from a primary wallet.
