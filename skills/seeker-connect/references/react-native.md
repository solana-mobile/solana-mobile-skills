# React Native

`@solana-mobile/seeker-connect-react-native` is a native module over the Android Seeker Connect
SDK, drawing that SDK's Compose button and dialogs. It talks to the wallet over a local
WebSocket on the device, so there is no relay to configure and no relay terms to accept.

## Requirements

- React Native 0.81 or later, Expo SDK 54 or later.
- **A development build.** The module is native, so Expo Go cannot run it. Autolinking picks
  it up on the next `npx expo prebuild`; current Expo SDKs already meet its Android floor of
  compileSdk 36, Android Gradle plugin 8.9.1, and Kotlin 2.0.
- `0.2.0` or later. Nothing earlier was published.
- For a new app, start from the `expo-kit-minimal` template:
  `npx solana-mobile@latest create my-app --template expo-kit-minimal`. It ships everything on
  this page wired up: the package, a provider that keeps the authorization in React state and
  builds transactions with `@solana/kit`, and the native button.

## Install

```bash
npm install @solana-mobile/seeker-connect-react-native
```

then rebuild the development client.

## Configure once

```ts
import { SeekerConnect } from '@solana-mobile/seeker-connect-react-native';

await SeekerConnect.configure({
  identity: { name: 'My Dapp', uri: 'https://mydapp.example.com', icon: 'favicon.ico' },
  chain: 'solana:devnet', // defaults to solana:mainnet
});
```

**`identity.uri` must be an `https` URL.** Mobile Wallet Adapter requires an absolute,
hierarchical URI, and the Seeker wallet ends the session on a custom scheme such as
`myapp://` — the user sees "The wallet session ended" on every connect. Do not reuse the
Expo `scheme` from `app.json`. The wallet shows the URI's host in its consent sheet.

| Option | Required | Notes |
| --- | --- | --- |
| `associationTimeoutMs` | no | How long a launch may take before `association-failed`. Default 30s |
| `chain` | no | Chain requested at authorization. Default `solana:mainnet` |
| `firstConnectWalletBaseUri` | no | Leave unset. Defaults to `https://connect.solanamobile.com`, the App Link domain certified wallets handle |
| `identity` | yes | `name`, `uri`, optional `icon` (relative to `uri`). Shown in the wallet's consent UI |

There is no `relayDomain`: the transport is local. Calls that launch the wallet use the
app's current activity, so call them from a mounted screen rather than at module scope
before the app has rendered.

## The client

`SeekerConnect` is a module-level object; `configure` once, then:

| Method | Notes |
| --- | --- |
| `restore()` | The cached authorization without launching the wallet; `null` when there is none |
| `connect()` | Restores, or authorizes in a fresh session. Resolves the `StoredAuthorization` |
| `signIn(payload?)` | Sign-In-With-Solana, connecting in the same session when needed. `domain` defaults to the identity URI's host. Resolves `address`, `publicKey`, `signedMessage`, `signature` |
| `signMessages(addresses, payloads)` | Base58 addresses; one signed message per payload |
| `signTransactions(payloads)` | Serialized transaction bytes in, signed bytes out |
| `signAndSendTransactions(payloads, options?)` | Submits; resolves one signature per transaction |
| `transact(requests)` | Several sign requests in one wallet launch; one result list per request |
| `disconnect()` | Forgets the authorization locally, without launching the wallet |
| `walletAvailability()` | `'certified'`, `'other'`, or `'none'`, without launching anything |

Bytes cross as `Uint8Array` in both directions; serialize transactions with whichever client
library the app already uses. The mental model from the skill holds: every call is its own
short-lived session, "connected" means `restore()` returns an authorization, and
`disconnect` never deauthorizes wallet-side.

**Restore on launch** so a returning user is connected without a wallet round trip, for
example with React Query:

```ts
const query = useQuery({
  queryKey: ['seeker-authorization', chain],
  queryFn: () => SeekerConnect.restore(),
});
```

and writes `connect()`'s result back into that query with `setQueryData`. `disconnect()`
resolves `void`, so after it store `null` yourself. After `signIn`, call `restore()` to get the
`StoredAuthorization` the sign-in created.

When sign-in authenticates a user, the nonce and verification rules from the skill's
Step 4 apply unchanged: the server issues the nonce and verifies the signed message.

## The button

```tsx
import { SeekerConnectButton } from '@solana-mobile/seeker-connect-react-native';

<SeekerConnectButton onPress={() => connect()} style={{ height: 56 }} />
```

A native view: **give it a height in `style`**, or it renders at zero size, since React
Native cannot measure it. The design height is 56. Props: `variant` (`connect`, the
default, or `sign-in`), `theme` (`light` or `dark`; follows the system when unset),
`enabled`, and `onPress`. It is presentation only — wire `onPress` to `connect()` or
`signIn()` yourself.

Use it as the one dedicated control that starts the connection. Other actions (sign,
disconnect) can use the app's own buttons.

The branded progress and error dialogs are drawn by the module inside the app's activity
and are always on; React Native apps cannot replace them. The consent and approval sheets
on top of those come from the wallet app.

## Handle errors by code

Rejections are `SeekerConnectError` with the codes from the skill, plus four the native
side adds:

| Code | Meaning |
| --- | --- |
| `invalid-argument` | A payload or address the bridge could not decode |
| `no-activity` | No foreground activity to launch the wallet from |
| `no-wallet-found` | No Mobile Wallet Adapter wallet is installed |
| `not-configured` | The native module is not linked, or a call came before `configure` |

`cancelled` is still a normal outcome. `not-configured` for a missing native module is raised
in JavaScript before anything native runs, so no dialog shows: it means the app is running in
Expo Go or in a development client built before the package was installed, and the fix is a
rebuild. For the rest, the SDK's dialog has told the user; log the error and leave the UI
disconnected.

## Kotlin

The same SDK is on Maven Central for Kotlin apps, with the button and dialogs as Compose
composables; the React Native methods above mirror it one to one. See
[kotlin.md](kotlin.md).
