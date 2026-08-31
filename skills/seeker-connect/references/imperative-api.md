# Imperative API and injection points

The Wallet Standard wallet is the canonical entry point. Reach for the pieces below when the
dapp does not use Wallet Standard, or when a default (storage, UI, transport) needs
replacing.

## `transact`: one session, one callback

`@solana-mobile/seeker-connect-web` exposes the `SeekerLink` implementation directly:

```ts
import { createNostrSeekerLink, SeekerConnectError } from '@solana-mobile/seeker-connect-web';

const link = createNostrSeekerLink();

const nonce = await fetch('/api/siws/nonce').then((response) => response.text());
const issuedAt = new Date();

const authorization = await link.transact(config, async (wallet) => {
  return wallet.authorize({
    signInPayload: {
      domain: window.location.host,
      uri: window.location.origin,
      statement: 'Sign in to My Dapp',
      version: '1',
      chainId: 'solana:mainnet',
      nonce,
      issuedAt: issuedAt.toISOString(),
      expirationTime: new Date(issuedAt.getTime() + 5 * 60_000).toISOString(),
    },
  });
});
```

`config` is the same `SeekerConnectConfig` object `registerSeekerConnect` takes (`identity`,
`relayDomain`, optional `chain`, `firstConnectWalletBaseUri`, `associationTimeoutMs`).

Fill the payload in, every time. This path hands `signInPayload` to the wallet verbatim: unlike
the `solana:signIn` feature on the Wallet Standard wallet, it does not default `domain`, and
nothing anywhere invents a nonce. A payload carrying only a `statement` produces a signature
over a message with no site to bind it to, no single-use value, and no expiry — it proves
someone holds the key, and nothing else, so it is replayable forever by anyone who sees it.

The nonce comes from the server, is used once, and is checked there against the returned
message and signature along with the domain and the validity window, before any session is
created. The `seeker-genesis-token` skill walks through that server side.

`transact(config, callback, options?)` establishes one wallet session, runs the callback
against it, and always tears the session down when the callback settles. The `wallet` handle
is only valid inside the callback. Options:

| Option | Notes |
| --- | --- |
| `signal` | `AbortSignal`; aborting closes the session and rejects the `transact` promise |
| `walletUriBase` | Endpoint-specific wallet URI from a prior authorization; targets that wallet directly instead of the first-connect URI |

Rejections are always `SeekerConnectError` (see the code table in the skill).

Note there is **no built-in UI on this path** — the progress overlay and error dialog belong
to the presenter, which only the Wallet Standard wallet wires up by default. Either render
your own feedback around `transact`, or use `createSeekerConnectPresenter()` from
`@solana-mobile/seeker-connect-ui` manually.

## The session-scoped wallet handle

Inside the callback, `wallet` is a `SeekerWallet`:

| Method | Notes |
| --- | --- |
| `authorize(request?)` | Fresh consent, or pass `authToken` to reauthorize silently. Optional `chain`, `signInPayload` (SIWS). Returns `accounts`, `authToken`, `walletUriBase`, and `signInResult` when a sign-in payload was sent |
| `deauthorize({ authToken })` | Invalidates a token wallet-side. The Wallet Standard wallet never calls this |
| `getCapabilities()` | Supported transaction versions, feature identifiers, `supportsSignAndSendTransactions`, batch limits |
| `signAndSendTransactions({ payloads, options? })` | Submits; resolves raw signature bytes per transaction. Options: `minContextSlot`, `commitment`, `skipPreflight`, `maxRetries`, `waitForCommitmentToSendNextTransaction` |
| `signMessages({ addresses, payloads })` | Base58 addresses of the signing accounts; resolves signed message bytes (signature = final 64 bytes) |
| `signTransactions({ payloads })` | Serialized transaction bytes in, signed bytes out. Only if the wallet reports the `solana:signTransactions` feature |

Addresses are base58 throughout — the adapter converts from MWA's base64 wire encoding.

To stay "connected" across interactions, persist what `authorize` returns (`authToken`,
`accounts`, `walletUriBase`, capabilities) and replay the token in the next session's
`authorize` — exactly what the Wallet Standard wallet's `AuthorizationCache` does.

## Overriding the defaults in `registerSeekerConnect`

```ts
registerSeekerConnect({
  ...config,
  authorizationCache: createMemoryAuthorizationCache(), // instead of localStorage
  presenter: myPresenter,                               // instead of the built-in UI
  seekerLink: myLink,                                   // instead of the Nostr transport
});
```

**`authorizationCache`** persists the authorization between page loads. Exports:
`createLocalStorageAuthorizationCache()` (default) and `createMemoryAuthorizationCache()`
(useful for tests, or when persistence is unwanted). Custom implementations provide
`get()`, `set(authorization)`, and `clear()`, all async.

**`presenter`** owns the UI shown around interactions. The interface is two methods:
`interactionStarted(cancel)` — called when an interaction begins; invoking `cancel` aborts
it (that is what produces the `cancelled` error code); returns a closer invoked on
settlement — and `interactionFailed(error)` for failures the user should be told about.
Implementations must tolerate any call ordering and never throw. Replace it to integrate
Seeker Connect into an app's own modal system.

**`seekerLink`** replaces the transport entirely — the main use is injecting a fake wallet
in tests.
