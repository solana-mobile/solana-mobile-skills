---
name: seeker-genesis-token
description: Verify Seeker device ownership by checking for the Seeker Genesis Token (SGT) with Sign-in-with-Solana and server-side token verification. Use when gating content or rewards to Seeker owners, verifying a user holds an SGT, adding anti-Sybil checks to a Solana mobile app, or implementing one-claim-per-device logic.
---

# Seeker Genesis Token verification

The Seeker Genesis Token (SGT) is a Token-2022 NFT minted once per Seeker device. Holding one
is evidence of owning a Seeker, which makes it useful for gating rewards and for
one-claim-per-device logic.

Verification has two halves, and **both are required**:

1. **Prove the user controls the wallet** — Sign-in-with-Solana (SIWS)
2. **Prove that wallet holds an SGT** — inspect the wallet's Token-2022 mints

Doing only the second means anyone can submit a real Seeker owner's public address and pass.
Doing only the first proves wallet control but says nothing about a device.

## This must run on a server

**Never decide entitlement client-side.** A client can be patched, so a client-side `hasSGT`
boolean is worth nothing. The client's job is to collect a signature; the server verifies it
and owns the result.

Requirements:

- A backend you control that can make Solana mainnet RPC calls
- Storage for nonces and claim records
- An RPC endpoint. A paid provider helps, since the check may enumerate many token accounts —
  keep that key server-side only, never in an `EXPO_PUBLIC_*` variable

## Prerequisites

A working wallet connection. If the app has none, use the `solana-mobile-wallet` skill first;
this skill assumes `useMobileWallet()` is available.

Testing needs a physical Seeker device — an emulator cannot hold an SGT. Plan for a code path
you can exercise without one, such as a server-side allowlist in development.

## Step 1: issue the payload from the server

The server issues the **whole** SIWS payload, not just a nonce, and stores it under the nonce
with a short TTL. Every field the client supplies is a field an attacker chooses, and each one
is fed straight to the signature check, so pin them all at issue time.

```ts
// POST /api/siws/nonce
const issuedAt = new Date()
const nonce = crypto.randomBytes(16).toString('hex')

const payload = {
  chainId: 'solana:mainnet',
  domain: 'yourdapp.com',
  expirationTime: new Date(issuedAt.getTime() + 300_000).toISOString(),
  issuedAt: issuedAt.toISOString(),
  nonce,
  statement: 'Sign in to verify Seeker ownership',
  uri: 'https://yourdapp.com',
  version: '1',
}

await store.put(nonce, payload, { ttlSeconds: 300 })
return payload
```

The nonce must be **server-generated, single-use, and short-lived**. A client-generated or
reusable nonce makes the signature replayable, which defeats the exercise.

`address` is the one field the server cannot fill in. The client adds it in step 2.

`chainId` is pinned to `solana:mainnet` deliberately rather than taken from the wallet's
`chain`: SGTs exist only on mainnet, so a signature scoped to devnet proves nothing about a
device. Issuing it server-side is what turns that into a guarantee instead of a comment.

## Step 2: sign in on the client

`signIn` from the wallet hook authorizes and proves ownership in a single prompt. Spread the
issued payload and add the address:

```ts
import { useMobileWallet } from '@wallet-ui/react-native-kit'

const { signIn } = useMobileWallet()

const issued = await fetch('https://yourdapp.com/api/siws/nonce', { method: 'POST' }).then(
  (response) => response.json(),
)

const address = account.address.toString()
const output = await signIn({ ...issued, address })

await fetch('https://yourdapp.com/api/siws/verify', {
  body: JSON.stringify({
    address,
    nonce: issued.nonce,
    signature: Array.from(output.signature),
    signedMessage: Array.from(output.signedMessage),
  }),
  headers: { 'Content-Type': 'application/json' },
  method: 'POST',
})
```

Post exactly those four fields. **Do not post `output.account`, and the server must never
accept an account object or a public key from the client** — the key the signature is checked
against has to be derived from the address the server is about to act on. Step 3 shows why.
`nonce` is only a lookup key here; the signature check is what binds it.

This is the fully-specified payload, not the short `signIn` form. `domain`, `nonce`, and
`version` are what make the signature non-replayable and bind it to your app, and the server
has to have issued them for that to hold. The `solana-mobile-wallet` skill covers both forms
and when each is appropriate.

## Step 3: verify the signature on the server

```bash
npm install @solana/kit @solana/wallet-standard-util
```

```ts
import { getBase58Encoder } from '@solana/kit'
import { verifySignIn } from '@solana/wallet-standard-util'

function verifySiws(issued, { address, signature, signedMessage }) {
  // Reject malformed input here, not inside the ed25519 verify.
  if (!Array.isArray(signature) || signature.length !== 64) {
    throw new Error('Malformed signature.')
  }
  if (!Array.isArray(signedMessage)) throw new Error('Malformed signed message.')

  // Derive the verifying key from the address, never from the request body.
  const publicKey = getBase58Encoder().encode(address)
  if (publicKey.length !== 32) throw new Error('Malformed address.')

  return verifySignIn(
    { ...issued, address },
    {
      account: { address, chains: [], features: [], publicKey },
      signature: new Uint8Array(signature),
      signedMessage: new Uint8Array(signedMessage),
    },
  )
}
```

