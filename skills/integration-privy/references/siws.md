# Sign-In-With-Solana against Privy

The exchange in full, plus the three variations on it: linking a second wallet, verifying the
session on a server, and driving the raw MWA protocol when Wallet UI is not in the project.

## The exchange

```
generateMessage  →  Privy builds a SIWS message bound to the address, domain, and uri
signMessages     →  the wallet app signs it, user approves in the wallet
login            →  Privy verifies the signature and returns a User
```

Privy owns the nonce and the expiry inside the message, which is the reason to call
`generateMessage` rather than assembling a SIWS message yourself. A hand-built message will not
carry a nonce Privy issued, and `login` rejects it.

## Exact hook signatures

`useLoginWithSiws()` from `@privy-io/expo`:

```ts
generateMessage: (args: {
  from: { domain: string; uri: string }
  wallet: { address: string }
}) => Promise<{ message: string }>

login: (opts: {
  disableSignup?: boolean
  message: string
  signature: string
  wallet?: { connectorType?: string; walletClientType?: string }
}) => Promise<User>
```

Notes that are not obvious from the shape:

- `wallet` on `login` is optional metadata that gets stored on the linked account. Omitting it
  is fine; the template does.
- `disableSignup: true` makes `login` reject rather than create an account for an unrecognized
  wallet. Use it when a separate onboarding flow owns account creation.
- The hook takes no `onSuccess` or `onError` options, unlike its React web counterpart. Handle
  both from the returned promise.
- `login` resolves to a `User`. Reading `usePrivy().user` immediately after is also fine — the
  provider state updates as part of the call.

## Encoding, end to end

This is where the integration goes wrong, so trace the types once:

| Step | Value | Encoding |
| --- | --- | --- |
| `account.address` | Kit `Address` | base58 — pass this to `generateMessage` |
| `account.addressBase64` | MWA wire format | base64 — Privy rejects it |
| `generateMessage` result | `{ message: string }` | plain text |
| `signMessages` argument | `Uint8Array` | `new TextEncoder().encode(message)` |
| `signMessages` result | `Uint8Array` | MWA *signed payload*, not a bare signature |
| `login` `signature` | `string` | `fromUint8Array(...)` — base64 |

`fromUint8Array` is exported from `@wallet-ui/react-native-kit` as a re-export of `js-base64`.
Use it rather than `btoa(String.fromCharCode(...bytes))`, which throws
`RangeError: Maximum call stack size exceeded` on payloads of any size.

Do not slice the signed payload down to its trailing 64 bytes. Both the `expo-kit-privy`
template and Privy's own MWA recipe pass the whole thing base64-encoded, and that is what
Privy's verifier expects.

## Choosing `domain` and `uri`

```ts
const siwsDomain = 'myapp.com'
const siwsUri = 'myapp://privy-login'
```

`domain` is an RFC 3986 *authority* — a host, optionally with a port. No scheme, no trailing
path. `uri` is a full URI identifying what is requesting the signature; a deep link into the
app is the natural choice on mobile.

Both are rendered inside the message the user approves in their wallet, so they are the only
thing distinguishing your request from a phishing one. Pick values that read as yours and then
leave them alone — changing them changes what users see at every login.

## Linking a wallet to an existing account

Same shape, different hook. Use this when the user already signed in some other way — email,
OAuth — and is now attaching a wallet:

```tsx
import { useLinkWithSiws } from '@privy-io/expo'

const { generateMessage, link } = useLinkWithSiws()

const { message } = await generateMessage({
  from: { domain: siwsDomain, uri: siwsUri },
  wallet: { address: address.toString() },
})
const signedPayload = await signMessages(new TextEncoder().encode(message))

await link({ message, signature: fromUint8Array(signedPayload) })
```

`link` takes the same options as `login` minus `disableSignup`, and returns the updated `User`
with the wallet in its linked accounts. Calling `login` here instead would start a second
account owned by the wallet, orphaning the original.

## Verifying the session on a server

The client's `user.id` proves nothing — it is a string the client could invent. Send the access
token and let the server decide:

```ts
const { getAccessToken } = usePrivy()

const token = await getAccessToken()

await fetch('https://api.myapp.com/claim', {
  headers: { authorization: `Bearer ${token}` },
  method: 'POST',
})
```

Fetch a token per request. It is short-lived and the SDK refreshes it on demand, so a cached
copy expires mid-session.

### Verify the token, and pin who it was issued for

Privy access tokens are ES256 JWTs. Three shapes verify one, and whichever you pick, read the
app ID into a checked constant at module load, before anything that verifies a token:

```ts
const PRIVY_APP_ID = process.env.PRIVY_APP_ID
if (!PRIVY_APP_ID) throw new Error('PRIVY_APP_ID is not set')
```

All three want a `string` there. Threading `process.env.PRIVY_APP_ID` through directly types as
`string | undefined`, and the `undefined` case is the one that fails open — see the warning at
the end of this section.

The server SDK runs the whole check and is the right default. It is also the only one of the
three that needs the app secret, so check that where the client is built rather than at module
load — a server on either other path has no secret to check:

