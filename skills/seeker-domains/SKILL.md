---
name: seeker-domains
description: Resolve and display .skr domain names in Solana mobile apps, in both directions between names and wallet addresses. Use when showing .skr names instead of wallet addresses in profiles, friend lists, or transaction history, resolving a .skr domain to an address, reverse-looking-up an address to a domain, or validating .skr input.
---

# .skr domain resolution

`.skr` domains are AllDomains names on Solana mainnet. Seeker users get one by default, which
makes them a good substitute for truncated addresses in a UI.

Two directions:

- **Forward** — `alice.skr` to a wallet address
- **Reverse** — a wallet address to a `.skr` name: its primary name, or else one it owns

Both live on **mainnet**, regardless of which cluster the rest of the app targets. An app on
devnet still resolves names against mainnet.

## Decide where resolution runs

Resolution reads public on-chain data, so a client can do it directly. Proxy it through a
backend when you want:

- **RPC key protection.** A key in `EXPO_PUBLIC_*` is readable by anyone with the APK. If you
  use a paid RPC, it has to be server-side.
- **Shared caching.** Names change rarely. One server-side cache beats every client
  re-resolving the same addresses.
- **Batch lookups.** Resolving a whole friend list in one request beats N round trips from a
  phone.
- **`getProgramAccounts` access.** Reverse lookup needs it, and plenty of providers disable or
  heavily rate-limit the method. One server-side endpoint against a provider you have checked
  beats discovering the restriction on user devices.

Direct client-side resolution against a public RPC is reasonable for a prototype or a
low-traffic app. Public endpoints are rate-limited, so it will not survive a list view that
resolves dozens of addresses.

Ask which the user wants if it is not obvious from the project. Default to the proxy for
anything heading to production.

## Integrating with an existing backend

**Check what exists before writing a new server.** Adding an Express app beside someone's
NestJS service is a mess to maintain.

1. Look for backend dependencies in every `package.json` — `express`, `fastify`, `hono`,
   `@nestjs/core`, `koa`, or a Next.js app with API routes.
2. Look for entry points: `server.ts`, `app.ts`, `main.ts`, `index.ts`.
3. Look for route organisation: `routes/`, `api/`, `controllers/`.
4. Ask if it is still ambiguous — "I see a Fastify server in `apps/api`; should the `.skr`
   endpoints go there?"

Add routes to what exists, matching its conventions for routing, validation, and error
handling. Only scaffold a minimal server when there is genuinely no backend.

## Core resolution logic

