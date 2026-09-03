# Frontend Implementation Reference

React Native implementation for .skr domain resolution with Mobile Wallet Adapter integration.

## Framework Note

This reference shows React Native implementation. **For other frontends**, the same pattern applies—you're simply making two API calls to the backend:

- `POST /api/resolve-domain` with `{ domain: "alice.skr" }` → returns `{ address: "..." }`
- `POST /api/resolve-address` with `{ address: "5FHw..." }` → returns `{ domain: "alice.skr" }`

Adapt this to your frontend framework:
- **React (web)**: Use `fetch` or `axios` in a custom hook
- **Vue**: Use composables with `fetch`
- **Svelte**: Use stores or `fetch` in `onMount`
- **Angular**: Use HttpClient in a service
- **Plain JS**: Use `fetch` directly

The core logic is identical—just HTTP POST requests to your backend.

## Domain Resolution Hook

Create a custom hook to handle API calls to the backend:

```typescript
// hooks/use-domain-lookup.ts
import { useState } from 'react';

// 10.0.2.2 is the Android emulator's alias for the host machine's localhost. Set
// EXPO_PUBLIC_API_URL per environment rather than committing either value.
//
// The fallback is gated on __DEV__ deliberately. EXPO_PUBLIC_* is inlined at build time, so an
// ungated default compiles the emulator's cleartext URL straight into the release APK, where it
// resolves to nothing and Android's default network security config blocks cleartext anyway.
// Better to fail loudly at startup than to ship an app whose lookups silently never work.
const API_BASE_URL = process.env.EXPO_PUBLIC_API_URL ?? (__DEV__ ? 'http://10.0.2.2:3000' : '');

if (!API_BASE_URL) {
  throw new Error('EXPO_PUBLIC_API_URL must be set for release builds');
}

interface DomainLookupResult {
  address?: string;
  domain?: string;
  error?: string;
}

export function useDomainLookup() {
  const [loading, setLoading] = useState(false);

  /**
   * Resolve .skr domain to wallet address
   * @param domain - Domain name (with or without .skr extension)
   * @returns Wallet address or error
   */
  const resolveDomain = async (domain: string): Promise<DomainLookupResult> => {
    setLoading(true);
    try {
      const response = await fetch(`${API_BASE_URL}/api/resolve-domain`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ domain }),
      });

      if (!response.ok) {
        const error = await response.json();
        return { error: error.error || 'Failed to resolve domain' };
      }

      const data = await response.json();
      return { address: data.address };
    } catch (error) {
      console.error('Error resolving domain:', error);
      return { error: 'Network request failed' };
    } finally {
      setLoading(false);
    }
  };

  /**
   * Reverse lookup: resolve wallet address to .skr domain
   * @param address - Solana wallet address (base58)
   * @returns .skr domain name or error
   */
  const resolveAddress = async (address: string): Promise<DomainLookupResult> => {
    setLoading(true);
    try {
      const response = await fetch(`${API_BASE_URL}/api/resolve-address`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ address }),
      });

      if (!response.ok) {
        const error = await response.json();
        return { error: error.error || 'Failed to resolve address' };
      }

      const data = await response.json();
      return { domain: data.domain };
    } catch (error) {
      console.error('Error resolving address:', error);
      return { error: 'Network request failed' };
    } finally {
      setLoading(false);
    }
  };

  return {
    resolveDomain,
    resolveAddress,
    loading,
  };
}
```

## Resolving directly, without a backend

For a prototype, the app can resolve on its own. The Kit resolver in
[kit-resolver.md](kit-resolver.md) uses only Kit's codecs, `@noble/hashes`, and `DataView` — no
`Buffer`, `TextEncoder`, or Node built-ins — so it needs no polyfills of its own beyond whatever
`@solana/kit` already requires in your app.

```typescript
// hooks/use-resolve-address.ts
import { useQuery } from '@tanstack/react-query';
import { address, createSolanaRpc } from '@solana/kit';
import { resolveSkrNames } from '../utils/skr';

// .skr lives on mainnet regardless of the cluster the rest of the app targets.
//
// The public endpoint, hardcoded, and not EXPO_PUBLIC_SOLANA_MAINNET_RPC_URL: every
// EXPO_PUBLIC_* value is inlined into the bundle, so putting a keyed provider URL here hands
// the key to anyone who unzips the APK — the thing this skill tells you to proxy in order to
// avoid. A prototype lives with the public endpoint's rate limits; the moment you need a paid
// provider, that is the moment you need the proxy.
const rpc = createSolanaRpc('https://api.mainnet-beta.solana.com');

export function useResolveAddress(walletAddress?: string) {
  return useQuery({
    queryKey: ['skr-name', walletAddress],
    enabled: !!walletAddress,
    // Reverse direction, so a long staleTime is fine — see "Caching by direction" below.
    staleTime: 1000 * 60 * 60,
    queryFn: async () => {
      const names = await resolveSkrNames(rpc, address(walletAddress!));
      return names[0] ?? null; // already sorted, so this is stable
    },
  });
}
```