```ts
import { PrivyClient } from '@privy-io/node'

const PRIVY_APP_SECRET = process.env.PRIVY_APP_SECRET
if (!PRIVY_APP_SECRET) throw new Error('PRIVY_APP_SECRET is not set')

const privy = new PrivyClient({
  appId: PRIVY_APP_ID,
  appSecret: PRIVY_APP_SECRET,
})

const claims = await privy.utils().auth().verifyAccessToken(token)
```

It resolves the app's JWKS from `appId` and pins `typ`, `algorithms`, `issuer`, and the audience
for you. Option names and call shape are as published in `@privy-io/node` 0.34.0.

`claims` is a `VerifyAccessTokenResponse`. Its fields are snake_case, and they are the whole of
what a verified access token tells you:

| Field | Claim | Value |
| --- | --- | --- |
| `app_id` | `aud` | your app ID |
| `expiration` | `exp` | unix seconds |
| `issued_at` | `iat` | unix seconds |
| `issuer` | `iss` | `privy.io` |
| `session_id` | `sid` | the session the token was issued for |
| `user_id` | `sub` | the Privy user ID |

The same package also exports `verifyAccessToken` standalone. It takes the verification key
instead of resolving one, so it needs no app secret:

```ts
import { verifyAccessToken } from '@privy-io/node'
import { createRemoteJWKSet } from 'jose'

const jwks = createRemoteJWKSet(
  new URL(`https://api.privy.io/v1/apps/${PRIVY_APP_ID}/jwks.json`),
)

const claims = await verifyAccessToken({
  access_token: token,
  app_id: PRIVY_APP_ID,
  verification_key: jwks,
})
```

Its input keys are snake_case, unlike the constructor's. `verification_key` also takes the
dashboard's static verification key as a PEM string — it calls `importSPKI` on it for you —
or any `CryptoKey`. Reach for this shape on a server that only authenticates and never calls
the Privy API, where an app secret buys nothing and is one more thing to leak.

Without the SDK at all, verify against Privy's JWKS with `jose` and pass `issuer` and `audience`
explicitly:

```ts
import * as jose from 'jose'

const jwks = jose.createRemoteJWKSet(
  new URL(`https://api.privy.io/v1/apps/${PRIVY_APP_ID}/jwks.json`),
)

const { payload } = await jose.jwtVerify(token, jwks, {
  algorithms: ['ES256'],
  audience: PRIVY_APP_ID,
  issuer: 'privy.io',
  typ: 'JWT',
})
```

`createRemoteJWKSet` caches the fetch and re-fetches on an unknown key ID, so signing-key
rotation does not need a deploy. The dashboard also exposes a single static verification key
under **Configuration > App settings**, usable via `jose.importSPKI(key, 'ES256')` in place of
`jwks` — but pin it only if you would rather redeploy than allow an outbound call to Privy.

**A valid signature is not proof the token was issued to you.** Privy mints tokens for every app
on the platform, and creating an app takes a minute. Check the signature without pinning
`audience` to your own app ID and a token minted for an attacker's Privy app authenticates
against your server — the signature is genuine, it was simply never issued for you. `audience`
is the claim that makes this authentication rather than a well-formedness check. Pin `issuer`
and `algorithms` in the same breath.

**And `audience` has to be a value, not a lookup.** `jose.jwtVerify` does not fail an audience
check it cannot perform — it skips the check entirely when `audience` is `undefined`. Written
inline as `audience: process.env.PRIVY_APP_ID`, an unset variable therefore turns verification
back into a well-formedness check without raising anything. On the JWKS path that same unset
variable corrupts the URL, so it tends to break loudly by luck. On the `importSPKI` path there
is no URL to corrupt: the key is valid, the signature is genuine, and any Privy app's token is
accepted. That is what the checked constant at the top of this section is for — read the
variable once, throw there, and pass the constant everywhere else.

Verification yields `claims.user_id` and nothing else identifying; an access token carries no
linked accounts. The wallet address comes from a further lookup — your own record keyed by
`user_id`, or `privy.users().get({ id_token })` against a Privy identity token — never from
the request body.

Taking the address from the request body instead is the same class of bug the
`seeker-genesis-token` skill covers in detail: a caller supplies someone else's address
alongside their own valid token and inherits their entitlements.

## Without Wallet UI: the raw protocol

Only relevant if the project talks to `@solana-mobile/mobile-wallet-adapter-protocol` directly.
`@wallet-ui/react-native-kit` wraps all of this, so prefer it in new code.

Two things the wrapper is doing that you then have to do yourself:

1. **Address conversion.** `authorizationResult.accounts[0].address` is base64. Privy needs
   base58, so decode the bytes and re-encode — with `getBase58Decoder()` from `@solana/kit`, or
   `new PublicKey(bytes).toBase58()` on the web3.js stack.
2. **Session management.** Everything runs inside a single `transact` callback, and
   authorization is not cached between calls unless you cache it.

Signing still returns a signed payload that you base64-encode and pass to `login` unchanged —
that part does not differ. Privy's recipe has the full component:
https://docs.privy.io/recipes/solana/adding-solana-mwa

Note that the recipe is written against `@solana/web3.js` and `react-native-quick-base64`.
Neither is needed on the kit stack; `@solana/kit`'s codecs cover the same ground.
</content>
