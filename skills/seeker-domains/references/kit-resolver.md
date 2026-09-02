# Kit resolver reference

A self-contained `.skr` resolver built on `@solana/kit`. This is the default — prefer it over
`@onsol/tldparser` unless you need the parts of AllDomains it does not cover (see
[Limits](#limits)).

Resolving a `.skr` name is a PDA derivation plus one account read. That is small enough to own
outright, which buys a not-found path that returns `null` instead of throwing, input handling
that accepts what users actually type, and no dependency on an SDK whose ESM build is broken.

```bash
npm install @solana/kit "@noble/hashes@^1"
```

`@noble/hashes` is a separate install: `@solana/kit` does not depend on it, so it is only
present by accident if something else in the tree pulls it in. It is pure JavaScript and works
under Hermes.

**Pin the major, and import `sha2.js` with the extension.** A bare `npm install @noble/hashes`
now resolves to 2.x, whose `exports` map lists `./sha2.js` and nothing else — the extensionless
`@noble/hashes/sha2` that 1.x also accepted fails there under strict exports resolution. The
`./sha2.js` specifier used below is valid on both 1.x and 2.x, so it survives an accidental
upgrade; the `^1` pin is what keeps the rest of the 2.x API changes out.

## How `.skr` names are stored

`.skr` is a TLD in AllDomains' Alt Name Service (ANS). Every name is an account owned by the
ANS program, found by a chain of PDAs — each seeded with `sha256("ALT Name Service" + name)`:

| Account | Seeds |
| --- | --- |
| ANS root | `hash("ANS")`, 32 zero bytes, 32 zero bytes |
| `.skr` parent | `hash(".skr")`, 32 zero bytes, ANS root |
| `alice.skr` | `hash("alice")`, 32 zero bytes, `.skr` parent |

The root is a constant, `3mX9b4AZaQehNoQGfckVcmgmA6bkBoFcbLj9RMmMyNcU`. Deriving it and
comparing against that value is a cheap self-check that the hashing and seed order are right —
worth keeping in a test, because every wrong derivation fails the same silent way: a PDA for an
account that does not exist, indistinguishable from an unregistered name.

The account is a 200-byte header. Three fields matter here:

| Offset | Field |
| --- | --- |
| 8 | `parentName` (32 bytes) — the memcmp filter for reverse lookup |
| 40 | `owner` (32 bytes) |
| 104 | `expiresAt` (u64 LE, seconds; `0` means non-expiring) |

The forward record carries nothing after byte 200. The human-readable label lives in a separate
reverse-lookup account, seeded with the name account's own base58 string — which is why reverse
lookup has to read a second account for every name. Those reads are batched 100 at a time
through `getMultipleAccounts`, so the cost is one request per 100 names rather than one each.

## Implementation

Compiles clean under `tsc --strict`. It touches no `Buffer`, `TextEncoder`, or `TextDecoder`,
using Kit's codecs instead, so the same file runs on a server and in React Native.

```typescript
// src/skr.ts
import {
  address,
  getAddressDecoder,
  getAddressEncoder,
  getBase64Encoder,
  getProgramDerivedAddress,
  getUtf8Decoder,
  getUtf8Encoder,
  type Address,
  type Base58EncodedBytes,
  type createSolanaRpc,
} from '@solana/kit';
// Extensioned subpath: valid on @noble/hashes 1.x and 2.x. Bare 'sha2' breaks on 2.x.
import { sha256 } from '@noble/hashes/sha2.js';

type Rpc = ReturnType<typeof createSolanaRpc>;

const ANS_PROGRAM = address('ALTNSZ46uaAUU7XUV6awvdorLGqAsPwa9shm7h4uP2FK');
const TLD_HOUSE_PROGRAM = address('TLDHkysf5pCnKsVA4gXpNvmy7psXLPEu4LAdDJthT9S');
const NAME_HOUSE_PROGRAM = address('NH3uX6FtVE2fNREAioP7hm5RaozotZxeL6khU1EHx51');
const ROOT_ANS = address('3mX9b4AZaQehNoQGfckVcmgmA6bkBoFcbLj9RMmMyNcU');
const HASH_PREFIX = 'ALT Name Service';
const TLD = '.skr';

const HEADER_SIZE = 200;
const OWNER_OFFSET = 40;
const EXPIRES_AT_OFFSET = 104;

// getMultipleAccounts takes at most 100 addresses per call.
const REVERSE_BATCH_SIZE = 100;

const addressDecoder = getAddressDecoder();
const utf8Decoder = getUtf8Decoder();
const base64Encoder = getBase64Encoder();

const utf8 = (value: string) => new Uint8Array(getUtf8Encoder().encode(value));
const addressBytes = (value: Address) => new Uint8Array(getAddressEncoder().encode(value));
const ZERO_32 = new Uint8Array(32);

const hashName = (name: string) => sha256(utf8(HASH_PREFIX + name));

async function pda(programAddress: Address, seeds: Uint8Array[]): Promise<Address> {
  const [derived] = await getProgramDerivedAddress({ programAddress, seeds });
  return derived;
}

const deriveNameAccount = (name: string, parent?: Address) =>
  pda(ANS_PROGRAM, [hashName(name), ZERO_32, parent ? addressBytes(parent) : ZERO_32]);

const deriveTldHouse = () => pda(TLD_HOUSE_PROGRAM, [utf8('tld_house'), utf8(TLD)]);

const deriveReverseAccount = (nameAccount: Address, tldHouse: Address) =>
  pda(ANS_PROGRAM, [hashName(nameAccount), addressBytes(tldHouse), ZERO_32]);

async function deriveNftRecord(nameAccount: Address, tldHouse: Address) {
  const nameHouse = await pda(NAME_HOUSE_PROGRAM, [utf8('name_house'), addressBytes(tldHouse)]);
  return pda(NAME_HOUSE_PROGRAM, [
    utf8('nft_record'),
    addressBytes(nameHouse),
    addressBytes(nameAccount),
  ]);
}

async function fetchAccountData(rpc: Rpc, account: Address): Promise<Uint8Array | null> {
  const { value } = await rpc.getAccountInfo(account, { encoding: 'base64' }).send();
  return value ? new Uint8Array(base64Encoder.encode(value.data[0])) : null;
}

/** Normalise user input to a bare label, or null if it cannot name a .skr domain. */
export function normalizeSkrName(input: string): string | null {
  const label = input.trim().toLowerCase().replace(/\.skr$/, '');
  return /^[a-z0-9-]{1,63}$/.test(label) ? label : null;
}

/** Forward lookup. Accepts "alice.skr" or "alice". Returns null when unregistered. */
export async function resolveSkrDomain(rpc: Rpc, domain: string): Promise<Address | null> {
  const label = normalizeSkrName(domain);
  if (!label) return null;

  const parent = await deriveNameAccount(TLD, ROOT_ANS);
  const nameAccount = await deriveNameAccount(label, parent);
  const data = await fetchAccountData(rpc, nameAccount);
  if (!data || data.length < HEADER_SIZE) return null;

  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const expiresAt = Number(view.getBigUint64(EXPIRES_AT_OFFSET, true));
  if (expiresAt !== 0 && expiresAt * 1000 < Date.now()) return null;

  const owner = addressDecoder.decode(data.subarray(OWNER_OFFSET, OWNER_OFFSET + 32));

  // A tokenized domain records the nft_record PDA as owner; the real owner holds the NFT.
  const nftRecord = await deriveNftRecord(nameAccount, await deriveTldHouse());
  return owner === nftRecord ? resolveTokenizedOwner(rpc, nftRecord) : owner;
}

async function resolveTokenizedOwner(rpc: Rpc, nftRecord: Address): Promise<Address | null> {
  const data = await fetchAccountData(rpc, nftRecord);
  if (!data || data[8] !== 1) return null; // tag !== ActiveRecord
  const mint = addressDecoder.decode(data.subarray(74, 106));
  // Check the mint, not the holder's balance. getTokenLargestAccounts returns the 20 largest
  // holders, so a mint with a supply of 2 split between two accounts passes a balance check and
  // resolves to an arbitrary one of them. Requiring a supply of exactly one indivisible unit is
  // what makes "the largest holder" and "the owner" the same thing.
  const { value: supply } = await rpc.getTokenSupply(mint).send();
  if (supply.decimals !== 0 || BigInt(supply.amount) !== 1n) return null;

  const { value: largest } = await rpc.getTokenLargestAccounts(mint).send();
  if (!largest?.length) return null;

  const { value: holder } = await rpc
    .getAccountInfo(largest[0].address, { encoding: 'jsonParsed' })
    .send();
  const parsed = holder?.data as { parsed?: { info?: { owner?: string } } } | undefined;
  const ownerString = parsed?.parsed?.info?.owner;
  return ownerString ? address(ownerString) : null;
}

/** Reverse lookup. Returns every .skr name the address owns, sorted. */
export async function resolveSkrNames(rpc: Rpc, owner: Address): Promise<string[]> {
  const parent = await deriveNameAccount(TLD, ROOT_ANS);
  const tldHouse = await deriveTldHouse();

  const accounts = await rpc
    .getProgramAccounts(ANS_PROGRAM, {
      encoding: 'base64',
      // Just the expiry field. Enough to drop expired names in this same call, without
      // pulling 200-byte headers for every name the address holds.
      dataSlice: { offset: EXPIRES_AT_OFFSET, length: 8 },
      filters: [
        { memcmp: { offset: 8n, bytes: parent as string as Base58EncodedBytes, encoding: 'base58' } },
        {
          memcmp: {
            offset: BigInt(OWNER_OFFSET),
            bytes: owner as string as Base58EncodedBytes,
            encoding: 'base58',
          },
        },
      ],
    })
    .send();

  const now = Date.now();

  // Same expiry rule as the forward path: 0 is non-expiring, a past value is unregistered.
  // Skipping it would leave an expired name showing as somebody's display label.
  const live = accounts.filter(({ account }) => {
    const expiry = new Uint8Array(base64Encoder.encode(account.data[0]));
    if (expiry.length < 8) return false;
    const expiresAt = Number(
      new DataView(expiry.buffer, expiry.byteOffset, 8).getBigUint64(0, true),
    );
    return expiresAt === 0 || expiresAt * 1000 >= now;
  });

  // PDA derivation only — no network, so deriving these together is free.
  const reverseAccounts = await Promise.all(
    live.map(({ pubkey }) => deriveReverseAccount(pubkey, tldHouse)),
  );

  // One request per 100 names, in sequence, rather than one per name all at once. An address
  // can hold thousands of names and that count is chosen by whoever transferred them, so a
  // per-name fan-out is a burst an outsider gets to size — against your own RPC quota.
  const names: string[] = [];
  for (let i = 0; i < reverseAccounts.length; i += REVERSE_BATCH_SIZE) {
    const { value: batch } = await rpc
      .getMultipleAccounts(reverseAccounts.slice(i, i + REVERSE_BATCH_SIZE), {
        encoding: 'base64',
      })
      .send();

    for (const entry of batch) {
      if (!entry) continue;
      const data = new Uint8Array(base64Encoder.encode(entry.data[0]));
      if (data.length <= HEADER_SIZE) continue;
      const label = utf8Decoder.decode(data.subarray(HEADER_SIZE)).replace(/\0.*$/, '');
      if (label) names.push(`${label}${TLD}`);
    }
  }
  return names.sort();
}
```

## Usage

```typescript
import { address, createSolanaRpc } from '@solana/kit';
import { resolveSkrDomain, resolveSkrNames } from './skr';

// Always mainnet, whatever cluster the rest of the app targets.
const rpc = createSolanaRpc(process.env.SOLANA_MAINNET_RPC_URL!);

await resolveSkrDomain(rpc, 'alice.skr'); // Address, or null
await resolveSkrNames(rpc, address('5FHw...')); // ['alice.skr'], sorted
```

## Notes

**Not-found is `null`, never a throw.** A rejected promise from either function means the RPC
failed, so the two map cleanly onto a 404 and a 503. This is the main practical reason to prefer
this over `@onsol/tldparser`, which throws a `TypeError` for both cases indistinguishably.

**Forward lookup accepts either form.** `normalizeSkrName` strips a trailing `.skr`, trims, and
lowercases, so `"Alice.SKR"` and `"alice"` both work. It rejects anything with an interior dot,
including subdomains like `"a.alice.skr"` — those are a different derivation this resolver does
not implement, and quietly resolving them to the wrong account would be worse than refusing.

**Reverse lookup needs `getProgramAccounts`.** It is filtered down to one owner so the response
is tiny, but plenty of providers disable or rate-limit the method regardless. Confirm your
provider allows it before relying on the reverse direction, and keep it server-side.

**Reverse lookup batches its second read, and does not fan out.** The label for each name lives
in its own account, so a naive version issues one `getAccountInfo` per name in a single
`Promise.all`. How many names an address holds is not something you control — anyone can
transfer names to it — so that shape lets an outsider pick the size of a burst against your RPC
quota, by loading up an address and asking you to resolve it. The batched loop above is capped
at 100 addresses per request, one request at a time.

**Reverse lookup returns an array, sorted.** An address can own several `.skr` names, and the
on-chain order is not a ranking. Sorting is what stops the displayed name changing between
calls; take `[0]` only after sorting.

**A reverse-resolved name is not a claim about who an address is.** `.skr` names are
transferable, and a transfer needs nothing from the recipient — anyone can push a name onto any
wallet. Since `[0]` is just the lexicographically first name the address holds, a stranger can
decide what your UI calls a user by registering something that sorts early. Sorting makes the
label stable, not trustworthy. So:

- Render it **beside** the truncated address, never instead of it.
- Where the label stands in for identity — a payee, a counterparty, a moderation surface —
  prefer the owner's `MainDomain`, the name they picked themselves. This resolver does not
  implement it; that is `@onsol/tldparser`'s `getMainDomain`, which throws when the user has
  never set one (the common case), so treat that throw as "no main domain" and fall back to the
  address.

**Expiry.** `expiresAt` of `0` means non-expiring, which is what Seeker-issued `.skr` names
carry today. Both directions treat a past `expiresAt` as unregistered, with no grace period —
`@onsol/tldparser` instead keeps a name resolving for roughly 50 days past expiry. If you need
to match the SDK, or want to show "expires soon", return `expiresAt` rather than dropping it.

## Limits

The resolver covers the name-account path, which is all that Seeker `.skr` names use today. Two
gaps, both in AllDomains features `.skr` does not currently exercise:

- **Reverse lookup skips tokenized domains.** The `memcmp` on `owner` matches name accounts
  only, so a domain minted as an NFT and held in a wallet would not appear. As of writing, none
  of the ~120k `.skr` name accounts are tokenized, so this is latent rather than a live gap.
  Forward lookup does handle the case, via `resolveTokenizedOwner`.
- **No records, avatars, or `MainDomain`.** If you need a user's chosen primary domain or the
  ANS record set (avatar, socials), that is `@onsol/tldparser` territory. Note that
  `getMainDomain` throws when a user has never set one, which is the common case.

Reach for `@onsol/tldparser` for those, and see the caveats in
[server.md](server.md#onsoltldparser-alternative) before you do.
