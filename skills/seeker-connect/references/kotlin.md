# Kotlin

`com.solanamobile:seeker-connect` is the Seeker Connect SDK for Android apps written in
Kotlin, with `com.solanamobile:seeker-connect-compose` adding the branded button and
dialogs for Jetpack Compose. It talks to the wallet over a local WebSocket on the device,
so there is no relay to configure and no relay terms to accept. The React Native package
wraps this SDK, so the two expose the same client.

## Requirements

- compileSdk 36 or later, Android Gradle plugin 8.9.1 or later, Kotlin 2.0 or later.
- For a new app, start from the `kotlin-compose-minimal` template:
  `npx solana-mobile@latest create my-app --template kotlin-compose-minimal`. It ships
  everything on this page wired up: the catalog entries, the ViewModel, the button, and the
  dialogs.
- `0.2.0` or later. Nothing earlier was published.

## Install

In `gradle/libs.versions.toml`:

```toml
[versions]
seekerConnect = "0.2.0"

[libraries]
seeker-connect = { group = "com.solanamobile", name = "seeker-connect", version.ref = "seekerConnect" }
seeker-connect-compose = { group = "com.solanamobile", name = "seeker-connect-compose", version.ref = "seekerConnect" }
```

In `app/build.gradle.kts`:

```kotlin
implementation(libs.seeker.connect)
implementation(libs.seeker.connect.compose)
```

The SDK depends on Mobile Wallet Adapter `clientlib-ktx` itself, so an app that only uses
Seeker Connect can drop its direct `mobile-wallet-adapter-clientlib-ktx` dependency.

## Construct once

Build one `SeekerConnect` per app and keep it in a ViewModel. It needs a `Context` for the
link and the cache, so use an `AndroidViewModel`:

```kotlin
class MainViewModel(application: Application) : AndroidViewModel(application) {
    val dialogs = SeekerConnectDialogState()

    private val seekerConnect = SeekerConnect(
        SeekerConnectConfig(
            identity = DappIdentity("My Dapp", "https://mydapp.example.com", "favicon.ico"),
            chain = "solana:devnet", // defaults to solana:mainnet
        ),
        MwaSeekerLink(application),
        SharedPreferencesAuthorizationCache(application),
        dialogs,
    )
}
```

**`identity.uri` must be an `https` URL.** Mobile Wallet Adapter requires an absolute,
hierarchical URI, and the Seeker wallet ends the session on a custom scheme. The wallet
shows the URI's host in its consent sheet; `icon` is resolved relative to it.

| Argument | Notes |
| --- | --- |
| `SeekerConnectConfig` | `identity` (required), `chain`, `firstConnectWalletBaseUri` (leave the default), `associationTimeoutMs` (default 30s) |
| `MwaSeekerLink(context)` | The transport: launches the wallet and runs the MWA session |
| `AuthorizationCache` | `SharedPreferencesAuthorizationCache(context)` survives process death; the default is in-memory |
| `SeekerConnectPresenter` | `SeekerConnectDialogState()` from the Compose module draws the branded progress and error cards; the default shows nothing |

## The client

Every call is a `suspend` function. The ones that launch the wallet take the
`ComponentActivity` to launch it from and register their activity-result launcher on
demand, so they can run at any point in the activity's lifecycle.

| Method | Notes |
| --- | --- |
| `authorization` | `StateFlow<StoredAuthorization?>`: the held authorization, `null` while disconnected. Collect it to drive the UI |
| `restore()` | The cached authorization without launching the wallet; `null` when there is none |
| `connect(activity)` | Restores, or authorizes in a fresh session. Concurrent calls launch the wallet once |
| `signIn(activity, payload)` | Sign-In-With-Solana, connecting in the same session when needed. `SeekerSignInPayload.domain` defaults to the identity URI's host. Returns `address`, `publicKey`, `signedMessage`, `signature` |
| `signMessages(activity, addresses, payloads)` | Base58 addresses; one signed message per payload, as `ByteArray` |
| `signTransactions(activity, payloads)` | Serialized transaction bytes in, signed bytes out |
| `signAndSendTransactions(activity, payloads, options?)` | Submits; returns one raw signature per transaction |
| `transact(activity) { authorization -> … }` | Several requests in one wallet launch, on the `SeekerWallet` receiver |
| `disconnect()` | Forgets the authorization locally, without launching the wallet. To also revoke the token, call `transact(activity) { deauthorize(it.authToken) }` first |
| `walletAvailability()` | `CERTIFIED`, `OTHER`, or `NONE`, without launching anything |

