# Solana Mobile dev skills

Skills for building Solana apps on Android with Expo and React Native. Each skill is a
self-contained directory under `skills/` holding a `SKILL.md` and its `references/`.

**Read the relevant `SKILL.md` in full before writing code.** The reference files under each
skill's `references/` are loaded on demand — follow the links from `SKILL.md` rather than
reading everything up front.

## Skill index

| Skill | Use when |
| --- | --- |
| [skills/integration-privy](skills/integration-privy/SKILL.md) | Adding Privy authentication over Mobile Wallet Adapter, via Sign-In-With-Solana |
| [skills/seeker-connect](skills/seeker-connect/SKILL.md) | Connecting a web dapp to the Seeker's built-in wallet, in the browser on the device |
| [skills/seeker-domains](skills/seeker-domains/SKILL.md) | Resolving or displaying `.skr` domain names in either direction |
| [skills/seeker-genesis-token](skills/seeker-genesis-token/SKILL.md) | Verifying Seeker device ownership, gating rewards, anti-Sybil checks |
| [skills/solana-mobile](skills/solana-mobile/SKILL.md) | Creating a project, picking a template, emulators, dev builds, toolchain problems |
| [skills/solana-mobile-wallet](skills/solana-mobile-wallet/SKILL.md) | Connecting a wallet, signing messages, sending transactions |

## Things that apply across all of them

**Mobile Wallet Adapter requires a development build. Expo Go will not work.** MWA depends on
native Android modules Expo Go does not bundle. This is the most common cause of "the wallet
integration does not work".

**Two client stacks exist and their APIs differ.** Check `package.json` before writing wallet
code:

- `@wallet-ui/react-native-kit` with `@solana/kit` — the current default
- `@wallet-ui/react-native-web3js` with `@solana/web3.js` — legacy

Provider props, hook return values, and transaction construction all differ between them.
Code from one does not work on the other.

**Use the CLI rather than hand-rolling setup.** `npx solana-mobile@latest` scaffolds projects,
checks the toolchain (`doctor`), and manages emulators (`emu`). Prefer it over manual
dependency and polyfill wiring.

**Android only.** iOS builds run but have no wallet support.

## Scope

Mobile and Seeker-specific work only.

For general Solana development — Anchor and Pinocchio programs, Codama client generation,
testing, security review, RPC work outside a mobile app — use the Solana Foundation's
[`solana-dev`](https://github.com/solana-foundation/solana-dev-skill) skill. `npx
solana-mobile create` installs it into `.agents/skills/solana-dev/` in every scaffolded
project, so it is usually already present. These skills are meant to sit alongside it, not
duplicate it.

Rough division: `solana-dev` covers Solana; the skills here cover the mobile and Seeker parts
`solana-dev` does not — Mobile Wallet Adapter, development builds, emulators, SGT, `.skr`.

## Repository layout

```
skills/<name>/SKILL.md          the skill: what to do, in order
skills/<name>/references/*.md   detail loaded on demand
plugin.json                     Agent Plugin manifest for the repository
scripts/check-links.sh          checks every relative link resolves and stays in its skill
scripts/validate-skills.sh      runs the vendored Agent Skills spec validator on every skill
```

`skills/` is the single source of truth.

## Contributing

Three checks run in CI, and all of them run locally. Validate against the Agent Skills spec
with Anthropic's `quick_validate.py`, vendored at `scripts/validate-skill.py` and wrapped to add
the checks it skips, such as the skill name matching its directory. Needs `python3` with PyYAML:

```bash
./scripts/validate-skills.sh
```

Then check that every relative link resolves and stays inside its skill directory, which the
spec validator does not cover:

```bash
./scripts/check-links.sh
```

Then validate the Agent Plugin manifest:

```bash
curl -sfL https://agent-plugins.org/schemas/1.0.0/plugin.schema.json -o /tmp/plugin.schema.json && npx -y ajv-cli@5 validate --spec=draft2020 -s /tmp/plugin.schema.json -d plugin.json
```
