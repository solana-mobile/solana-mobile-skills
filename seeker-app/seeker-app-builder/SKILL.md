---
name: seeker-app-builder
description: Router for building a Solana Mobile (Seeker) dApp end-to-end. Triggers - "build a Seeker app", "ship to dApp Store", "start Solana Mobile RN project". Delegates to sub-skills.
---

# Seeker App Builder

## Use

- "build a Seeker app" / "ship to dApp Store" / "start Solana Mobile project"
- Multi-phase work: scaffold → MWA → tx → UX → publish

## Not

- Single phase → call the sub-skill directly
- Debugging an existing app → jump to the specific skill
- Wallet app (manages seeds) → `seed-vault`

## Route

| State | Sub-skill |
|-------|-----------|
| No project | `seeker-app-scaffold` |
| No wallet | `mwa-setup` → `mwa-connection` (sibling) — uses `@wallet-ui/react-native-web3js` |
| Need Seeker-owner gating | `genesis-token` (sibling) — SIWS + SGT check |
| Need `.skr` name resolution | `skr-address-resolution` (sibling) |
| No on-chain action | `mwa-transactions` (SOL) or `solana-pay-mobile` (USDC) |
| Untuned UX | `seeker-ux` |
| Ready to ship | `dapp-store-publishing` |
| Building a wallet (not dApp) | `seed-vault` |

## Order

scaffold → MWA setup → connection → tx action → UX → publish.

## Constraints

- No private keys in app code. MWA signs.
- APK only. No AAB.
- minSdkVersion 26.
- Different signing key from Google Play if dual-ship.

## Refs

- docs.solanamobile.com
- docs.solanamobile.com/dapp-store/intro
