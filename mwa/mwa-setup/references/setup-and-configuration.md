# Setup and Configuration

Complete setup guide for Mobile Wallet Adapter integration in React Native Expo apps.

## Prerequisites

### Required Dependencies

```bash
npm install @wallet-ui/react-native-web3js react-native-quick-crypto @solana/web3.js expo-dev-client
```

### Development Build Requirement

⚠️ **IMPORTANT**: Mobile Wallet Adapter requires a development build. **Expo Go will NOT work**.

```bash
# Generate native projects
npx expo prebuild --clean

# Build for Android
npx expo run:android
```

**Why?**
- MWA uses native Android modules
- Expo Go doesn't include custom native modules
- Must use development build or EAS Build for production

## Critical: Crypto Polyfill Setup

### Implementation

Create `polyfill.js` at the project root:

```typescript
import { install } from 'react-native-quick-crypto';

install();
```

Then import it as the **FIRST import** in `index.js`:

```typescript
import './polyfill';  // ⚠️ MUST BE FIRST

import { registerRootComponent } from 'expo';
import App from './App';

registerRootComponent(App);
```

### Why This Is Critical

**Order Matters**:
- Polyfills global `crypto` object
- Other modules check for crypto on import
- If imported late, modules already failed their checks
- Can cause random "crypto.getRandomValues() not supported" errors

**Symptoms**:
- ✅ Wallet connection works (doesn't need crypto)
- ❌ Transactions fail (needs crypto for blockhash/IDs)
- ❌ getLatestBlockhash() throws error
- ❌ Random crashes when signing

## Environment Configuration

### .env File

```bash
EXPO_PUBLIC_SOLANA_CLUSTER=devnet
EXPO_PUBLIC_SOLANA_RPC_ENDPOINT=https://api.devnet.solana.com
```

**For Production**:
```bash
EXPO_PUBLIC_SOLANA_CLUSTER=mainnet-beta
EXPO_PUBLIC_SOLANA_RPC_ENDPOINT=https://api.mainnet-beta.solana.com
```

### Constants File

Create `constants/wallet.ts`:

```typescript
export const APP_IDENTITY = {
  name: 'Your App Name',
  uri: 'https://yourapp.com',
  icon: 'favicon.ico',
};

export const SOLANA_CLUSTER = (
  process.env.EXPO_PUBLIC_SOLANA_CLUSTER || 'devnet'
) as 'devnet' | 'testnet' | 'mainnet-beta';

export const SOLANA_RPC_ENDPOINT = 
  process.env.EXPO_PUBLIC_SOLANA_RPC_ENDPOINT || 
  'https://api.devnet.solana.com';
```

## Provider Setup

### Root Layout Configuration

In `app/_layout.tsx`:

```typescript
import { Stack } from 'expo-router';
import { MobileWalletProvider } from '@wallet-ui/react-native-web3js';
import { SOLANA_CLUSTER, SOLANA_RPC_ENDPOINT, APP_IDENTITY } from '@/constants/wallet';

export default function RootLayout() {
  const chain = `solana:${SOLANA_CLUSTER}` as const;

  return (
    <MobileWalletProvider
      chain={chain}
      endpoint={SOLANA_RPC_ENDPOINT}
      identity={APP_IDENTITY}
    >
      <Stack>
        <Stack.Screen name="index" />
        {/* Other screens */}
      </Stack>
    </MobileWalletProvider>
  );
}
```

## Common Setup Issues

### Issue: "crypto.getRandomValues() not supported"
**Solution**: Install `react-native-quick-crypto`, create `polyfill.js`, and import `./polyfill` first in `index.js`.

### Issue: Wallet popup doesn't appear
**Solution**: Run `npx expo prebuild --clean` and rebuild. Ensure you're not using Expo Go.

### Issue: "Cannot find module '@wallet-ui/react-native-web3js'"
**Solution**: Install dependencies and rebuild:
```bash
npm install
npx expo prebuild --clean
npx expo run:android
```

### Issue: App crashes on transaction
**Solution**: Check crypto polyfill is first import. Clear cache and rebuild.

### Issue: "Buffer doesn't exist" error
**Solution**: `Buffer` is a Node.js global that doesn't exist in React Native. Use `btoa` instead:
```typescript
// ❌ Won't work
const base64 = Buffer.from(uint8Array).toString("base64");

// ✅ Works in React Native
const base64 = btoa(String.fromCharCode(...uint8Array));
```