Two caveats before shipping this rather than the proxy:

- **A key cannot live here.** `EXPO_PUBLIC_*` is inlined at build time and readable by anyone who
  unzips the APK, so client-side resolution only works against an endpoint you do not mind
  exposing. That is why the sample hardcodes the public one instead of reading an env var that
  invites a paid URL.
- Reverse lookup calls `getProgramAccounts`, which many providers restrict. The public endpoint
  will also rate-limit a list view that resolves dozens of addresses.

Both point the same way for production: proxy it, and use the hook above.

## Caching by direction

Names change rarely, so caching is worth having. But the two directions carry different
consequences when the cache is wrong, and they need different TTLs.

| Direction | What it feeds | `staleTime` | Cost of a stale hit |
| --- | --- | --- | --- |
| Reverse (address → name) | Display labels | Long — an hour is fine | A wrong label. Cosmetic. |
| Forward (name → address) | Payment destinations | None. Re-resolve at send time | Funds sent to the name's previous owner |

`.skr` names are transferable and re-registrable. Resolve `alice.skr` for a "send to" field,
cache it for an hour, and a transfer built from that cached entry pays whoever held the name an
hour ago — not the person the user thinks they are paying. Nothing about the UI looks wrong.

So for anything that becomes a transaction:

```typescript
// hooks/use-resolve-domain.ts — the forward direction, for payees.
import { useQuery } from '@tanstack/react-query';

export function useResolveDomain(domain?: string) {
  return useQuery({
    queryKey: ['skr-address', domain],
    enabled: !!domain,
    // No caching in the forward direction. The address is only good at the moment it is read.
    staleTime: 0,
    gcTime: 0,
    queryFn: () => resolveDomainViaApi(domain!),
  });
}
```

And re-resolve immediately before signing rather than trusting whatever the field last showed:

```typescript
const onSend = async () => {
  // Resolve again at send time; the value the user typed is a name, not a destination.
  const { address: destination } = await resolveDomain(recipientName);
  if (!destination) return showError('That .skr name is no longer registered');

  // Show the address that will actually be paid, not just the name that was typed.
  const confirmed = await confirmTransfer({ name: recipientName, address: destination, amount });
  if (!confirmed) return;

  await signAndSend(destination, amount);
};
```

The confirmation step is the part that is easy to skip and most worth keeping. A user who typed
`alice.skr` cannot tell a re-registration from a correct resolution, but they can recognise an
address they have paid before — so put the resolved address in front of them before they sign.

## Usage in Components

### Example 1: Display User's .skr Domain

```typescript
// app/index.tsx - Main screen showing personalized welcome
import { useEffect, useState } from 'react';
import { View, Text } from 'react-native';
import { useMobileWallet } from '@wallet-ui/react-native-kit';
import { useDomainLookup } from '../hooks/use-domain-lookup';
import { ellipsify } from '../utils/ellipsify';

export default function HomeScreen() {
  const { account } = useMobileWallet();
  const { resolveAddress, loading } = useDomainLookup();
  const [domain, setDomain] = useState<string | null>(null);

  // On the kit stack `address` is already a string. On the web3.js stack it is a
  // PublicKey, so call .toString() there.
  const address = account?.address.toString();

  useEffect(() => {
    // Clear first, including on disconnect. Without this the previous account's name stays on
    // screen while the next one resolves, or after the wallet goes away entirely.
    setDomain(null);
    if (!address) return;

    // Switching accounts starts a second lookup while the first is still in flight, and they
    // can land out of order. Without this flag, account A's name can overwrite account B's.
    let current = true;
    resolveAddress(address).then((result) => {
      if (current) setDomain(result.domain ?? null);
    });
    return () => {
      current = false;
    };
  }, [address]);

  if (!address) return <Text>Welcome, Guest!</Text>;

  return (
    <View>
      <Text>Welcome, {domain ?? ellipsify(address)}!</Text>
      {/* The address stays visible even for the signed-in user: anyone can transfer a .skr
          name to any wallet, so the label is not self-asserted. */}
      {domain ? <Text>{ellipsify(address)}</Text> : null}
      {loading ? <Text>Loading...</Text> : null}
    </View>
  );
}
```

### Example 2: Domain Search Component

