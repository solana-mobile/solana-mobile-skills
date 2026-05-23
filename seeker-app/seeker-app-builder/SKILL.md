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
| Need direct MWA session APIs | `mwa-setup`, then use `@solana-mobile/mobile-wallet-adapter-protocol-web3js` for `transact` |
| Need Seeker-owner gating | `genesis-token` (sibling) — SIWS + SGT check |
| Need `.skr` name resolution | `skr-address-resolution` (sibling) |
| Need on-chain action | `mwa-transactions` (SOL) or `solana-pay-mobile` (USDC) |
| Untuned UX | `seeker-ux` |
| Ready to ship | `dapp-store-publishing` |
| Building a wallet (not dApp) | `seed-vault` |

## Order

scaffold → MWA setup → connection → tx action → UX → publish.

## Constraints

- Start from `https://docs.solanamobile.com/llms.txt` before browsing docs pages.
- Native MWA is Android only. Do not imply iOS support for this wallet flow.
- No private keys in app code. MWA signs.
- APK only. No AAB.
- minSdkVersion 26.
- Different signing key from Google Play if dual-ship.
- Platform constants can identify Seeker for UI treatment only; secure gating requires SIWS + Seeker Genesis Token verification.

## Refs

- docs.solanamobile.com
- docs.solanamobile.com/llms.txt
- docs.solanamobile.com/get-started/react-native/installation
- docs.solanamobile.com/get-started/react-native/invoke-mwa-sessions-directly
- docs.solanamobile.com/recipes/general/detecting-seeker-users
- docs.solanamobile.com/dapp-store/intro
- docs.solanamobile.com/dapp-store/build-and-sign-an-apk
