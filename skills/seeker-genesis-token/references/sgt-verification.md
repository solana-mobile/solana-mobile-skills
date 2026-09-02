# SGT verification implementation

Server-side only. See the parent skill for why, and for the SIWS half of the check.

## What makes a mint an SGT

Three properties of a Token-2022 mint must **all** hold. Checking fewer is not a partial
check — it is a bypass, since any of them can be forged in isolation by an unrelated token.

These identify the mint. They say nothing about who holds it, so they are necessary but not
sufficient — see [the wallet must actually hold the token](#the-wallet-must-actually-hold-the-token).

| Property | Expected value |
| --- | --- |
| Mint authority | `GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4` |
| Metadata pointer authority | `GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4` |
| Metadata pointer address | `GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te` |
| Token group member group | `GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te` |

```js
const SGT_MINT_AUTHORITY = 'GT2zuHVaZQYZSyQMgJPLzvkmyztfyXg2NJunqFp4p3A4'

// The metadata address and group mint address are intentionally the same value.
const SGT_METADATA_ADDRESS = 'GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te'
const SGT_GROUP_MINT_ADDRESS = 'GT22s89nU4iWFkNXj1Bw6uYhJJWDRPpShHt4Bk8f99Te'
```

SGTs live on **mainnet**. There is no devnet equivalent to test against.

## Dependencies

```bash
npm install @solana/web3.js @solana/spl-token
```

## Shared mint check

Both variants below produce a list of Token-2022 mint addresses, then run them through this:

```js
const {
  getMetadataPointerState,
  getTokenGroupMemberState,
  TOKEN_2022_PROGRAM_ID,
  unpackMint,
} = require('@solana/spl-token')

const BATCH_SIZE = 100

async function findSgtMint(connection, mintPubkeys) {
  for (let i = 0; i < mintPubkeys.length; i += BATCH_SIZE) {
    const batch = mintPubkeys.slice(i, i + BATCH_SIZE)
    const infos = await connection.getMultipleAccountsInfo(batch)

    for (let j = 0; j < infos.length; j++) {
      if (!infos[j]) continue

      let mint
      try {
        mint = unpackMint(batch[j], infos[j], TOKEN_2022_PROGRAM_ID)
      } catch {
        continue // Not a Token-2022 mint we can read; not an SGT.
      }

      const metadataPointer = getMetadataPointerState(mint)
      const groupMember = getTokenGroupMemberState(mint)

      const ok =
        mint.mintAuthority?.toBase58() === SGT_MINT_AUTHORITY &&
        metadataPointer?.authority?.toBase58() === SGT_MINT_AUTHORITY &&
        metadataPointer?.metadataAddress?.toBase58() === SGT_METADATA_ADDRESS &&
        groupMember?.group?.toBase58() === SGT_GROUP_MINT_ADDRESS

      if (ok) return mint.address.toBase58()
    }
  }

  return null
}
```

`getMultipleAccountsInfo` is batched at 100 because most RPC providers reject larger
multi-account requests.

Returning the **mint address** rather than a boolean is deliberate: the mint identifies the
device, which is what anti-Sybil logic needs to record. See the parent skill.

## The wallet must actually hold the token

Both variants filter out token accounts with `amount === '0'` before collecting mints. This is
not defensive noise — omitting it is a verification bypass.

Transferring an SGT out of a wallet does not close the source Associated Token Account. The ATA
stays open forever with `amount: "0"`, and `getTokenAccountsByOwner` keeps returning it. Since
`findSgtMint` validates properties of the **mint** and never touches the balance, an unfiltered
list makes every wallet that has *ever* held an SGT verify as a current holder, permanently.

SGTs do move between wallets in practice, so these stale accounts are common rather than
hypothetical. The same filter also covers revocation: the mint carries a permanent delegate and
a close authority, so an SGT can be burned out of a wallet, leaving identical zero-balance
residue.

**Do not additionally reject frozen accounts.** A legitimately held SGT sits in a *frozen* ATA —
Solana Mobile holds the freeze authority and re-freezes on arrival, which is what stops holders
from moving the token themselves. Treating `state === 'frozen'` as suspicious rejects every real
Seeker owner. The balance is the discriminator; the freeze state is not.

## Variant 1: standard RPC

Works with any Solana RPC, no API key. Suitable when wallets hold a modest number of tokens.

```js
const { Connection, PublicKey } = require('@solana/web3.js')

async function checkWalletForSGT(walletAddress, rpcUrl) {
  const connection = new Connection(rpcUrl, 'confirmed')

  const { value: tokenAccounts } = await connection.getParsedTokenAccountsByOwner(
    new PublicKey(walletAddress),
    { programId: TOKEN_2022_PROGRAM_ID },
  )

  const mintPubkeys = tokenAccounts
    .filter((entry) => entry.account.data.parsed?.info?.tokenAmount?.amount !== '0')
    .map((entry) => entry.account.data.parsed?.info?.mint)
    .filter(Boolean)
    .map((mint) => new PublicKey(mint))

  const mintAddress = await findSgtMint(connection, mintPubkeys)

  return { hasSGT: mintAddress !== null, mintAddress }
}
```

`getParsedTokenAccountsByOwner` returns every matching account in one response with no
pagination. For a wallet with an unusually large number of Token-2022 accounts the response
can exceed provider size limits — that is the case variant 2 exists for.

## Variant 2: Helius with pagination

Uses `getTokenAccountsByOwnerV2`, which pages. Needed for wallets holding many token accounts.

```js
const { Connection, PublicKey } = require('@solana/web3.js')

const TOKEN_2022_PROGRAM = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb'

const MAX_PAGES = 50

async function checkWalletForSGT(walletAddress, heliusRpcUrl) {
  const connection = new Connection(heliusRpcUrl, 'confirmed')

  const accounts = []
  const seenKeys = new Set()
  let paginationKey = null
  let page = 0

  do {
    if (++page > MAX_PAGES) throw new Error(`Pagination exceeded ${MAX_PAGES} pages`)

    const response = await fetch(heliusRpcUrl, {
      body: JSON.stringify({
        id: `page-${page}`,
        jsonrpc: '2.0',
        method: 'getTokenAccountsByOwnerV2',
        params: [
          walletAddress,
          { programId: TOKEN_2022_PROGRAM },
          {
            encoding: 'jsonParsed',
            limit: 1000,
            withContext: true,
            ...(paginationKey && { paginationKey }),
          },
        ],
      }),
      headers: { 'Content-Type': 'application/json' },
      method: 'POST',
    })

    if (!response.ok) throw new Error(`RPC HTTP ${response.status}`)

    const data = await response.json()
    if (data.error) throw new Error(`RPC error: ${data.error.message}`)

    const value = data.result?.value
    if (!Array.isArray(value?.accounts)) {
      throw new Error('Unexpected getTokenAccountsByOwnerV2 response shape')
    }

    accounts.push(...value.accounts)
    paginationKey = value.paginationKey ?? null

    if (paginationKey !== null) {
      if (seenKeys.has(paginationKey)) {
        throw new Error('getTokenAccountsByOwnerV2 repeated a paginationKey')
      }
      seenKeys.add(paginationKey)
    }
  } while (paginationKey)

  const mintPubkeys = accounts
    .filter((entry) => entry?.account?.data?.parsed?.info?.tokenAmount?.amount !== '0')
    .map((entry) => entry?.account?.data?.parsed?.info?.mint)
    .filter(Boolean)
    .map((mint) => new PublicKey(mint))

  const mintAddress = await findSgtMint(connection, mintPubkeys)

  return { hasSGT: mintAddress !== null, mintAddress }
}
```

`withContext: true` is what makes the read above correct: with it, both `accounts` and
`paginationKey` live under `result.value`, and without it `result.value` *is* the account array
with `paginationKey` alongside it on `result` — so a copy that drops the flag has to read
`Array.isArray(result.value)` instead. Getting this wrong fails silently rather than loudly:
reading the wrong shape yields `undefined`, no accounts, and `hasSGT: false` for every wallet,
which is why the shape is asserted rather than defaulted to `[]`.

`seenKeys` and `MAX_PAGES` bound the loop. A provider that keeps handing back the same
`paginationKey` would otherwise spin forever, and a page cap alone does not catch that — it
just spins `MAX_PAGES` times first, which is why both guards are here rather than one.

Both throw instead of returning the accounts gathered so far. A truncated list is a list with
mints missing from it, and a missing mint reads as `hasSGT: false` — the same silent false
negative as the response-shape bug above, and the reason this file prefers a loud failure. At
`limit: 1000` the cap allows 50,000 Token-2022 accounts on one wallet, so raise it only if you
genuinely expect more.

## Error handling

Let RPC failures throw. Swallowing them and returning `{ hasSGT: false }` turns a transient
outage into "you do not own a Seeker", which is both wrong and hard to debug. Distinguish the
two cases at the API boundary:

```js
try {
  const { hasSGT, mintAddress } = await checkWalletForSGT(address, rpcUrl)
  return reply.send({ hasSGT, mintAddress })
} catch (error) {
  return reply.status(503).send({ error: 'Verification temporarily unavailable.' })
}
```
