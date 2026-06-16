---
name: mwa-connection
description: Add wallet connect/disconnect functionality to a React Native app using Mobile Wallet Adapter. Use when the user wants to add a connect wallet button, implement wallet connection, show connected wallet address, or handle wallet state.
---

# MWA Wallet Connection

Add connect/disconnect wallet functionality using Mobile Wallet Adapter.

## When to Use

- User wants a "Connect Wallet" button
- User wants to display connected wallet address
- User wants to handle wallet connection state

## When NOT to Use

- MWA not set up yet → Use `mwa-setup` first
- User wants to send transactions → Use `mwa-transactions` instead

## Prerequisites

- MWA setup complete (polyfills, providers configured)
- If unsure, check for `MobileWalletProvider` in app layout

## The Hook

```typescript
import { useMobileWallet } from '@wallet-ui/react-native-web3js';

const { account, connect, disconnect } = useMobileWallet();
```

| Property | Type | Description |
|----------|------|-------------|
| `account` | `{ address, publicKey }` | Connected account (null if disconnected) |
| `connect()` | `async () => Account` | Triggers wallet picker, returns account |
| `disconnect()` | `async () => void` | Disconnects wallet |
| `account` truthiness | `boolean` | Connection state |

## Implementation

### Basic Connect Button

```typescript
import { View, Pressable, Text, StyleSheet } from 'react-native';
import { useMobileWallet } from '@wallet-ui/react-native-web3js';

export function ConnectButton() {
  const { account, connect, disconnect } = useMobileWallet();

  const handlePress = async () => {
    if (account) {
      await disconnect();
    } else {
      try {
        await connect();
      } catch (error) {
        console.error('Connection failed:', error);
      }
    }
  };

  return (
    <Pressable style={styles.button} onPress={handlePress}>
      <Text style={styles.text}>
        {account ? 'Disconnect' : 'Connect Wallet'}
      </Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: { backgroundColor: '#9945FF', padding: 15, borderRadius: 8 },
  text: { color: 'white', fontSize: 16, fontWeight: '600', textAlign: 'center' },
});
```

### Display Wallet Address

**IMPORTANT**: Always render a string, not the address object directly.

```typescript
import { Text } from 'react-native';
import { useMobileWallet } from '@wallet-ui/react-native-web3js';

export function WalletAddress() {
  const { account } = useMobileWallet();

  if (!account) return null;

  // Truncate for display
  const address =
    typeof account.address.toBase58 === 'function'
      ? account.address.toBase58()
      : account.address.toString();
  const truncated = `${address.slice(0, 4)}...${address.slice(-4)}`;

  return <Text>{truncated}</Text>;
}
```

### Adding to Existing Button

If user has an existing auth/login button:

```typescript
import { useMobileWallet } from '@wallet-ui/react-native-web3js';

export function ExistingLoginButton() {
  const { connect } = useMobileWallet();

  const handleLogin = async () => {
    try {
      const account = await connect();
      // account.address - PublicKey-like object
      // account.address.toBase58() / toString() - Base58 string
      // Continue with existing auth logic...
    } catch (error) {
      console.error('MWA connection failed:', error);
    }
  };

  return <Button onPress={handleLogin}>Login with Wallet</Button>;
}
```

## Key Points

1. **Session Persistence**: SDK automatically stores auth token. App will auto-reconnect on restart.

2. **Address Display**: Always convert `account.address` to a string — using `account.address` directly may show garbled text.

3. **Error Handling**: Wrap `connect()` in try-catch. User can cancel the wallet picker.

4. **Connection Flow**:
   - User taps connect
   - Android shows wallet picker (if multiple wallets)
   - User approves in wallet app
   - `connect()` resolves with account

## Troubleshooting

### Garbled Address Display

If address shows like "+9pgyt LK...MIiSdpI=":

```typescript
// WRONG
<Text>{account.address}</Text>

// CORRECT
<Text>{account.address.toBase58?.() ?? account.address.toString()}</Text>
```

## SIWS / Authenticated Connection

For Seeker Genesis Token verification or backend login, use Sign-In with Solana. If `useMobileWallet().signIn` is not sufficient for your flow, use direct `transact` from `@solana-mobile/mobile-wallet-adapter-protocol-web3js` and pass `sign_in_payload` to `wallet.authorize`.

Verify the `sign_in_result` on the backend with `@solana/wallet-standard-util`; do not trust a client-only signature check for gated rewards.

## Platform Boundary

MWA is an Android-native flow. It is not supported on iOS.

## Next Steps

After connection works:
- Add transactions → Use `mwa-transactions` skill
