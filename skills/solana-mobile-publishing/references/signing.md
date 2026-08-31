# Signing and release builds

Everything between a working debug build and a signed APK the dApp Store will accept.

The signing key decisions here are permanent: an update must be signed with the same key as the
release before it, and there is no way to re-key a listing. Read this section before generating
a keystore, not after.

## Create the keystore

Once per app, and never again.

**Ask where the keystore should live before generating it, and never write it inside the
repository.** `keytool` writes to the current working directory if you let it, so running this
from a project root drops a release signing key into the tree where a later `git add` will take
it. In a public repo that is an unrecoverable compromise: anyone can sign an update as you, and
the key cannot be rotated.

```bash
mkdir -p ~/.keystores
keytool -genkey -v -keystore ~/.keystores/my-app.keystore -alias my-app \
  -keyalg RSA -keysize 2048 -validity 10000
```

`~/.keystores` is a placeholder to confirm with the user, not a default to assume. An OS
keychain or a password manager that stores file attachments is better, and an organisation
shipping more than one app usually has a secrets store that release keys belong in.

`-validity 10000` is roughly 27 years. A keystore that expires while the app is still shipping
cannot sign an update, and the app cannot be re-keyed, so do not shorten it.

Put the keystore and both passwords somewhere durable and access-controlled immediately. This is
the single unrecoverable artifact in the pipeline: losing it ends the listing's update path
permanently, and leaking it hands over the ability to ship as you. If a CI checkout genuinely
forces the file into the tree, add `*.keystore` to `.gitignore` as a backstop — but treat that
as a last resort, not the arrangement to aim for.

If the app also ships to Google Play, generate a **second, different** keystore for that store.

## Which signing path applies

Decide this before editing anything, because the two paths conflict.

| Project | Path |
| --- | --- |
| Expo with EAS-managed credentials | EAS holds the keystore. Skip the Gradle config entirely and go to [Expo and EAS](#expo-and-eas) |
| Expo building locally, or a project with a committed `android/` directory | Use the Gradle config below |
| Bare React Native | Use the Gradle config below |

In a prebuild-managed Expo project, `android/` is generated output: `npx expo prebuild --clean`
rewrites `build.gradle`, so a signing block added by hand disappears at the next prebuild and
can conflict with what Expo generates in the meantime. Check whether `android/` is committed and
whether `.gitignore` lists it before assuming an edit will survive.

## Gradle signing config

For local signing only — see the table above.

```gradle
android {
  signingConfigs {
    dappStore {
      // Absolute path from outside the repository, via a Gradle property or the environment.
      def keystorePath = findProperty("dappKeystorePath") ?: System.getenv("DAPP_KEYSTORE_PATH")
      if (keystorePath) {
        storeFile file(keystorePath)
        storePassword findProperty("dappKeystorePwd") ?: System.getenv("DAPP_KEYSTORE_PWD")
        keyAlias "my-app"
        keyPassword findProperty("dappKeyPwd") ?: System.getenv("DAPP_KEY_PWD")
      }
    }
  }
  buildTypes {
    release {
      signingConfig signingConfigs.dappStore
      // minifyEnabled defaults to false here on purpose — see Release-only failures
    }
  }
}
```

The `if` is not decoration. `file(null)` throws while Gradle is still configuring the project,
so an unset variable takes down every task including `assembleDebug`, and a build that breaks
the moment the keystore is absent is exactly what pushes someone to hardcode the path back into
the file. Guarded, an unset variable only leaves the release variant unsigned — caught by
`apksigner verify` and by the portal, and harmless to debug builds.

The path and both passwords come from `~/.gradle/gradle.properties` — the one in your home
directory, outside every repository — or from the environment, never from the build file.
`findProperty` also reads the project's own `gradle.properties`, and in a React Native project
`android/gradle.properties` is committed, so putting them there is the same mistake as putting
them in `build.gradle`. Both lookups are needed: `System.getenv` reads process environment
variables only and returns `null` for anything set in `gradle.properties`, so a config using it
alone silently fails for whichever half you chose. `findProperty` covers the properties file and
falls back to the environment for CI.

A password in `build.gradle` is a password in git history, and a hardcoded `storeFile` inside
the project is how the key itself ends up there.

## Expo and EAS

Add a dApp Store profile that forces an APK, since EAS defaults to a bundle:

```json
{
  "build": {
    "dapp-store": {
      "android": {
        "buildType": "apk"
      }
    }
  }
}
```

```bash
eas build --platform android --profile dapp-store
eas build --platform android --profile dapp-store --local
```

EAS can hold the keystore for you. If you let it, make sure the credential it manages for this
profile is not the same one backing a Google Play submission. A managed build arrives as a
download rather than at a path in the tree, but it is still an APK: the `apksigner` check below
applies to it unchanged, because verifying a signature needs the certificate in the file and not
the private key behind it. Download the artifact and run it. It is the only way to notice before
uploading that EAS signed with a different keystore than the last release, and a key change on
an update is unrecoverable.

## Build and verify

The build step is for local signing; an EAS-managed build is covered above. The verify step
applies to both.

```bash
(cd android && ./gradlew :app:assembleRelease)
```

The subshell keeps the `cd` from leaking, so the verify command below still resolves from the
repository root. Output: `android/app/build/outputs/apk/release/app-release.apk`.

```bash
apksigner verify --print-certs android/app/build/outputs/apk/release/app-release.apk
```

Point it at a downloaded EAS artifact the same way. Check the printed certificate fingerprint
against the key you intended. On an update this is worth doing every time — an APK signed with
the wrong key is rejected, the fingerprint is the only way to see that before uploading, and
comparing the SHA-256 against the previous release is what catches a keystore that changed
underneath you.

## Release-only failures

A release build exercises paths a debug build never touches, so this class of bug appears at the
worst moment. In rough order of likelihood:

| Symptom | Cause and fix |
| --- | --- |
| Crashes on launch in release, fine in debug | **If `minifyEnabled true` on the release variant:** missing ProGuard rules. Set it to `false` to confirm, then fix with `-keep` rules rather than shipping unminified. **If minification is already off** — as in the config above — ProGuard is not the cause; look at the rows below |
| Wallet connection silently fails in release only | Same cause and same split. R8 strips or renames classes that Mobile Wallet Adapter and other native modules reach reflectively, so this only applies when minification is enabled |
| `.aab` produced instead of `.apk` | `bundleRelease` instead of `assembleRelease`, or an EAS profile without `"buildType": "apk"` |
| Upload rejected as unsigned | `signingConfig` not attached to the `release` build type |
| Portal reports no matching app | APK package name differs from the listing. Check `expo.android.package` in `app.json` or `app.config.*` on Expo, or `applicationId` in `android/app/build.gradle` on a bare project |
| `No space left on device` | Release native builds need far more disk than debug. Clear the Gradle and CMake caches and retry |

### ProGuard rules when minifying

If you do enable `minifyEnabled true`, keep the classes that are resolved by name at runtime:

```proguard
-keep class com.solana.mobilewalletadapter.** { *; }
-keep class com.solanamobile.** { *; }
```

That covers Mobile Wallet Adapter itself. Any other dependency doing reflection — JSON
serialisers binding to model classes, native modules registered by name — needs its own
`-keep`, and the library's own docs are the source for those rules.

Build the release variant and exercise a real wallet connection before submitting. Minification
problems do not show up in unit tests, only in a release build on a device.
