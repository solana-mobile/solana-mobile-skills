---
name: seeker-domains
description: Resolve and display .skr domain names in Solana mobile apps, in both directions between names and wallet addresses. Use when showing .skr names instead of wallet addresses in profiles, friend lists, or transaction history, resolving a .skr domain to an address, reverse-looking-up an address to a domain, or validating .skr input.
---

# .skr domain resolution

`.skr` domains are AllDomains names on Solana mainnet. Seeker users get one by default, which
makes them a good substitute for truncated addresses in a UI.

Two directions:

- **Forward** — `alice.skr` to a wallet address
- **Reverse** — a wallet address to the `.skr` names it owns

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

The library is framework-agnostic; only the routing around it changes.

```bash
npm install @onsol/tldparser @solana/web3.js
```

```ts
import { TldParser } from '@onsol/tldparser'
import { Connection } from '@solana/web3.js'

const connection = new Connection(process.env.SOLANA_MAINNET_RPC_URL, 'confirmed')
const parser = new TldParser(connection)

// Forward: name to address. Pass the name WITHOUT the .skr suffix.
const owner = await parser.getOwnerFromDomainTld('alice')

// Reverse: address to names.
const domains = await parser.getParsedAllUserDomainsFromTld(publicKey, 'skr')
```

Two things to get right:

- **`getOwnerFromDomainTld` takes the bare name**, not `alice.skr`. Passing the full domain
  returns nothing, which reads as "unregistered" rather than as a bug.
- **Reverse lookup returns an array.** An address can own several `.skr` names, and the order
  is not a ranking. Pick deterministically — sort and take the first — or the displayed name
  will change between calls.

## API shape

Two endpoints, adapted to whatever framework is in use:

| Route | Body | Success | Not found |
| --- | --- | --- | --- |
| `POST /api/resolve-domain` | `{ domain: "alice.skr" }` | `{ address }` | 404 |
| `POST /api/resolve-address` | `{ address: "5FHw..." }` | `{ domain }` | 404 |

Validate input before touching RPC: reject a malformed base58 address or a domain that does
not end in `.skr` with a 400, so bad input does not consume RPC quota.

Distinguish "no domain registered" (404) from "RPC failed" (503). Collapsing both into 404
makes an outage look like every user having no name.

Full Express implementation, plus notes for Fastify, NestJS, Hono, and Next.js route
handlers: [references/server.md](references/server.md).

## Client integration

```ts
const { data: domain } = useResolveAddress(account?.address)
const label = domain ?? ellipsify(account?.address)
```

Always fall back to a truncated address. A name that fails to resolve should degrade to
something usable, never to a blank space or a spinner that never resolves.

Cache results — `@tanstack/react-query` with a long `staleTime` is enough, since names change
rarely.

For an Android emulator, `localhost` is the emulator itself. Reach the host machine at
`http://10.0.2.2:3000`. On a physical device use the host's LAN IP. Hard-coding either into
source is what breaks the app for the next person — read it from
`EXPO_PUBLIC_API_URL`.

Hook, components, and the truncation helper: [references/client.md](references/client.md).

## Reference material

- [references/server.md](references/server.md) — Express implementation, other frameworks,
  validation and error handling
- [references/client.md](references/client.md) — resolution hook, display components,
  emulator networking

## Related skills

- `solana-mobile-wallet` — the wallet connection supplying the address to resolve
- `seeker-genesis-token` — verifying Seeker ownership

## Links

- AllDomains developer guide: https://docs.alldomains.id/protocol/developer-guide/ad-sdks/svm-sdks/solana-mainnet-sdk
- `@onsol/tldparser`: https://www.npmjs.com/package/@onsol/tldparser
