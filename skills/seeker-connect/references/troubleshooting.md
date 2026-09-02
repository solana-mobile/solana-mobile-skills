# Troubleshooting

## `association-failed` on every connect

The wallet app never completed the session handshake. Causes, most common first:

1. **Not on a Seeker.** The wallet is launched via an app link on the same device, so the
   dapp must be open in the browser on the Seeker itself. Desktop browsers always end here —
   usually within seconds via the failed launch detection below, not after the timeout. This
   is expected, not a bug in the integration.
2. **The wallet never launched.** The protocol detects a successful launch by the page
   losing focus within 3 seconds of the association URL opening. If the page stays focused,
   association fails immediately rather than after the timeout.
3. **Relay unreachable.** Session traffic rides the Nostr relay in `relayDomain`; check it
   from the device's network.
4. **Timeout too tight.** `associationTimeoutMs` (default 30s) covers association only —
   wallet launched but not yet connected. The interaction itself is never timed out.

## First connect opens a generic wallet chooser

`firstConnectWalletBaseUri` is unset, so the first connect falls back to the generic
`solana-wallet:` Android intent and Android asks which wallet to use. That is the safe default,
and it only affects the first connect: after the first authorization the wallet returns its own
`walletUriBase`, which is cached and used for every session after that.

Setting it is not a cosmetic tweak. The value is an `https:` App Link, and on that path the
protocol navigates the page to it — `window.location.assign` on the association URL, with the
association parameters attached. The only check is that the string parses as an `https:` URL,
so whichever host is named receives the handshake and gets to answer as the wallet. A guessed
domain, or a look-alike of the right one, is handed the session.

Leave it unset unless Solana Mobile has published the Seeker wallet's App Link and you are
pasting that exact value. The SDK ships no default for it, and one wallet chooser tap on the
first connect is the cheaper trade.

## `signTransaction` / `signAndSendTransaction` feature missing

These two features are derived from the wallet's `get_capabilities` response, learned during
the first connect. Before any connect both are assumed present; afterwards the set is
re-derived and a `standard:events` `change` event fires with the new `features`. Always
feature-detect (`if (wallet.features[SolanaSignTransaction]) ...`) instead of assuming.

The exact rule: `signTransaction` appears only when the wallet reports the
`solana:signTransactions` feature. `signAndSendTransaction` appears when the wallet reports
`supportsSignAndSendTransactions` — and also when it reports *neither* route, because MWA
2.0 makes sign-and-send mandatory, so a missing report means a non-reporting wallet, not a
non-signing one. The only combination that hides `signAndSendTransaction` is a wallet that
reports sign-only support.

## Connection state seems wrong

- **`connect({ silent: true })` resolved with zero accounts** — there was no cached
  authorization. That is the contract: a silent connect must never launch the wallet. Show
  the connect button.
- **Reconnected without a consent prompt** — expected. Operations replay the cached
  `authToken` (MWA reauthorize), which re-grants without fresh consent until the wallet
  revokes it.
- **Cache vanished after a declined request** — only `authorization-declined` during a
  token replay wipes the cache, because it means the wallet no longer honors the token.
  Transport failures never wipe it.
- **Disconnect didn't revoke anything wallet-side** — by design. Disconnect forgets the
  token locally and never calls `deauthorize`, which would launch the wallet app just to
  disconnect.

## Every operation shows the overlay and bounces to the wallet

Working as intended. MWA sessions are per-interaction: each connect or sign opens a fresh
session with its own progress overlay. Dismissing the overlay aborts the session and rejects
with the `cancelled` code.

## Exercising the flow off-device

For automated tests, two hooks make the SDK drivable without a Seeker:

- **Fake the transport**: pass a custom `seekerLink` to `registerSeekerConnect` and serve
  scripted responses — no relay, no wallet.
- **Fake the launch detection**: if a test harness serves a wallet endpoint over a real
  relay, the browser side still needs the page to blur within 3s of association (see above).
  Dispatching a synthetic `blur` event on `window` satisfies the check — this is what the
  repository's own E2E setup does.

Also `createMemoryAuthorizationCache()` keeps test runs from leaking authorization state
through localStorage.