```typescript
// components/domain-search.tsx - Search for domains or addresses
import { useState } from 'react';
import { View, TextInput, Button, Text } from 'react-native';
import { useDomainLookup } from '../hooks/use-domain-lookup';

export function DomainSearch() {
  const [query, setQuery] = useState('');
  const [result, setResult] = useState<string>('');
  const { resolveDomain, resolveAddress, loading } = useDomainLookup();

  const handleSearch = async () => {
    if (!query.trim()) return;

    // Check if input looks like a domain (.skr) or address
    if (query.includes('.skr')) {
      // Domain to address lookup
      const res = await resolveDomain(query);
      if (res.address) {
        setResult(`Address: ${res.address}`);
      } else {
        setResult(`Error: ${res.error}`);
      }
    } else {
      // Address to domain lookup
      const res = await resolveAddress(query);
      if (res.domain) {
        setResult(`Domain: ${res.domain}`);
      } else {
        setResult(`Error: ${res.error}`);
      }
    }
  };

  return (
    <View>
      <TextInput
        placeholder="Enter .skr domain or wallet address"
        value={query}
        onChangeText={setQuery}
      />
      <Button title="Search" onPress={handleSearch} disabled={loading} />
      {result && <Text>{result}</Text>}
    </View>
  );
}
```

### Example 3: Display .skr Instead of Address in Lists

```typescript
// components/wallet-list-item.tsx - Show .skr domain in user lists
import { useEffect, useState } from 'react';
import { View, Text } from 'react-native';
import { useDomainLookup } from '../hooks/use-domain-lookup';
import { ellipsify } from '../utils/ellipsify';

interface WalletListItemProps {
  address: string;
}

export function WalletListItem({ address }: WalletListItemProps) {
  const { resolveAddress } = useDomainLookup();
  const [domain, setDomain] = useState<string | null>(null);

  useEffect(() => {
    // Clear on change, and ignore a response that arrives after the address moved on — a
    // recycled row in a list would otherwise show the previous wallet's name.
    setDomain(null);
    let current = true;
    resolveAddress(address).then((result) => {
      if (current) setDomain(result.domain ?? null);
    });
    return () => {
      current = false;
    };
  }, [address]);

  // The name goes beside the address, never in place of it. A reverse-resolved .skr name is
  // whatever sorts first among the names that address holds, and anyone can transfer a name to
  // any wallet without the owner agreeing — so a stranger can choose the label here.
  return (
    <View>
      <Text>{domain ?? ellipsify(address)}</Text>
      {domain ? <Text>{ellipsify(address)}</Text> : null}
    </View>
  );
}
```

The truncated address is not decoration. It is the part the user can check.

## Utility: Address Truncation

```typescript
// utils/ellipsify.ts
export function ellipsify(str: string, len = 4): string {
  if (str.length <= len * 2) return str;
  return `${str.slice(0, len)}...${str.slice(-len)}`;
}
```

## Key Implementation Notes

1. **API URL**: `http://10.0.2.2:3000` reaches the host machine from an Android emulator. Physical devices need the host's LAN IP. Read it from `EXPO_PUBLIC_API_URL` instead of committing either value, and gate the emulator fallback on `__DEV__` — `EXPO_PUBLIC_*` is inlined at build time, so an ungated default ships a dead cleartext URL in the release APK, which Android's default network security config blocks regardless.

2. **No RPC keys in the app**: every `EXPO_PUBLIC_*` value is readable by anyone who unzips the build. Client-side resolution is limited to endpoints you do not mind publishing; a paid provider belongs behind the proxy.

3. **Caching**: cache by direction, not uniformly. Long `staleTime` for reverse lookups (display labels); no cache for forward lookups, re-resolved at send time, because a stale name-to-address entry pays the name's previous owner. See [Caching by direction](#caching-by-direction).

4. **Display names beside addresses, not instead of them**: a reverse-resolved `.skr` name is the first-sorting name an address happens to hold, and names are transferable without the recipient's consent, so the label can be picked by a third party. Keep the truncated address visible next to it, and put the resolved address in any confirmation step that precedes a signature.

5. **Resolution is async, so guard against stale responses**: switching accounts or recycling a list row starts a second lookup while the first is in flight, and they can land out of order. Clear the name when the address changes — including on disconnect — and drop any response that arrives after it did, or one wallet ends up labelled with another's name.

6. **Error Handling**: Always fall back to a truncated address. A failed lookup should degrade to something readable, never to a blank or a permanent spinner.

7. **Loading States**: Show a loading indicator, but render the truncated address underneath rather than an empty string, so the UI never shows a nameless user.

8. **Validation**: The backend validates input; validating on the client too avoids a round trip for obviously malformed input.

9. **Wallet hook**: The hook is `useMobileWallet()`, from `@wallet-ui/react-native-kit` or `@wallet-ui/react-native-web3js` depending on the stack. There is no `useMobileWalletAdapter` export. On the kit stack `account.address` is a string; on web3.js it is a `PublicKey` needing `.toString()`. See the `solana-mobile-wallet` skill.
