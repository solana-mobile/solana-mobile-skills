# Solana Mobile Dev Skills

Claude Code skills for building Solana Mobile apps.

## Available Skills

### Mobile Wallet Adapter (`mwa/`)

Integrates Mobile Wallet Adapter (MWA) for wallet connection and transaction signing in React Native Expo apps using [@wallet-ui/react-native-web3js](https://wallet-ui.dev/).

All MWA skills are located in the `mwa/` directory:

| Folder | Skill | Description |
|--------|-------|-------------|
| `mwa/mobile-wallet-adapter-react-native` | Router | Assesses needs and delegates to sub-skills |
| `mwa/mwa-setup` | Setup | Install dependencies, polyfills, and provider configuration |
| `mwa/mwa-connection` | Connection | Add connect/disconnect wallet functionality |
| `mwa/mwa-transactions` | Transactions | Add SOL transfers and transaction signing |

**Trigger phrases:**
- "Add wallet connection to my React Native app"
- "Integrate Mobile Wallet Adapter"
- "Add a connect wallet button"
- "Send SOL transactions from my app"

### Solana Domains (`skr-address-resolution/`)

Add .skr domain name resolution to display human-readable names instead of wallet addresses.

**What it does:**
- Forward lookup: Resolve `.skr` domains to wallet addresses
- Reverse lookup: Resolve wallet addresses to `.skr` domain names
- Integrates with existing backend or creates minimal Express server

**Trigger phrases:**
- "Add .skr domain resolution to my app"
- "Display .skr names instead of wallet addresses"
- "Show user's .skr name in their profile"

### Seeker Genesis Token (`genesis-token/`)

Verify Seeker device ownership by checking for the Seeker Genesis Token (SGT) — a unique NFT minted once per Seeker device.

**What it does:**
- Proves wallet ownership via Sign-in-with-Solana (SIWS)
- Verifies wallet contains an SGT
- Backend verification to prevent spoofing

**Trigger phrases:**
- "Verify Seeker device ownership"
- "Gate content to Seeker owners"
- "Add SGT verification"
- "Implement anti-Sybil for Seeker"

### Seeker App Lifecycle (`seeker-app/`)

End-to-end skills for building a Seeker dApp: scaffold, Seeker-specific UX conventions, USDC/SOL payments via MWA, Seed Vault audience boundary, and dApp Store publishing. Complements the MWA skills above.

| Folder | Skill | Description |
|--------|-------|-------------|
| `seeker-app/seeker-app-builder` | Router | Assesses project state and routes through scaffold → MWA → tx → UX → publish |
| `seeker-app/seeker-app-scaffold` | Scaffold | `npm create solana-dapp` / `create-expo-app`, Android toolchain (JDK 17, adb), polyfills, `APP_IDENTITY` / `SOLANA_CHAIN` constants |
| `seeker-app/seeker-ux` | UX | One-tap approval, batched ixs, haptic ladder, AMOLED palette, 48/56 px tap targets, 120 Hz Reanimated v4 |
| `seeker-app/solana-pay-mobile` | Payments | SOL/USDC transfers signed via MWA, Solana Pay URL spec, RN-specific gotchas (`Buffer`, `address.toString()`) |
| `seeker-app/seed-vault` | Seed Vault | Audience-boundary skill — wallet developers only; routes dApp builders back to MWA |
| `seeker-app/dapp-store-publishing` | Publishing | APK sign (`keytool` + `assembleRelease`), `@solana-mobile/dapp-store-cli`, publisher wallet + App NFT, ProGuard footgun |

**Trigger phrases:**
- "Build a Seeker app"
- "Ship to the Solana dApp Store"
- "Scaffold a Solana Mobile RN app"
- "Add USDC payments to my Seeker app"
- "Sign and publish my APK"

## Installation

Copy the skill folders to your Claude Code skills directory:

```bash
# MWA skills
cp -r mwa/* ~/.claude/skills/

# Solana Domains skill
cp -r skr-address-resolution ~/.claude/skills/

# Genesis Token skill
cp -r genesis-token ~/.claude/skills/

# Seeker App Lifecycle skills
cp -r seeker-app/* ~/.claude/skills/
```

## Requirements

- React Native Expo project
- Development build (not Expo Go - MWA uses native modules)
- Android development environment

## Contributing

Improving skills is an iterative process—prompts can always be refined and enhanced. This repo is open to any issues raised or improvements suggested. Feel free to open an issue or submit a pull request if you have ideas for better prompts, additional features, or bug fixes.
