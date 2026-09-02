---
name: seeker-connect
description: Connect a web dapp to the Seeker device's built-in wallet with Seeker Connect. Use when adding wallet connection, sign-in with Solana, message signing, or transaction signing to a website that runs in the browser on a Seeker phone, registering the "Seeker Connect" Wallet Standard wallet, using the seeker-connect-button element, or debugging SeekerConnectError codes like association-failed.
---

# Seeker Connect for web dapps

Seeker Connect links a web page open in the browser **on the Seeker device** to the device's
built-in wallet. It speaks Mobile Wallet Adapter over a Nostr relay and ships Seeker-branded
progress and error UI, exposed to the app as an ordinary Wallet Standard wallet named
**"Seeker Connect"**.

This is for **web dapps**, not React Native apps. For wallet connection inside an Expo or
React Native app, use the `solana-mobile-wallet` skill instead.

## The mental model — read this before writing code

- **There is no long-lived connection.** Every wallet interaction (connect, sign message,
  sign transaction) opens its own short-lived MWA session, runs one request, and tears down.
  Each interaction launches the wallet app and shows a branded progress overlay — the one
  exception is a silent connect, which only reads the cache and never opens a session. This
  is by design — do not build reconnect loops or keep-alive logic around it.
- **"Connected" means "holds a cached authorization."** The first `connect()` stores a
  wallet-issued `authToken` plus accounts and capabilities (localStorage by default). Later
  operations replay that token silently — no repeated consent prompt.
- **Disconnect only forgets the token locally.** It deliberately never calls the wallet's
  `deauthorize`, because that would launch the wallet app just to disconnect.
- **It only completes on the device.** On desktop, connect fails with `association-failed` —
  typically within seconds, when nothing answers the wallet launch; the association timeout
  only applies to a wallet that launches but never connects. Register the wallet
  unconditionally; it simply won't get past association elsewhere.

## Step 1: install

```bash
npm install @solana-mobile/seeker-connect-wallet-standard
```

This pulls in the other Seeker Connect packages (`core`, `ui`, `web`) as dependencies.
They are not re-exported, though — so also install any package the app imports from
directly (the snippets below use `@solana-mobile/seeker-connect-ui`,
`@solana/wallet-standard-features`, and `@wallet-standard/features`); strict package
managers like pnpm refuse imports of undeclared transitive dependencies.

| Package | Role |
| --- | --- |
| `@solana-mobile/seeker-connect-core` | Shared contracts: config, error taxonomy, `SeekerLink` port |
| `@solana-mobile/seeker-connect-ui` | Lit elements: progress overlay, error dialog, branded button |
| `@solana-mobile/seeker-connect-wallet-standard` | **The entry point** — the Wallet Standard wallet |
| `@solana-mobile/seeker-connect-web` | MWA-over-Nostr transport, plus an imperative SDK |

## Step 2: register once at startup

Call `registerSeekerConnect` before the UI renders, so wallet discovery sees it from the
first render. It must run in the browser — the snippet below reads `window`, so under SSR
(Next.js and similar) put the call in a client-only module or guard it with
`typeof window !== 'undefined'`; in a plain client-rendered app, module scope of the entry
file is fine:

```ts
import { registerSeekerConnect } from '@solana-mobile/seeker-connect-wallet-standard';

registerSeekerConnect({
  identity: {
    name: 'My Dapp',
    uri: window.location.origin,
    icon: 'favicon.ico', // resolved relative to uri; shown in the wallet's consent UI
  },
  relayDomain: 'relay.solanamobile.com',
});
```

Configuration:

| Option | Required | Notes |
| --- | --- | --- |
| `identity` | yes | `name`, `uri`, optional `icon`. Shown in the wallet's consent UI |
| `relayDomain` | yes | Nostr relay that carries the session traffic |
| `associationTimeoutMs` | no | How long a launch may take before `association-failed`. Default 30s |
| `chain` | no | Chain requested at authorization. Default `solana:mainnet` |
| `firstConnectWalletBaseUri` | no | **Leave unset** unless Solana Mobile publishes a value to paste. Unset, first connects use the generic `solana-wallet:` scheme; set, the page navigates to that host — see [references/troubleshooting.md](references/troubleshooting.md#first-connect-opens-a-generic-wallet-chooser) |

`registerSeekerConnect` also accepts `seekerLink`, `authorizationCache`, and `presenter`
overrides — see [references/imperative-api.md](references/imperative-api.md).

## Step 3: use it like any other wallet

After registration, "Seeker Connect" appears in the Wallet Standard registry, so
wallet-adapter, ConnectorKit, `@solana/react-hooks`, or a raw `@wallet-standard/app` listing
all pick it up with no further wiring. Existing connect buttons and signing code keep
working.

Features exposed: `standard:connect`, `standard:disconnect`, `standard:events`,
`solana:signMessage`, `solana:signIn`, and — depending on the wallet's reported capabilities
after the first connect — `solana:signTransaction` and/or `solana:signAndSendTransaction`.

Working with the wallet directly:

```ts
import { SeekerConnectWalletName } from '@solana-mobile/seeker-connect-wallet-standard';
import { StandardConnect } from '@wallet-standard/features';

const seeker = wallets.find((wallet) => wallet.name === SeekerConnectWalletName);
const { accounts } = await seeker.features[StandardConnect].connect();
```

**Restore the session on page load** with a silent connect — it reads the cache and never
launches the wallet, resolving with zero accounts when there is nothing cached:

```ts
const { accounts } = await seeker.features[StandardConnect].connect({ silent: true });
```

**Feature-detect the signing routes.** Until the first connect, both transaction features
are assumed; after it they are re-derived from the wallet's actual capabilities, announced
via a `standard:events` `change` event. Check before calling:

```ts
import { SolanaSignAndSendTransaction } from '@solana/wallet-standard-features';

const feature = seeker.features[SolanaSignAndSendTransaction];
if (feature) {
  const [{ signature }] = await feature.signAndSendTransaction({
    account,
    chain: seeker.chains[0],
    transaction,
  });
}
```

`chain` is part of the Wallet Standard input, but this wallet ignores it — the network is the
one passed to `registerSeekerConnect`, replayed from the cached authorization on every call.
Nothing cross-checks the two, so a per-call `solana:devnet` against a mainnet registration
submits on mainnet without complaint. Pass `seeker.chains[0]` so the two can never disagree,
and change networks at registration.

Transactions cross the feature boundary as raw serialized bytes (`Uint8Array`), legacy and
v0 both supported — serialize with whichever client library the app already uses. Sign-in
follows the SIWS spec via `solana:signIn`; `domain` defaults to `window.location.host`.

When sign-in authenticates a user, the server is the authority, not the client: issue a
single-use, short-lived nonce server-side, and verify the returned message and signature —
including the expected domain and validity window — on the server before creating a
session. The `seeker-genesis-token` skill walks through that server flow step by step.

## Handle errors by code

Wallet outcomes reject with a `SeekerConnectError` carrying a `code`:

| Code | Meaning |
| --- | --- |
| `association-failed` | No wallet completed the launch: timeout, relay unreachable, or not on a Seeker |
| `authorization-declined` | The user declined authorization. The cached token is wiped; the next connect prompts fresh consent |
| `cancelled` | The user dismissed the progress overlay. **A normal outcome — never surface it as an error** |
| `request-declined` | The wallet declined to sign or submit |
| `session-closed` | The session ended before the interaction completed |
| `wallet-error` | Any other wallet-reported error |

Three failures are plain `Error`s instead, and they are misuse rather than wallet outcomes:
`signAndSendTransaction` on a wallet that reported no support for it, any signing call before a
successful connect, and a sign-in the wallet answered without a result.

That distinction decides who shows the error. The branded dialog fires for `SeekerConnectError`
and nothing else — every code above except `cancelled`, which is a normal outcome and stays
silent. The three plain `Error`s never reach the presenter, so if the app shows nothing they
fail invisibly. Branch on the type first, then on `.code`:

```ts
import { SeekerConnectError, SeekerConnectErrorCode } from '@solana-mobile/seeker-connect-wallet-standard';

try {
  await seeker.features[StandardConnect].connect();
} catch (error) {
  if (error instanceof SeekerConnectError) {
    if (error.code === SeekerConnectErrorCode.cancelled) {
      return; // user closed the overlay; nothing to report
    }
    // The SDK has shown its dialog. Log, and leave the UI in the disconnected state.
    console.error(error);
    return;
  }
  // No dialog was shown for this one. Surface it yourself.
  showToast('Could not connect to the wallet.'); // your app's own error UI
  console.error(error);
}
```

## Optional: the branded connect button

`@solana-mobile/seeker-connect-ui` ships a `<seeker-connect-button>` custom element in
Shadow DOM (no host CSS needed). The SDK defines its elements on first use; call
`defineSeekerConnectElements()` at startup to define them eagerly:

```ts
import { defineSeekerConnectElements } from '@solana-mobile/seeker-connect-ui';

defineSeekerConnectElements();
```

```html
<seeker-connect-button theme="dark" variant="sign-in"></seeker-connect-button>
```

Attributes: `disabled`, `theme="light" | "dark"` (names the host page's theme), and
`variant="connect"` (default) or `variant="sign-in"` for the label. Wire `click` to the
connect or sign-in call yourself — the button is presentation only.

## Reference material

- [references/imperative-api.md](references/imperative-api.md) — the non-Wallet-Standard
  path via `createNostrSeekerLink().transact`, and the `seekerLink` /
  `authorizationCache` / `presenter` overrides
- [references/troubleshooting.md](references/troubleshooting.md) — association failures,
  desktop testing, capability-derived features, cache behavior

## Related skills

- `seeker-domains` — display `.skr` names instead of raw addresses
- `seeker-genesis-token` — verify Seeker device ownership after connecting
- `solana-mobile-wallet` — wallet connection in React Native apps (Mobile Wallet Adapter
  directly)

## Links

- MWA web docs: https://docs.solanamobile.com/get-started/web/installation
- Seeker Connect repository: https://github.com/solana-mobile/seeker-connect
