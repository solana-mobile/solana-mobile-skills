---
name: dapp-store-publishing
description: Build/sign/publish Solana dApp Store releases. Triggers - "publish to dApp Store", "ship to Seeker", "submit app", "release update", "sign APK".
---

# dApp Store Publishing

## Use

- App built + tested, ready to ship
- First release or shipping an update
- Need to sign an APK for distribution

## Not

- App not built → `seeker-app-scaffold` first
- No publisher account → register at publish.solanamobile.com first (mints App NFT)
- `.aab` submission → unsupported. Use `assembleRelease`, not `bundleRelease`
- Google Play → different store, different signing key

## One-time setup

### Publisher + App NFT

1. publish.solanamobile.com → connect wallet (Phantom/Solflare).
2. Fund **~0.2 SOL** for fees + storage.
3. Create publisher + dApp listing → mints App NFT.
4. Storage: ArDrive.
5. **Publisher wallet = required forever. Do not lose.**

### API key

publish.solanamobile.com/dashboard/settings/api-keys

```bash
export DAPP_STORE_API_KEY=<key>
```

### CLI

```bash
npm install -g @solana-mobile/dapp-store-cli
```

Node 18+.

## Build + sign APK

**APK only.** `.aab` rejected.

### Keystore (once)

```bash
keytool -genkey -v -keystore my-app.keystore -alias my-app \
  -keyalg RSA -keysize 2048 -validity 10000
```

Password manager only. Losing = no updates ever.

Google Play too? → **different key**.

### Gradle

```gradle
android {
  signingConfigs {
    dappStore {
      storeFile file("keystores/my-app.keystore")
      storePassword System.getenv("DAPP_KEYSTORE_PWD")
      keyAlias "my-app"
      keyPassword System.getenv("DAPP_KEY_PWD")
    }
  }
  buildTypes {
    release {
      signingConfig signingConfigs.dappStore
      // minifyEnabled false  // see Pitfalls before enabling
    }
  }
}
```

No plaintext passwords. Env or `~/.gradle/gradle.properties`.

### Build

```bash
cd android && ./gradlew :app:assembleRelease
# → app/build/outputs/apk/release/app-release.apk
```

### Verify

```bash
apksigner verify --print-certs app/build/outputs/apk/release/app-release.apk
```

## Publish

Legacy `init/create/validate/publish` flow = **dead**. Single entrypoint:

```bash
dapp-store --apk-file ./app-release.apk --whats-new "Initial release"
# or
dapp-store --apk-url https://cdn/app.apk --whats-new "Bug fixes"
```

Portal infers target app from APK package name. Must match step 1. No `--rpc-url` — portal handles.

### API key via stdin

```bash
printf '%s' "$DAPP_STORE_API_KEY" | dapp-store --apk-file ./app-release.apk --whats-new "..."
```

### Keypair

CLI wants signer keypair. Default `~/.config/solana/id.json`. Override: `--keypair <path>`.

## Review

3–5 business days. Common rejects: unsigned APK, mismatched package, missing privacy policy, content policy violation.

## Updates

Same command. Portal matches by package name. **Bump `versionCode`** every release.

## Pitfalls

| Issue | Fix |
|-------|-----|
| `.aab` submitted | `assembleRelease`, not `bundleRelease` |
| Wrong signing key on update | Keep keystore safe forever. No recovery. |
| `versionCode` not bumped | Bump in `build.gradle` |
| Publisher wallet drained | Top up to ~0.2 SOL |
| `minifyEnabled true` breaks MWA / reflective native modules in release | Default to `false`. If enabling, add `-keep` rules in `proguard-rules.pro` for `com.solana.mobilewalletadapter.**`, `com.solanamobile.**`, and any other reflective deps. Test release build before submission. |
| App crashes on launch only in release | Almost always missing ProGuard rules. Disable `minifyEnabled` to confirm. |
| Package name mismatch between APK + portal | The portal infers app identity from APK package name; must match the `expo.android.package` set at scaffold. |

## Refs

- docs.solanamobile.com/dapp-store/intro
- docs.solanamobile.com/dapp-store/publishing-cli
- docs.solanamobile.com/dapp-store/build-and-sign-an-apk
- docs.solanamobile.com/dapp-store/publisher-policy
- github.com/solana-mobile/dapp-publishing
