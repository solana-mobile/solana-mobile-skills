---
name: solana-pay-mobile
description: SOL/USDC transfers in RN signed via MWA. Triggers - "add USDC payments", "Solana Pay", "send SOL", "checkout flow", "payment QR/link".
---

# Solana Pay (Mobile)

## Use

- Move SOL or USDC from the app
- Generate or consume a Solana Pay URL / QR
- Checkout, tip, send, or payment flow

## Not

- MWA not wired → `mwa-setup` first
- Swap UX → Jupiter / DFlow / Orca skills
- NFT mint → Metaplex skill
- Web app → use `@solana/pay` directly (RN can't)

## Prereq

MWA setup done via `mwa-setup` (sibling): `@wallet-ui/react-native-web3js`, `react-native-quick-crypto` installed through a first-import `polyfill.js`, `expo-dev-client`, and `MobileWalletProvider` wired. If not → do that first.

## Mints

| Token | Mainnet | Devnet |
|-------|---------|--------|
| USDC | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` | `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU` |
| SOL | native | native |

`constants/wallet.ts` only. Never inline.

## Build tx

`@solana/pay` = web-only. Use `@solana/web3.js`:

```ts
import { SystemProgram, Transaction } from '@solana/web3.js';
import {
  createTransferCheckedInstruction,
  getAssociatedTokenAddressSync,
  createAssociatedTokenAccountIdempotentInstruction,
} from '@solana/spl-token';

// SOL
const solIx = SystemProgram.transfer({
  fromPubkey: payer, toPubkey: recipient, lamports: sol * 1e9,
});

// USDC (6 dec)
const usdcIx = createTransferCheckedInstruction(
  getAssociatedTokenAddressSync(USDC_MINT, payer),
  USDC_MINT,
  getAssociatedTokenAddressSync(USDC_MINT, recipient),
  payer, usdc * 1e6, 6,
);
```

Recipient ATA may not exist? Prepend `createAssociatedTokenAccountIdempotentInstruction`. **Batch into one tx** (Seeker = one approval).

## Sign + send (hook path, preferred)

Use `useMobileWallet` from `@wallet-ui/react-native-web3js`:

```ts
import { useMobileWallet } from '@wallet-ui/react-native-web3js';
import { Transaction } from '@solana/web3.js';

function PayButton() {
  const { account, connection, signAndSendTransaction } = useMobileWallet();

  const pay = async () => {
    if (!account) return;
    const { blockhash, lastValidBlockHeight } = await connection.getLatestBlockhash();
    const tx = new Transaction({
      feePayer: account.address,
      blockhash,
      lastValidBlockHeight,
    }).add(usdcIx);

    const sig = await signAndSendTransaction(tx);  // returns string
    await connection.confirmTransaction({ signature: sig, blockhash, lastValidBlockHeight });
    return sig;
  };
}
```

- `account.address` = `PublicKey`-like object. Display with `account.address.toBase58?.() ?? account.address.toString()`.
- `connection` from the hook. Don't `new Connection()`.
- `signAndSendTransaction(tx)` = singular, returns `string`.

## Raw API (advanced)

Skip the hook for SIWS or custom wallet sessions:

```ts
import { transact } from '@solana-mobile/mobile-wallet-adapter-protocol-web3js';

const [sig] = await transact(async (wallet) => {
  await wallet.authorize({ cluster: 'solana:mainnet', identity: APP_IDENTITY });
  return wallet.signAndSendTransactions({ transactions: [tx] });
});
```

Raw `signAndSendTransactions` = plural, returns `string[]`.

## Solana Pay URL

```
solana:<recipient>?amount=<n>&spl-token=<mint>&reference=<pubkey>&label=<>&message=<>
```

- `amount` UI units (`10.50`), not lamports.
- `reference` = throwaway pubkey for tx lookup.
- `encodeURIComponent` label/message.

Incoming: parse → build tx → MWA sign.

## Pitfalls

| Issue | Fix |
|-------|-----|
| Garbled address text | `account.address.toBase58?.() ?? account.address.toString()`, never `{account.address}` directly |
| `Buffer doesn't exist` in RN | `btoa(String.fromCharCode(...uint8Array))` instead of `Buffer.from(...).toString('base64')` |
| Tx fails to unfunded recipient | Some wallets reject. Test with known funded addresses first. |
| Blockhash expired | Fresh blockhash per tx. Rebuild on retry. |
| Multi-tx UX | Batch ixs into one Transaction. Never chain `signAndSendTransaction` calls. |

## RPC

Never ship public RPC for mainnet. Use Helius/QuickNode/Triton via backend-issued key. Never embed in bundle.

## Refs

- docs.solanapay.com
- docs.solanamobile.com/llms.txt
- docs.solanamobile.com/get-started/react-native/invoke-mwa-sessions-directly
- Sibling: `../mwa/mwa-transactions/`
- github.com/solana-mobile/mobile-wallet-adapter