Launch wallet calls in the activity's `lifecycleScope`, so a destroyed activity cancels
them instead of launching the wallet from it later. Cancelling the coroutine cancels the
interaction and closes the session; that is not an error. Call `restore()` once in the
ViewModel's `init`, so a returning user is connected without a wallet round trip:

```kotlin
init {
    seekerConnect.authorization
        .onEach { authorization -> _uiState.update { it.copy(address = authorization?.accounts?.first()?.address) } }
        .launchIn(viewModelScope)
    viewModelScope.launch { seekerConnect.restore() }
}

fun connect(host: ComponentActivity) = host.lifecycleScope.launch {
    try {
        seekerConnect.connect(host)
    } catch (e: SeekerConnectException) {
        Log.w("Wallet", "connect failed: ${e.code}")
    }
}

fun signMessage(host: ComponentActivity, message: String) = host.lifecycleScope.launch {
    val address = checkNotNull(seekerConnect.authorization.value).accounts.first().address
    try {
        val signature = seekerConnect.signMessages(host, listOf(address), listOf(message.encodeToByteArray())).single()
    } catch (e: SeekerConnectException) {
        Log.w("Wallet", "sign failed: ${e.code}")
    }
}
```

Catch `SeekerConnectException` inside the coroutine: an exception that escapes `launch`
crashes the app.

`authorization` already updates on `connect`, `signIn`, and `disconnect`, so the UI needs no
other bookkeeping. Do not name a helper `run` and call it inside `launch { }`: the stdlib
`run` on the coroutine scope wins, the block executes, and its result is silently dropped.

When sign-in authenticates a user, the nonce and verification rules from the skill's
Step 4 apply unchanged: the server issues the nonce and verifies the signed message.

## The button and dialogs

```kotlin
setContent {
    SeekerConnectButton(onClick = { viewModel.connect(this) }, enabled = !state.isLoading)
    SeekerConnectDialogs(viewModel.dialogs)
}
```

`SeekerConnectButton` draws "Connect with Seeker" (`variant = SeekerConnectButtonVariant.CONNECT`,
the default) or "Sign in with Seeker" (`SIGN_IN`) at 56dp high and up to 368dp wide, black on
a light screen and white on a dark one; pass `darkTheme` to force one. It is presentation
only: wire `onClick` to `connect` or `signIn` yourself. Use it as the one dedicated control
that starts the connection; other actions can use the app's own buttons.

`SeekerConnectDialogs` draws the progress card during a wallet interaction and the error
card after a failure, from the `SeekerConnectDialogState` the client was built with. Place
it once at the top of the screen tree. Closing the progress card cancels the interaction,
which then fails with `CANCELLED` and shows no error card. The consent and approval sheets
on top of those come from the wallet app.

## Handle errors by code

Wallet and transport failures throw `SeekerConnectException` with a `code`:

| Code | Meaning |
| --- | --- |
| `ASSOCIATION_FAILED` | No wallet completed association: timeout, or the wallet returned without connecting |
| `AUTHORIZATION_DECLINED` | The wallet declined authorization; on reauthorization the stored token is discarded |
| `CANCELLED` | The user closed the Seeker Connect UI, or disconnected mid-interaction |
| `NO_WALLET_FOUND` | No Mobile Wallet Adapter wallet is installed |
| `REQUEST_DECLINED` | The wallet declined to sign or submit |
| `SESSION_CLOSED` | The session ended before the interaction completed |
| `WALLET_ERROR` | Any other wallet-reported error; `cause` holds the MWA error |

Catch `SeekerConnectException` inside the coroutine and let `CancellationException`
propagate. `CANCELLED` is a normal outcome. For the rest, the dialogs have told the user; log the code and leave the
UI disconnected.
