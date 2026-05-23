---
name: mwa-transactions
description: Add transaction signing and SOL transfers to a React Native app using Mobile Wallet Adapter. Use when the user wants to send SOL, sign transactions, implement transfers, or add transaction functionality to their Solana mobile app.
---

# MWA Transactions

Add SOL transfers and transaction signing using Mobile Wallet Adapter.

## When to Use

- User wants to send SOL from their app
- User wants to sign and send transactions
- User wants to implement transfer functionality

## When NOT to Use

- MWA not set up → Use `mwa-setup` first
- Wallet connection not working → Use `mwa-connection` first

## Prerequisites

- MWA setup complete
- Wallet connection working
- User can connect/disconnect successfully

## The Hook

```typescript
import { useMobileWallet } from '@wallet-ui/react-native-web3js';

const { account, connection, signAndSendTransaction } = useMobileWallet();
```

| Property | Type | Description |
|----------|------|-------------|
| `account` | `{ address, publicKey }` | Connected wallet |
| `connection` | `Connection` | Solana RPC connection |
| `signAndSendTransaction` | `async (tx) => string` | Sign and broadcast, returns signature |
| `signMessage` | `async (msg) => Uint8Array` | Sign arbitrary message |

## Implementation

### SOL Transfer

```typescript
import { useState } from 'react';
import { View, TextInput, Pressable, Text, Alert } from 'react-native';
import { useMobileWallet } from '@wallet-ui/react-native-web3js';
import {
  PublicKey,
  Transaction,
  SystemProgram,
  LAMPORTS_PER_SOL,
} from '@solana/web3.js';

export function SendSol() {
  const { account, connection, signAndSendTransaction } = useMobileWallet();
  const [recipient, setRecipient] = useState('');
  const [amount, setAmount] = useState('');
  const [loading, setLoading] = useState(false);

  const handleSend = async () => {
    if (!account) return;

    try {
      setLoading(true);

      // Get fresh blockhash
      const { blockhash, lastValidBlockHeight } =
        await connection.getLatestBlockhash();

      // Build transaction
      const transaction = new Transaction({
        feePayer: account.address,
        blockhash,
        lastValidBlockHeight,
      }).add(
        SystemProgram.transfer({
          fromPubkey: account.address,
          toPubkey: new PublicKey(recipient),
          lamports: Math.floor(parseFloat(amount) * LAMPORTS_PER_SOL),
        })
      );

      // Sign and send
      const signature = await signAndSendTransaction(transaction);

      // Confirm
      await connection.confirmTransaction({
        signature,
        blockhash,
        lastValidBlockHeight,
      });

      Alert.alert('Success', `Sent ${amount} SOL\n\nSignature: ${signature.slice(0, 20)}...`);
    } catch (error: any) {
      Alert.alert('Error', error.message);
    } finally {
      setLoading(false);
    }
  };

  if (!account) return <Text>Connect wallet first</Text>;

  return (
    <View style={{ padding: 20 }}>
      <TextInput
        placeholder="Recipient Address"
        value={recipient}
        onChangeText={setRecipient}
        style={{ borderWidth: 1, padding: 10, marginBottom: 10, borderRadius: 4 }}
      />
      <TextInput
        placeholder="Amount (SOL)"
        value={amount}
        onChangeText={setAmount}
        keyboardType="decimal-pad"
        style={{ borderWidth: 1, padding: 10, marginBottom: 10, borderRadius: 4 }}
      />
      <Pressable
        onPress={handleSend}
        disabled={loading || !recipient || !amount}
        style={{
          backgroundColor: '#9945FF',
          padding: 15,
          borderRadius: 8,
          opacity: loading ? 0.6 : 1,
        }}
      >
        <Text style={{ color: 'white', textAlign: 'center', fontWeight: 'bold' }}>
          {loading ? 'Sending...' : 'Send SOL'}
        </Text>
      </Pressable>
    </View>
  );
}
```

### Transaction Pattern

Wallet UI transactions follow this pattern:

```typescript
// 1. Get fresh blockhash
const { blockhash, lastValidBlockHeight } = await connection.getLatestBlockhash();

// 2. Build transaction
const transaction = new Transaction({
  feePayer: account.address,
  blockhash,
  lastValidBlockHeight,
}).add(/* instructions */);

// 3. Sign and send
const signature = await signAndSendTransaction(transaction);

// 4. Confirm
await connection.confirmTransaction({ signature, blockhash, lastValidBlockHeight });
```

For direct Mobile Wallet Adapter sessions, use `transact` from `@solana-mobile/mobile-wallet-adapter-protocol-web3js` and call `wallet.signAndSendTransactions` / `wallet.signTransactions` inside the callback. Do not import `transact` from the base protocol package unless you intentionally want lower-level encoded payloads.

Prefer versioned transactions for new code unless the target wallet or program requires legacy transactions.

## Key Points

1. **Use hook's connection**: Don't create `new Connection()`. Use `connection` from the hook.

2. **Fresh blockhash**: Always get a new blockhash. They expire in ~150 blocks (~1-2 minutes).

3. **Recipient must exist**: Some wallets reject transactions to accounts that don't exist on-chain. Test with known addresses first.

4. **No Buffer**: React Native doesn't have `Buffer`. For encoding:
   ```typescript
   // Base64 encoding (if needed)
   const base64 = btoa(String.fromCharCode(...uint8Array));
   ```

5. **Avoid session chaining**: Batch related instructions into one transaction request when one user action needs one approval.

## Troubleshooting

### "Buffer doesn't exist" Error

```typescript
// WRONG - Buffer doesn't exist in RN
Buffer.from(signature).toString('base64');

// CORRECT
btoa(String.fromCharCode(...signature));
```

### Transaction Fails to Random Addresses

Some wallets require recipient to exist on-chain. Test with a known funded address first.

### "payloads invalid for signing" Error

Usually means the transaction is malformed or blockhash expired. Get a fresh blockhash and rebuild.

## Reference

For complete implementation with balance display, explorer links, and more error handling:
- [references/transaction-signing.md](references/transaction-signing.md)

Official refs:
- https://docs.solanamobile.com/llms.txt
- https://docs.solanamobile.com/get-started/react-native/invoke-mwa-sessions-directly
- https://docs.solanamobile.com/get-started/react-native/mobile-wallet-adapter
