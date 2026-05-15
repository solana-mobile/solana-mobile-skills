---
name: seeker-app-scaffold
description: Scaffold Solana Mobile RN app. Triggers - "create Solana Mobile app", "start Seeker dApp", "solana.new", "set up Android toolchain".
---

# Seeker App Scaffold

## Use

- No `package.json` yet, or only CLAUDE.md + git
- "create Solana Mobile app" / "start Seeker dApp" / "solana.new"
- Android toolchain setup (JDK 17, `adb`, `ANDROID_HOME`)

## Not

- Project scaffolded → `mwa-setup` (sibling)
- iOS-only → Solana Mobile = Android
- Web app → `gh:solana-foundation/templates/kit/nextjs` instead

## Prereq

```bash
node -v          # >= 20
java -version    # JDK 17
adb version
```

macOS missing:

```bash
brew install --cask zulu@17
brew install android-platform-tools
```

`ANDROID_HOME=~/Library/Android/sdk`. Add `$ANDROID_HOME/platform-tools` to PATH.

## Scaffold

Three equivalent paths:

| Path | When |
|------|------|
| `npm create solana-dapp@latest` | Discoverable picker (Category: Mobile → Template: `solana-mobile-expo-template`) |
| `npm create solana-dapp@latest -t gh:solana-foundation/templates/mobile/solana-mobile-expo-template` | Scripted (skip prompts) |
| `npx create-expo-app --template @solana-mobile/solana-mobile-expo-template` | Direct (know the template) |

Then:

```bash
cd <name> && npm install && npm run android
```

## Config

- `app.json` → `expo.android.package` = final reverse-DNS id. Must match dApp Store entry.
- `android/app/build.gradle` → `minSdkVersion 26` (MWA req).

## Rule

MWA = native modules. **Expo Go fails.** Always dev client:

```bash
npx expo prebuild --platform android --clean
npx expo run:android
```

## Polyfill (critical)

A crypto polyfill **MUST be the very first import** in app entry. Other modules check `crypto` on import — wrong order = silent tx failures.

Pick one:
- `react-native-get-random-values` (canonical; what the `mwa-setup` skill installs)
- `expo-crypto`'s `getRandomValues` via `src/polyfills.ts` (default in some Solana Mobile Expo templates)

Expo Router (`app/_layout.tsx`):

```ts
import 'react-native-get-random-values';  // FIRST
import { Stack } from 'expo-router';
```

React Navigation (`index.tsx`):

```ts
import 'react-native-get-random-values';  // FIRST
import { registerRootComponent } from 'expo';
```

## SDK choice

`@wallet-ui/react-native-web3js` (Beeman's Wallet UI SDK) = official recommendation. Provides `useMobileWallet` hook + `MobileWalletProvider`. Wraps the raw `@solana-mobile/mobile-wallet-adapter-protocol-web3js`.

```bash
npm install @wallet-ui/react-native-web3js @solana/web3.js @tanstack/react-query react-native-get-random-values
```

## Constants

`constants/wallet.ts`:

```ts
import type { Chain } from '@solana-mobile/mobile-wallet-adapter-protocol';

export const APP_IDENTITY = {
  name: '<Your App>',
  uri: 'https://yourapp.com',
  icon: 'favicon.ico',
};

export const SOLANA_CLUSTER = (process.env.EXPO_PUBLIC_SOLANA_CLUSTER || 'devnet') as 'devnet' | 'testnet' | 'mainnet-beta';
export const SOLANA_CHAIN: Chain = `solana:${SOLANA_CLUSTER}`;
export const SOLANA_RPC_ENDPOINT = process.env.EXPO_PUBLIC_SOLANA_RPC_ENDPOINT || 'https://api.devnet.solana.com';
```

`SOLANA_CHAIN` uses CAIP-2 format. MWA requires this exact shape.

## Pitfalls

| Error | Fix |
|-------|-----|
| `SDK location not found` | Set `ANDROID_HOME`; `android/local.properties` with `sdk.dir=...` |
| `Unable to locate a Java Runtime` | JDK 17 + `export JAVA_HOME=$(/usr/libexec/java_home -v 17)` |
| MWA error in Expo Go | Use dev client, not Go |
| `Secure context (https)` error from MWA | `rm -rf node_modules/@solana-mobile/mobile-wallet-adapter-protocol/lib/esm` then rebuild |
| Silent tx failures, `crypto.getRandomValues` not found | Polyfill not first import (see above) |

## Refs

- docs.solanamobile.com/get-started/react-native/create-solana-mobile-app
- docs.solanamobile.com/get-started/react-native/setup
