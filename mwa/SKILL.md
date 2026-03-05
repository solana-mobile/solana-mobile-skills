---
name: mwa
description: Integrate Mobile Wallet Adapter (MWA) for wallet connection and transaction signing in React Native Expo apps using @wallet-ui/react-native-web3js. Use when the user wants to add wallet support, connect wallets, sign transactions, send SOL, or set up MWA in their Solana mobile app.
---

# Mobile Wallet Adapter (MWA)

Add Solana wallet connection and transaction signing to React Native Expo apps using [Beeman's Wallet UI SDK](https://wallet-ui.dev/) (`@wallet-ui/react-native-web3js`).

## Assess First, Then Route

Before doing anything, determine what the user's project needs:

1. **Is MWA set up?** Check for `MobileWalletProvider` in the app layout and `@wallet-ui/react-native-web3js` in `package.json`.
   - **No** -> Start with [mwa-setup](mwa-setup/SKILL.md)
   - **Yes** -> Continue to step 2

2. **What does the user want?**

| Need | Sub-Skill | What It Does |
|------|-----------|--------------|
| Install deps, polyfills, providers | [mwa-setup](mwa-setup/SKILL.md) | Installs packages, configures crypto polyfills, wraps app in `MobileWalletProvider` |
| Connect/disconnect wallet | [mwa-connection](mwa-connection/SKILL.md) | Adds connect button, displays wallet address, handles connection state |
| Send SOL / sign transactions | [mwa-transactions](mwa-transactions/SKILL.md) | Builds and signs transactions, sends SOL transfers, confirms on-chain |
| Full integration (all of the above) | Start with setup, then connection, then transactions | Sequential — each builds on the previous |

## Requirements

- React Native Expo project
- **Development build** (not Expo Go — MWA uses native Android modules)
- Android device or emulator
- A Solana wallet app installed (e.g., Phantom, Solflare)