Use [`@solana-mobile/skr-domain`](https://www.npmjs.com/package/@solana-mobile/skr-domain). Do
not copy a resolver into the project or reach for another SDK: the package is maintained by
Solana Mobile, built on `@solana/kit`, and covers both directions. Resolution is
framework-agnostic; only the routing around it changes.

```bash
npm install @solana-mobile/skr-domain @solana/kit
```

```ts
import { getPrimarySkrDomain, getSkrDomains, normalizeSkrName, resolveSkrDomain } from '@solana-mobile/skr-domain'
import { address, createSolanaRpc } from '@solana/kit'

// Always mainnet, whatever cluster the rest of the app targets.
const rpc = createSolanaRpc(process.env.SOLANA_MAINNET_RPC_URL!)

// Forward: { owner, nameAccount, expiresAt }, or null when unregistered or expired.
const domain = await resolveSkrDomain(rpc, 'alice.skr')

// Reverse: the name the wallet chose, else the first name it owns (sorted), else null.
const wallet = address('5FHw...')
const name = (await getPrimarySkrDomain(rpc, wallet)) ?? (await getSkrDomains(rpc, wallet))[0] ?? null
```

What the package does, so you do not re-implement it:

- **Not-found is `null` (or `[]`), never a throw.** A rejection means the RPC failed, so the two
  map cleanly onto a 404 and a 503.
- **Invalid input throws a plain `Error`.** `normalizeSkrName` accepts `alice`, `Alice.skr` and
  `' alice '`, and throws for subdomains, other TLDs, or an empty label. Call it inside a
  `try`/`catch` to turn bad input into a 400 before spending RPC quota.
- **Expired names resolve as unregistered**, in both directions, with no grace period.
- **`getPrimarySkrDomain` re-checks ownership.** A `MainDomain` account is not updated on
  transfer, so the package resolves the name forward and only returns it if the wallet still owns
  it.
- **`getSkrDomains` uses `getProgramAccounts`**, which many providers disable or rate-limit. It
  reads labels in batches of 100, one request at a time, so a wallet stuffed with names cannot
  set the size of a burst against your quota.
- **NFT-wrapped names are out of scope.** None exist under `.skr` today; `resolveSkrDomain`
  throws if one appears.

**React Native needs a WebCrypto polyfill.** Deriving a name address calls
`crypto.subtle.digest`, which Hermes lacks. Install `react-native-quick-crypto` and call its
`install()` at startup, before the package is imported. Node 20.18+, Bun and browsers need nothing.

**The package is ESM-only.** A CommonJS server needs `"type": "module"` (or Node 22.12+, which can
`require()` ES modules).

For ANS records or avatars, which the package does not cover, use the AllDomains SDK — see the
links below.

## API shape

Two endpoints, adapted to whatever framework is in use:

| Route | Body | Success | Not found |
| --- | --- | --- | --- |
| `POST /api/resolve-domain` | `{ domain: "alice.skr" }` | `{ address }` | 404 |
| `POST /api/resolve-address` | `{ address: "5FHw..." }` | `{ domain }` | 404 |

Validate input before touching RPC: reject a malformed base58 address or a name that
`normalizeSkrName` rejects with a 400, so bad input does not consume RPC quota.

Distinguish "no domain registered" (404) from "RPC failed" (503). Collapsing both into 404
makes an outage look like every user having no name.

A proxy that exists to protect an RPC key has to not be an open relay in front of it. The
reverse route costs up to two `getAccountInfo` calls, a `getProgramAccounts`, and a batched read
of every name the address owns, so the endpoint needs an origin allowlist, a per-IP rate limit, a
body limit, and a cache that also stores negative results. Require the RPC URL and the origin
list at startup rather than falling back to the public endpoint or to open CORS.

Full Express and Hono implementations, plus notes for Fastify, NestJS, Koa, and Next.js
route handlers: [references/server.md](references/server.md).

## Client integration

```ts
const { data: domain } = useResolveAddress(account?.address)
const label = domain ?? ellipsify(account?.address)
```

Always fall back to a truncated address. A name that fails to resolve should degrade to
something usable, never to a blank space or a spinner that never resolves.

For an Android emulator, `localhost` is the emulator itself. Reach the host machine at
`http://10.0.2.2:3000`. On a physical device use the host's LAN IP. Hard-coding either into
source is what breaks the app for the next person — read it from `EXPO_PUBLIC_API_URL`, and
gate any emulator fallback on `__DEV__`: `EXPO_PUBLIC_*` is inlined at build time, so an
ungated default ships a dead cleartext URL in the release APK, which Android blocks by default
anyway. Nothing with an RPC key belongs in an `EXPO_PUBLIC_*` variable at all — that is what
the proxy is for.

The snippet above assumes the proxy. If you resolve directly from the app instead, the package
runs under Hermes once the WebCrypto polyfill is installed — call it from the same hook in place
of `fetch`.

Hook, components, and the truncation helper: [references/client.md](references/client.md).

### Trusting a reverse-resolved name

The primary name is one the wallet chose. A name from `getSkrDomains` is not: a `.skr` transfer
needs nothing from the recipient, so anyone can push a name onto any wallet, and a stranger can
decide what your UI calls a user without a primary name by sending one that sorts early.

- **Prefer `getPrimarySkrDomain`**, and fall back to `getSkrDomains` only for display.
- **Show the name beside the truncated address, not instead of it.** The address is the part
  a user can actually check.
- **Where the label stands in for identity** — a payee, a counterparty, a moderation surface —
  use the primary name only, and fall back to the address.

### Cache by direction

| Direction | Feeds | Cache |
| --- | --- | --- |
| Forward (name → address) | Payment destinations | None. Re-resolve at send time. |
| Reverse (address → name) | Display labels | Long `staleTime`; an hour is fine. |

Names change rarely, so caching reverse results is nearly free. Forward results are different:
`.skr` names are transferable and re-registrable, so a forward result cached for an hour and
then used to build a transfer pays whoever owned the name an hour ago, with nothing in the UI
looking wrong. Re-resolve immediately before signing, and put the resolved address in the
confirmation step so the user sees where the funds are actually going.

That has to hold on **both** sides. A client that re-resolves at send time gets nothing if the
proxy answers from its own forward cache, so the server caches forward misses only and never a
resolved address.

## Reference material

- [references/server.md](references/server.md) — Express and Hono implementations, other
  frameworks, validation and error handling
- [references/client.md](references/client.md) — resolution hook, display components,
  emulator networking

## Related skills

- `solana-mobile-wallet` — the wallet connection supplying the address to resolve
- `seeker-genesis-token` — verifying Seeker ownership

## Links

- `@solana-mobile/skr-domain`: https://www.npmjs.com/package/@solana-mobile/skr-domain
- `@solana-mobile/skr-domain` source and README: https://github.com/solana-mobile/skr-js/tree/main/packages/skr-domain
- AllDomains developer guide: https://docs.alldomains.id/protocol/developer-guide/ad-sdks/svm-sdks/solana-mainnet-sdk
- `@solana/kit`: https://www.npmjs.com/package/@solana/kit
