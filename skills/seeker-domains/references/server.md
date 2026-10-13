# Server implementation reference

Express implementation of `.skr` resolution. Adapt the routing to whatever framework the project
already uses — see [Other frameworks](#other-frameworks). The resolution logic itself is
framework-agnostic.

`.skr` names live on Solana **mainnet**, whatever cluster the app targets.

Resolution comes from [`@solana-mobile/skr-domain`](https://www.npmjs.com/package/@solana-mobile/skr-domain).
Its functions return `null` (or `[]`) for not-found and only reject when the RPC fails, which is
what the 404/503 split below relies on.

## Full Express code

This proxy exists to keep an RPC key off user devices. That only holds if the proxy is not
itself an open relay in front of that key: the reverse route costs a `getProgramAccounts` plus
a batched read of every name the address owns when the wallet has no primary name, so an unthrottled, uncached endpoint hands anyone
who finds the URL a free way to burn the quota you were protecting. Origin allowlist, rate
limit, cache, and body limit are all part of the sample for that reason.

```typescript
// backend/src/index.ts
import express, { NextFunction, Request, Response } from 'express';
import { address, createSolanaRpc, type Address } from '@solana/kit';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { LRUCache } from 'lru-cache';
import { getPrimarySkrDomain, getSkrDomains, normalizeSkrName, resolveSkrDomain } from '@solana-mobile/skr-domain';

const app = express();
const PORT = Number(process.env.PORT ?? 3000);
const IS_PROD = process.env.NODE_ENV === 'production';

// No public-endpoint fallback. This server's whole job is to hold the key, so an unset env var
// is a broken deploy — fail at startup rather than quietly serving from the public endpoint
// until its rate limits make it look like every user has no name. The reverse route needs
// getProgramAccounts, which some providers disable; check before deploying.
const RPC_ENDPOINT = process.env.SOLANA_MAINNET_RPC_URL;
if (!RPC_ENDPOINT) {
  throw new Error('SOLANA_MAINNET_RPC_URL is required');
}

// Build the RPC client once at module scope, not per request.
const rpc = createSolanaRpc(RPC_ENDPOINT);

// Comma-separated, e.g. "https://app.example.com,https://staging.example.com".
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

if (IS_PROD && ALLOWED_ORIGINS.length === 0) {
  throw new Error('ALLOWED_ORIGINS is required in production');
}

app.use(
  cors({
    origin: (origin, callback) =>
      // A missing Origin is a native app or a server-side caller, which CORS does not police
      // either way — the rate limit is what covers those. A browser Origin must be listed.
      !origin || ALLOWED_ORIGINS.includes(origin)
        ? callback(null, true)
        : callback(new Error('Origin not allowed')),
  }),
);

// Both routes carry one short string. Express's 100kb default lets a caller push megabytes at
// the JSON parser before any of your code runs.
app.use(express.json({ limit: '1kb' }));

// Per-IP ceiling on the RPC spend. Tune to your provider's quota, not to what feels polite.
// Behind a load balancer this needs `app.set('trust proxy', <hops>)` to see the real client
// IP — see note 8.
app.use(
  '/api',
  rateLimit({
    windowMs: 60_000,
    limit: 60,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
  }),
);

// The forward direction caches misses ONLY, and never a resolved address. A forward result is
// a payment destination, and the client is told to re-resolve at send time — which comes back
// through this same route, so serving it a cached address would reintroduce the stale-payee bug
// the client-side rule exists to prevent. Caching misses still blunts the cheap abuse, which is
// walking through unregistered names to miss the cache on every request.
//
// Reverse results are display labels, so they cache normally, boxed because LRUCache's value
// type is `V extends {}` and rejects null, and because a miss and a cached "no name" have to
// stay distinguishable. See notes 5 and 6.
const forwardMissCache = new LRUCache<string, true>({ max: 10_000, ttl: 60_000 });
const reverseCache = new LRUCache<string, { domain: string | null }>({
  max: 10_000,
  ttl: 3_600_000,
});

app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

// express.json() leaves req.body undefined unless the Content-Type is JSON, so destructuring it
// straight away turns an ordinary bad request into a 500 — and on Express 4, into an unhandled
// rejection. Read fields defensively instead.
function readStringField(body: unknown, field: string): string | null {
  if (typeof body !== 'object' || body === null) return null;
  const value = (body as Record<string, unknown>)[field];
  return typeof value === 'string' ? value : null;
}

// Resolve .skr domain to wallet address
app.post('/api/resolve-domain', async (req: Request, res: Response) => {
  const domain = readStringField(req.body, 'domain');

  if (!domain) {
    return res.status(400).json({ error: 'Domain name is required' });
  }

  // Reject malformed input before spending RPC quota on it. The normalised label doubles as the
  // cache key, so "Alice.SKR" and "alice" are one entry rather than two.
  let label: string;
  try {
    label = normalizeSkrName(domain);
  } catch {
    return res.status(400).json({ error: 'Not a valid .skr domain' });
  }

  if (forwardMissCache.has(label)) {
    return res.status(404).json({ error: 'Domain not found' });
  }

  try {
    const resolved = await resolveSkrDomain(rpc, label);

    // null is a genuine "not registered". A throw means the RPC failed — see below.
    if (!resolved) {
      forwardMissCache.set(label, true);
      return res.status(404).json({ error: 'Domain not found' });
    }

    // Deliberately not cached — see the cache declarations above.
    res.json({ address: resolved.owner });
  } catch (error) {
    // Also not cached: caching an outage turns a blip into a TTL of wrong answers.
    console.error('RPC failure resolving domain:', error);
    res.status(503).json({ error: 'Resolution temporarily unavailable' });
  }
});

// Reverse lookup: resolve wallet address to .skr domain
app.post('/api/resolve-address', async (req: Request, res: Response) => {
  const input = readStringField(req.body, 'address');

  if (!input) {
    return res.status(400).json({ error: 'Wallet address is required' });
  }

  // address() throws on malformed base58, so validate separately from the RPC call to keep
  // bad input a 400 rather than a 503.
  let owner: Address;
  try {
    owner = address(input);
  } catch {
    return res.status(400).json({ error: 'Invalid wallet address' });
  }

  const cached = reverseCache.get(owner);
  if (cached) {
    return cached.domain
      ? res.json({ domain: cached.domain })
      : res.status(404).json({ error: 'No .skr domain found for this address' });
  }

  try {
    // The name the wallet chose, else the first name it owns. getSkrDomains is sorted, so the
    // fallback is stable across calls for multi-domain owners.
    const domain =
      (await getPrimarySkrDomain(rpc, owner)) ?? (await getSkrDomains(rpc, owner))[0] ?? null;
    reverseCache.set(owner, { domain });

    if (!domain) {
      return res.status(404).json({ error: 'No .skr domain found for this address' });
    }

    res.json({ domain });
  } catch (error) {
    console.error('RPC failure resolving address:', error);
    res.status(503).json({ error: 'Resolution temporarily unavailable' });
  }
});

// Without this, a rejected origin and an oversized body both come back as a 500 with a stack
// trace in the body.
app.use((err: unknown, _req: Request, res: Response, next: NextFunction) => {
  if (res.headersSent) return next(err);
  if (err instanceof Error && err.message === 'Origin not allowed') {
    return res.status(403).json({ error: 'Origin not allowed' });
  }
  // express.json() attaches its own status: 413 for too large, 400 for malformed JSON.
  const status = (err as { status?: number } | null)?.status ?? 500;
  if (status === 500) console.error('Unhandled error:', err);
  res.status(status).json({ error: status === 500 ? 'Internal error' : 'Bad request' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});
```

Required environment: `SOLANA_MAINNET_RPC_URL` always, and `ALLOWED_ORIGINS` whenever
`NODE_ENV=production`. Both throw at startup when missing, so a misconfigured deploy fails
visibly instead of degrading.

## Package Configuration

```json
{
  "name": "skr-backend",
  "version": "1.0.0",
  "type": "module",
  "engines": {
    "node": ">=20.18.0"
  },
  "scripts": {
    "dev": "tsx src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@solana-mobile/skr-domain": "^1.1.0",
    "@solana/kit": "^8.0.0",
    "cors": "^2.8.5",
    "express": "^5.2.1",
    "express-rate-limit": "^8.7.0",
    "lru-cache": "^11.5.2"
  },
  "devDependencies": {
    "@types/cors": "^2.8.17",
    "@types/express": "^5.0.0",
    "@types/node": "^22.10.2",
    "tsx": "^4.19.2",
    "typescript": "^5.7.2"
  }
}
```

Express is pinned to `^5`, which is what `npm install express` resolves to — 4.x now sits
behind the `latest-4` tag. The sample runs unchanged on either: every route is a literal path,
so none of Express 5's `path-to-regexp` changes apply, and `express-rate-limit` declares
`express >= 4.11`. `@types/express@^5` is the matching major.

The project is ESM (`"type": "module"`, `"module": "nodenext"`) because `@solana-mobile/skr-domain`
ships ESM only, and on Node 20.18 or later because that is the package's declared minimum.

## TypeScript Configuration

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "nodenext",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

## Key implementation notes

1. **RPC endpoint**: required, with no fallback. The public mainnet endpoint is fine for
   development, but set it explicitly — a silent fallback means a deploy that lost its env var
   keeps answering, from a rate-limited endpoint, until it looks like every user has no name.
   Use a dedicated provider in production and keep the key in server-side environment variables
   only.

2. **Forward lookup**: `resolveSkrDomain` accepts `alice.skr` or `alice`, and returns
   `{ owner, nameAccount, expiresAt }`, or `null` when the name is unregistered or expired.
   Validate with `normalizeSkrName` first — it throws on malformed input — so bad input is a 400
   rather than a wasted RPC round trip.

3. **Reverse lookup**: `getPrimarySkrDomain` returns the name the wallet chose, or `null`. Most
   wallets never choose one, so fall back to `getSkrDomains`, which returns **all** live `.skr`
   names owned by an address, sorted; take `[0]`. `getSkrDomains` relies on
   `getProgramAccounts`, which some providers restrict — verify yours supports it.

4. **Error handling**: 400 for invalid input, 404 for a genuine "no domain registered", 503 for
   RPC failures. The package makes this easy: `null` is not-found, a rejected promise is an
   outage. Do not collapse RPC failures into 404 — an outage would then look like every user
   having no name.

5. **Cache**: names change rarely, and caching is the main reason to proxy rather than resolve
   from the client. Two things the obvious version gets wrong. Cache **negative** results, or a
   caller walking through unregistered names reaches the RPC on every request and the cache
   buys nothing exactly when you need it. And do **not** cache RPC failures — a rejected promise
   is an outage, and storing it turns a momentary blip into a full TTL of confidently wrong
   404s.

6. **What you cache depends on the direction, and the forward direction caches nothing
   positive.** Reverse results (address → name) are display labels; a stale one is a cosmetic
   bug, so an hour is fine. Forward results (name → address) end up as payment destinations, and
   `.skr` names are transferable and re-registrable — so a cached one pays whoever owned the
   name when it was cached. Shortening that TTL is not enough, because the client is told to
   re-resolve at send time and that re-resolution arrives *on this route*: any positive forward
   cache silently answers it from the same stale entry the rule exists to avoid. So the sample
   caches forward **misses** only and always resolves a real name for real. The client side of
   this is in [client.md](client.md#caching-by-direction).

7. **CORS**: the allowlist comes from `ALLOWED_ORIGINS` and is mandatory under
   `NODE_ENV=production`. `cors()` with no options reflects any origin, which makes the proxy
   usable from any page on the internet — the exact thing that turns a key-protection layer into
   a free relay for the key. A request with no `Origin` header (a native app, a server-side
   caller, curl) is allowed through, because CORS never restricted those in the first place;
   the rate limit is what covers them.

8. **Rate limit and body limit**: `express-rate-limit` caps the per-IP RPC spend, and
   `express.json({ limit: '1kb' })` stops a caller pushing megabytes through the JSON parser
   before any handler runs. Behind a proxy or load balancer, every request appears to come from
   the proxy's IP and one client exhausts the limit for everyone — set
   `app.set('trust proxy', <number of hops>)` to the count of proxies you actually control.
   Never `app.set('trust proxy', true)`: it takes the client's own `X-Forwarded-For` at face
   value, and rotating that header is a one-line bypass.

## Hono

Same five controls, rather less ceremony: `hono/cors` and `hono/body-limit` are built in, and
the whole thing is runtime-agnostic. Reasonable choice for a greenfield proxy. Express stays the
reference above because it is the shape most existing Node backends already have, and because
`express-rate-limit` is considerably more settled than `hono-rate-limiter`, which is still
pre-1.0 — and the rate limit is the control that actually stops the abuse this proxy invites.

**One trap, and it is the reason this sample is longer than you would expect.** `hono/cors` only
*sets response headers*; it does not reject a disallowed origin, because CORS is a browser
mechanism. `curl` and every server-side caller walk straight past it. Express's `cors` package
happens to block, because its origin callback can raise, and that difference is easy to carry
over by accident. If you want the allowlist enforced, write the check yourself.

```typescript
// backend/src/index.ts
import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { getConnInfo } from '@hono/node-server/conninfo';
import { bodyLimit } from 'hono/body-limit';
import { cors } from 'hono/cors';
import { rateLimiter } from 'hono-rate-limiter';
import { address, createSolanaRpc, type Address } from '@solana/kit';
import { LRUCache } from 'lru-cache';
import { getPrimarySkrDomain, getSkrDomains, normalizeSkrName, resolveSkrDomain } from '@solana-mobile/skr-domain';

const PORT = Number(process.env.PORT ?? 3000);
const IS_PROD = process.env.NODE_ENV === 'production';

// Same rule as the Express version: no public-endpoint fallback, because a server whose job is
// to hold the key should fail visibly when it has not been given one.
const RPC_ENDPOINT = process.env.SOLANA_MAINNET_RPC_URL;
if (!RPC_ENDPOINT) {
  throw new Error('SOLANA_MAINNET_RPC_URL is required');
}

const rpc = createSolanaRpc(RPC_ENDPOINT);

const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS ?? '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

if (IS_PROD && ALLOWED_ORIGINS.length === 0) {
  throw new Error('ALLOWED_ORIGINS is required in production');
}

// Forward: misses only, never a resolved address — it is a payment destination, and the client
// re-resolves at send time through this same route. Reverse: display labels, so cached normally.
const forwardMissCache = new LRUCache<string, true>({ max: 10_000, ttl: 60_000 });
const reverseCache = new LRUCache<string, { domain: string | null }>({
  max: 10_000,
  ttl: 3_600_000,
});

const app = new Hono();

app.get('/health', (c) => c.json({ status: 'ok' }));

// hono/cors sets response headers; it does NOT reject a disallowed origin, because CORS is a
// browser mechanism. Curl and any server-side caller sail straight past it. So the allowlist is
// enforced here, as an explicit 403, and cors() below only produces the browser-facing headers.
app.use('/api/*', async (c, next) => {
  const origin = c.req.header('Origin');
  if (origin && !ALLOWED_ORIGINS.includes(origin)) {
    return c.json({ error: 'Origin not allowed' }, 403);
  }
  return next();
});

app.use(
  '/api/*',
  cors({
    origin: (origin) => (ALLOWED_ORIGINS.includes(origin) ? origin : null),
  }),
);

// Both routes carry one short string.
app.use(
  '/api/*',
  bodyLimit({
    maxSize: 1024,
    onError: (c) => c.json({ error: 'Body too large' }, 413),
  }),
);

// Per-IP ceiling on the RPC spend. getConnInfo comes from the Node adapter; on another runtime
// use that runtime's adapter, and behind a proxy key on the forwarded header you control.
app.use(
  '/api/*',
  rateLimiter({
    windowMs: 60_000,
    limit: 60,
    standardHeaders: 'draft-7',
    keyGenerator: (c) => getConnInfo(c).remote.address ?? 'unknown',
  }),
);

app.post('/api/resolve-domain', async (c) => {
  const body = await c.req.json().catch(() => null);
  const domain = (body as { domain?: unknown } | null)?.domain;

  if (typeof domain !== 'string') {
    return c.json({ error: 'Domain name is required' }, 400);
  }

  let label: string;
  try {
    label = normalizeSkrName(domain);
  } catch {
    return c.json({ error: 'Not a valid .skr domain' }, 400);
  }

  if (forwardMissCache.has(label)) {
    return c.json({ error: 'Domain not found' }, 404);
  }

  try {
    const resolved = await resolveSkrDomain(rpc, label);
    if (!resolved) {
      forwardMissCache.set(label, true);
      return c.json({ error: 'Domain not found' }, 404);
    }
    return c.json({ address: resolved.owner });
  } catch (error) {
    console.error('RPC failure resolving domain:', error);
    return c.json({ error: 'Resolution temporarily unavailable' }, 503);
  }
});

app.post('/api/resolve-address', async (c) => {
  const body = await c.req.json().catch(() => null);
  const input = (body as { address?: unknown } | null)?.address;

  if (typeof input !== 'string') {
    return c.json({ error: 'Wallet address is required' }, 400);
  }

  let owner: Address;
  try {
    owner = address(input);
  } catch {
    return c.json({ error: 'Invalid wallet address' }, 400);
  }

  const cached = reverseCache.get(owner);
  if (cached) {
    return cached.domain
      ? c.json({ domain: cached.domain })
      : c.json({ error: 'No .skr domain found for this address' }, 404);
  }

  try {
    const domain =
      (await getPrimarySkrDomain(rpc, owner)) ?? (await getSkrDomains(rpc, owner))[0] ?? null;
    reverseCache.set(owner, { domain });
    return domain
      ? c.json({ domain })
      : c.json({ error: 'No .skr domain found for this address' }, 404);
  } catch (error) {
    console.error('RPC failure resolving address:', error);
    return c.json({ error: 'Resolution temporarily unavailable' }, 503);
  }
});

serve({ fetch: app.fetch, port: PORT }, ({ port }) => {
  console.log(`🚀 Server running on http://localhost:${port}`);
});
```

```json
{
  "name": "skr-backend",
  "private": true,
  "type": "module",
  "dependencies": {
    "@hono/node-server": "^2.1.1",
    "@solana-mobile/skr-domain": "^1.1.0",
    "@solana/kit": "^8.0.0",
    "hono": "^4.13.5",
    "hono-rate-limiter": "^0.5.3",
    "lru-cache": "^11.5.2"
  },
  "devDependencies": {
    "@types/node": "^22.10.2",
    "typescript": "^5.7.2"
  }
}
```

Notes specific to this version:

- **`getConnInfo` is adapter-specific.** It is imported from `@hono/node-server/conninfo` here.
  On another runtime, import it from that runtime's adapter; behind a proxy, key the limiter on
  a forwarded header you control rather than the socket address.
- **On Workers or Deno Deploy, revisit the cache.** An in-memory `LRUCache` is per-isolate and
  ephemeral there, so the hit rate collapses — and a shared cache is the main reason to run this
  proxy at all. Use KV or the Cache API, and Cloudflare's rate-limiting binding in place of
  `hono-rate-limiter`. `hono/cache` is Web Cache API based and is not available on Node.
- **`c.req.json()` rejects on a malformed body**, hence the `.catch(() => null)` and the
  explicit type check, which is also what keeps bad input a 400 rather than a 500.
- **It also ignores `Content-Type`**, which is where the two samples genuinely diverge. Hono
  parses the body whatever the header says, so a valid JSON body sent as `text/plain` is
  answered normally; `express.json()` refuses to parse it and the Express sample returns a 400.
  Neither leaks a 500, so this is a difference in leniency, not in safety — but do not assume
  the two are byte-for-byte interchangeable in their responses.

## Other frameworks

Only the routing changes; the package calls are identical.

| Framework | Where the routes go |
| --- | --- |
| Fastify | `fastify.post('/api/resolve-domain', handler)` |
| Hono | [Full sample above](#hono) |
| Koa | Router middleware |
| NestJS | A controller plus an injectable service holding the RPC client |
| Next.js | Route handlers at `app/api/resolve-domain/route.ts` |

Construct the RPC client **once** at module scope, not per request. Building it per request adds
latency and, on some providers, trips connection limits.
