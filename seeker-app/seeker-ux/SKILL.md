---
name: seeker-ux
description: Seeker UX conventions for RN dApps. Triggers - "Seeker UX", "add haptics", "AMOLED palette", "one-tap approval", "120Hz animation".
---

# Seeker UX

## Use

- App runs, UX needs Seeker polish
- Add haptics / approval flow / 120 Hz animations
- Brand palette, safe area, tap targets

## Not

- App doesn't run → `seeker-app-scaffold` first
- iOS UX → these conventions are Seeker (Android, AMOLED, 120 Hz)
- Generic web design → use a frontend skill

## One-tap approve

Wallet biometric = only confirmation. No `Alert.alert("Are you sure?")` before `transact()`. Long-press confirm OK for destructive only.

## Batch ixs

Combine related ixs into one Transaction. Examples: mint+transfer, wrap+swap. Never chain `transact()` calls.

## Haptics

`expo-haptics`:

| Trigger | Type |
|---------|------|
| Tap | `Impact.Light` |
| Selection | `selectionAsync()` or `Impact.Medium` |
| Tx submit | `Impact.Heavy` |
| Tx success | `Notification.Success` |
| Tx error | `Notification.Error` |

No haptics on scroll/input.

## AMOLED palette

```ts
export const colors = {
  bg: '#000000',
  surface: '#0A0A0A',
  border: '#1A1A1A',
  primary: '#9945FF',
  accent: '#14F195',
  text: '#FFFFFF',
  textMuted: '#A1A1AA',
};
```

Pure `#000` only. Never `#111`.

## Tap targets

- Min 48×48 px interactive.
- Primary button: 56 px.
- Bottom nav: `paddingBottom: insets.bottom` via `react-native-safe-area-context`.

## 120 Hz

- Animate `transform` + `opacity`. Never `width/height/top`.
- `react-native-reanimated@4` (current). Needs companion dep `react-native-worklets`.
- Requires **New Architecture (Fabric)** — default in recent Expo SDKs.
- Stuck on Old Arch? Use `react-native-reanimated@3` (`reanimated-3` npm tag).
- Easing: `cubic-bezier(0.4, 0, 0.2, 1)`. Use `useAnimatedStyle` worklets. Never legacy `Animated`.

Install (Expo):

```bash
npx expo install react-native-reanimated react-native-worklets
```

Expo SDK 50+ ships the Worklets Babel plugin by default. Bare RN must add `react-native-worklets/plugin` to `babel.config.js`.

## RN pitfalls

- `account.address.toString()` only. Bare `{account.address}` = garbled text in `<Text>`.
- No `Buffer` in RN. Use `btoa(String.fromCharCode(...arr))` for base64.
- Polyfill `react-native-get-random-values` = first import in entry file. Wrong order → silent tx failures.

## Security floor

- No keys/mnemonics in app code or env.
- Sign only via MWA (`useMobileWallet` hook or raw `transact()`).
- Privacy policy required for dApp Store. Reuse from web if shared.

## Refs

- docs.solanamobile.com
- github.com/solana-mobile/mobile-wallet-adapter
