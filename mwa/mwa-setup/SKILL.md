---
name: mwa-setup
description: Set up Mobile Wallet Adapter dependencies, crypto polyfills, and providers in a React Native Expo app. Use when the user needs to install MWA packages, configure polyfills, set up MobileWalletProvider, or prepare their app for wallet integration.
---

# MWA Setup

Install dependencies, configure crypto polyfills, and set up providers for Mobile Wallet Adapter.

## When to Use

- User wants to add MWA to a fresh React Native project
- Project is missing MWA dependencies or providers
- Crypto polyfill errors ("crypto.getRandomValues() not supported")

## When NOT to Use

- Project already has MWA set up (check for `MobileWalletProvider` in layout)
- User just wants to add a connect button → Use `mwa-connection` instead
- User just wants transactions → Use `mwa-transactions` instead

## Prerequisites

- React Native Expo project
- **NOT using Expo Go** (requires development build)
- Android development environment
- Native MWA is Android only; do not promise iOS support for this flow

## Implementation

### Step 1: Install Dependencies

```bash
npm install @wallet-ui/react-native-web3js react-native-quick-crypto @solana/web3.js expo-dev-client
```

### Step 2: Crypto Polyfill (CRITICAL)

**The crypto polyfill MUST be the VERY FIRST import in the app entry point.**

Create `polyfill.js` at the project root:

```typescript
import { install } from 'react-native-quick-crypto';

install();
```

Then import it first in `index.js`:

```typescript
import './polyfill'; // MUST BE FIRST

import { registerRootComponent } from 'expo';
import App from './App';

registerRootComponent(App);
```

Set `package.json` main to the new entry point:

```json
{
  "main": "./index.js"
}
```

**Why**: Other modules check for `crypto` on import. Wrong order = transactions fail silently.

### Step 3: Environment Variables

Create `.env` in project root:
```bash
EXPO_PUBLIC_SOLANA_CLUSTER=devnet
EXPO_PUBLIC_SOLANA_RPC_ENDPOINT=https://api.devnet.solana.com
```

### Step 4: Wallet Constants

Create `constants/wallet.ts`:
```typescript
import type { Chain } from '@solana-mobile/mobile-wallet-adapter-protocol';

export const APP_IDENTITY = {
  name: 'Your App Name',
  uri: 'https://yourapp.com',
  icon: 'favicon.ico',
};

export const SOLANA_CLUSTER = (
  process.env.EXPO_PUBLIC_SOLANA_CLUSTER || 'devnet'
) as 'devnet' | 'testnet' | 'mainnet-beta';

export const SOLANA_CHAIN: Chain = `solana:${SOLANA_CLUSTER}`;

export const SOLANA_RPC_ENDPOINT =
  process.env.EXPO_PUBLIC_SOLANA_RPC_ENDPOINT ||
  'https://api.devnet.solana.com';
```

### Step 5: Configure Provider

Wrap app with `MobileWalletProvider`:

**Root app component** (`App.tsx`):

```typescript
import { MobileWalletProvider } from '@wallet-ui/react-native-web3js';
import { APP_IDENTITY, SOLANA_CHAIN, SOLANA_RPC_ENDPOINT } from '@/constants/wallet';

export default function App() {
  return (
    <MobileWalletProvider
      chain={SOLANA_CHAIN}
      endpoint={SOLANA_RPC_ENDPOINT}
      identity={APP_IDENTITY}
    >
      {/* app content */}
    </MobileWalletProvider>
  );
}
```

### Step 6: Build Development Build

```bash
npx expo prebuild --clean
npx expo run:android
```

**Required** because MWA uses native Android modules not included in Expo Go.

## Direct MWA Sessions

Prefer Wallet UI for normal connect/disconnect and transaction hooks. If the feature needs SIWS, direct authorization, message signing, or custom transaction sessions, use the web3.js wrapper:

```bash
npm install @solana-mobile/mobile-wallet-adapter-protocol-web3js @solana-mobile/mobile-wallet-adapter-protocol
```

```typescript
import { transact } from '@solana-mobile/mobile-wallet-adapter-protocol-web3js';
```

Do not import `transact` from the base protocol package unless you intentionally want base64 payload handling instead of web3.js types.

## Troubleshooting

### "Secure context (https)" Error

```
SolanaMobileWalletAdapterError: The mobile wallet adapter protocol must be used in a secure context (`https`).
```

**Fix**: Remove ESM folder to force native resolution:
```bash
rm -rf node_modules/@solana-mobile/mobile-wallet-adapter-protocol/lib/esm
npx expo run:android
```

## Next Steps

After setup is complete:
- Add wallet connection → Use `mwa-connection` skill
- Add transactions → Use `mwa-transactions` skill

## Refs

- https://docs.solanamobile.com/llms.txt
- https://docs.solanamobile.com/get-started/react-native/installation
- https://docs.solanamobile.com/get-started/react-native/setup
- https://docs.solanamobile.com/get-started/react-native/invoke-mwa-sessions-directly
- https://docs.solanamobile.com/solana-mobile-stack/mobile-wallet-adapter