The three shape checks come first because every one of those values is attacker-chosen. Without
them the malformed cases reach `new Uint8Array()` and then the ed25519 verify, where they land
inconsistently: a short signature throws a library error about byte lengths, while a non-array
`signedMessage` coerces to an empty array and returns a plain `false`. Rejecting on shape gives
one clear answer for both and does not lean on internals you do not control.

`verifySignIn` compares the fields you pass it against the fields inside the signed text, then
verifies the signature with `account.publicKey`. **It never checks that the key and the address
agree.** Take that key from the request body and any throwaway keypair can sign a message
naming any address: the signature is genuine, it just is not the address holder's.

Because the server issued `issued`, `domain` and `chainId` are pinned by construction. No
client copy of either reaches the check, so no separate domain comparison is needed. If you
want a defensive assertion anyway, assert against `issued.domain` — the stored copy — never a
value off the request.

## Step 4: check the wallet for an SGT

See [references/sgt-verification.md](references/sgt-verification.md) for the full
implementation. It confirms three properties of a Token-2022 mint — mint authority, metadata
pointer, and token group membership — and all three must match.

## Step 5: combine the checks correctly

This is where the subtle bug lives. `verifySignIn` does not bind the account key to the address
in the signed message, so the server has to do that binding itself: derive the key from the
address it is going to act on, and look the SGT up against that same address.

```ts
async function verifySeekerUser({ address, nonce, signature, signedMessage }) {
  // 1. Consume the nonce atomically. Read-then-mark leaves a window where two concurrent
  //    requests both see it unused, and one signature is accepted twice.
  //    Redis: GETDEL. SQL: DELETE FROM nonces WHERE nonce = $1 RETURNING payload.
  const issued = await store.consume(nonce)
  if (!issued) throw new Error('Invalid, reused, or expired nonce.')

  // 2. The signature must be valid for the payload we issued and for this address.
  if (!verifySiws(issued, { address, signature, signedMessage })) {
    throw new Error('Invalid signature.')
  }

  // 3. Check the SGT against the address the signature was just verified against.
  const { hasSGT, mintAddress } = await checkWalletForSGT(address)

  return { address, hasSGT, mintAddress }
}
```

Checking the SGT against any other address lets a caller submit a real Seeker owner's address
with their own signature and be granted access.

## Anti-Sybil: one claim per device

An SGT is per-device, so the **mint address** is the device identity. Store that, not the
wallet address — a wallet can hold a different SGT later, and a device's SGT can move between
wallets.

A `UNIQUE` constraint is what enforces one claim, not application code:

```sql
CREATE TABLE claims (
  claimed_at timestamptz NOT NULL DEFAULT now(),
  mint_address text NOT NULL UNIQUE,
  paid_at timestamptz
);
```

```ts
const { address, hasSGT, mintAddress } = await verifySeekerUser(request.body)
if (!hasSGT) throw new Error('No Seeker Genesis Token found.')

// Insert first and let the constraint decide. Asking whether a row exists and then
// inserting is a double-claim bug: two concurrent requests both find nothing.
try {
  await claims.insert({ claimedAt: new Date(), mintAddress })
} catch (error) {
  // 23505 is the Postgres unique violation. Other drivers report it differently.
  if (error.code === '23505') throw new Error('This device has already claimed.')
  throw error
}

// Pay out only once the insert has landed. Anything paid before it can be paid twice.
await grantReward(address)
await claims.markPaid(mintAddress)
```

The insert and the payout are two separate writes, so decide what happens when the second one
fails. As written, a `grantReward` that throws after the row commits leaves that device unable
to retry: the constraint now rejects it as already claimed. Either drive retries off rows
with a null `paid_at`, or make `grantReward` idempotent on `mintAddress` so replaying it is
free.
This one is robustness rather than security: getting it wrong denies a real owner their
reward, it does not let anyone claim twice.

Have `checkWalletForSGT` return the mint address rather than a bare boolean — see the end of
the reference file.

## Reference material

- [references/sgt-verification.md](references/sgt-verification.md) — full verification
  implementation, SGT constants, standard-RPC and Helius variants

## Related skills

- `solana-mobile-wallet` — wallet connection and the two `signIn` payload forms
- `seeker-domains` — `.skr` domain resolution, which Seeker users have by default

## Links

- Detecting Seeker users: https://docs.solanamobile.com/react-native/detecting-seeker-users
- Sign-in-with-Solana spec: https://github.com/phantom/sign-in-with-solana
