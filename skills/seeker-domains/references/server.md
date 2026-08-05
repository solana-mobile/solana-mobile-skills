# Server implementation reference

Express implementation of `.skr` resolution using `@onsol/tldparser`. Adapt the routing to
whatever framework the project already uses — see [Other frameworks](#other-frameworks). The
resolution logic itself is framework-agnostic.

`.skr` names live on Solana **mainnet**, whatever cluster the app targets.

## Full Express code

```typescript
// backend/src/index.ts
import express, { Request, Response } from 'express';
import { Connection, PublicKey } from '@solana/web3.js';
import { TldParser } from '@onsol/tldparser';
import cors from 'cors';

const app = express();
const PORT = Number(process.env.PORT ?? 3000);

// Public endpoints are rate-limited and will not survive resolving a list view. Point this at
// a dedicated provider in production, and keep the key server-side.
const RPC_ENDPOINT = process.env.SOLANA_MAINNET_RPC_URL ?? 'https://api.mainnet-beta.solana.com';

// Initialize Solana connection and parser
const connection = new Connection(RPC_ENDPOINT);
const parser = new TldParser(connection);

// Middleware
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok' });
});

// Resolve .skr domain to wallet address
app.post('/api/resolve-domain', async (req: Request, res: Response) => {
  try {
    const { domain } = req.body;

    if (!domain || typeof domain !== 'string') {
      return res.status(400).json({ error: 'Domain name is required' });
    }

    // Remove .skr extension if present for lookup
    const domainName = domain.replace('.skr', '');
    
    // Look up domain owner
    const owner = await parser.getOwnerFromDomainTld(domainName);

    if (!owner) {
      return res.status(404).json({ error: 'Domain not found' });
    }

    res.json({ address: owner.toBase58() });
  } catch (error) {
    console.error('Error resolving domain:', error);
    res.status(500).json({ error: 'Failed to resolve domain' });
  }
});

// Reverse lookup: resolve wallet address to .skr domain
app.post('/api/resolve-address', async (req: Request, res: Response) => {
  try {
    const { address } = req.body;

    if (!address || typeof address !== 'string') {
      return res.status(400).json({ error: 'Wallet address is required' });
    }

    // Validate and convert address
    const publicKey = new PublicKey(address);
    
    // Get all .skr domains owned by this address
    const domains = await parser.getParsedAllUserDomainsFromTld(publicKey, 'skr');

    if (!domains || domains.length === 0) {
      return res.status(404).json({ error: 'No .skr domain found for this address' });
    }

    // Return the first .skr domain found
    const domainName = domains[0].domain;
    res.json({ domain: `${domainName}` });
  } catch (error) {
    console.error('Error resolving address:', error);
    res.status(500).json({ error: 'Failed to resolve address' });
  }
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
});
```

## Package Configuration

```json
{
  "name": "skr-backend",
  "version": "1.0.0",
  "scripts": {
    "dev": "ts-node src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@onsol/tldparser": "^0.6.7",
    "@solana/web3.js": "^1.98.4",
    "cors": "^2.8.5",
    "express": "^4.21.0"
  },
  "devDependencies": {
    "@types/cors": "^2.8.17",
    "@types/express": "^5.0.0",
    "@types/node": "^22.10.2",
    "ts-node": "^10.9.2",
    "typescript": "^5.7.2"
  }
}
```

## TypeScript Configuration

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
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

1. **RPC endpoint**: the public mainnet endpoint is fine for development. It will not survive a
   list view that resolves many addresses — use a dedicated provider in production and keep
   the key in server-side environment variables only.

2. **Forward lookup**: `parser.getOwnerFromDomainTld(name)` takes the name **without** the
   `.skr` suffix. Passing `alice.skr` returns nothing, which looks like "unregistered" rather
   than like a bug — strip the suffix before calling.

3. **Reverse lookup**: `parser.getParsedAllUserDomainsFromTld(publicKey, 'skr')` returns **all**
   `.skr` names owned by an address, in no meaningful order. Sort before taking one, or the
   displayed name will change between calls for multi-domain owners.

4. **Error handling**: 400 for invalid input, 404 for a genuine "no domain registered", 503 for
   RPC failures. Do not collapse RPC failures into 404 — an outage would then look like every
   user having no name.

5. **Validate before calling RPC**: reject malformed base58 addresses and non-`.skr` domains up
   front so bad input does not consume RPC quota.

6. **CORS**: open CORS is for local development. Restrict `origin` to known callers before
   deploying.

7. **Cache**: names change rarely. A short-TTL in-memory cache, keyed on the address or name,
   removes most repeated RPC calls — this is the main reason to proxy rather than resolve from
   the client.

## Other frameworks

Only the routing changes; `TldParser` usage is identical.

| Framework | Where the routes go |
| --- | --- |
| Fastify | `fastify.post('/api/resolve-domain', handler)` |
| NestJS | A controller plus an injectable service holding the parser |
| Hono | `app.post('/api/resolve-domain', handler)` |
| Koa | Router middleware |
| Next.js | Route handlers at `app/api/resolve-domain/route.ts` |

Construct the `Connection` and `TldParser` **once** at module scope, not per request. Building
them per request adds latency and, on some providers, trips connection limits.
