# Solana Mobile dev skills

Agent skills for building Solana apps on Android with Expo and React Native. These follow the
[Agent Skills](https://agentskills.io) convention — a `SKILL.md` per skill directory — so they
work with Claude Code, Codex, OpenCode, Cline, Amp, and the other agents the installer below
supports.

## Skills

| Skill | What it covers |
| --- | --- |
| [`seeker-domains`](skills/seeker-domains/SKILL.md) | `.skr` domain resolution in both directions, with server and client integration |
| [`seeker-genesis-token`](skills/seeker-genesis-token/SKILL.md) | Seeker device ownership via SGT verification and Sign-in-with-Solana |
| [`solana-mobile`](skills/solana-mobile/SKILL.md) | Project scaffolding, templates, emulators, development builds, toolchain checks |
| [`solana-mobile-wallet`](skills/solana-mobile-wallet/SKILL.md) | Mobile Wallet Adapter: connect, disconnect, sign, send |

Each skill is a self-contained directory: a `SKILL.md` with the procedure, and `references/`
with detail the agent loads only when it needs it. That keeps the up-front context cost small
while the long-form material stays available.

## Install

Use [`skills`](https://github.com/vercel-labs/skills), the same installer
`npx solana-mobile create` uses to add the Solana dev skill:

```bash
npx -y skills add solana-mobile/solana-mobile-dev-skill
```

That prompts for which skills and which agents. To take everything without prompts:

```bash
npx -y skills add solana-mobile/solana-mobile-dev-skill --all
```

Skills land in `.agents/skills/`, which most agents read directly, and are symlinked into the
agent-specific locations that need it. A `skills-lock.json` records the source and a content
hash of each skill, so installs are reproducible and reviewable in a diff.

Useful flags:

```bash
npx -y skills add solana-mobile/solana-mobile-dev-skill -l          # list without installing
npx -y skills add solana-mobile/solana-mobile-dev-skill -g          # install globally
npx -y skills add solana-mobile/solana-mobile-dev-skill -s solana-mobile-wallet
```

Then `skills list`, `skills update`, and `skills remove` manage what is installed.

To install by hand instead, copy any `skills/<name>/` directory into your agent's skills
directory. Each one is self-contained, with no links outside its own folder.

## Using them

Describe what you want; the agent picks the skill from its description. Things that trigger
these:

- "Create a new Solana mobile app"
- "Add a connect wallet button to my Expo app"
- "Send SOL from my React Native app"
- "Gate this screen to Seeker owners"
- "Show `.skr` names instead of wallet addresses"

In Claude Code you can also invoke one directly, for example `/solana-mobile-wallet`.

## Requirements

- An Expo React Native project
- **A development build — Expo Go does not work.** Mobile Wallet Adapter needs native Android
  modules that Expo Go does not bundle. This is the most common cause of "the wallet
  integration does not work".
- An Android development environment. `npx solana-mobile@latest doctor` checks it.

Android only. iOS builds run, but have no wallet support.

## Kit first

The skills write `@solana/kit` with `@wallet-ui/react-native-kit` — the current client library,
and what `npx solana-mobile create` scaffolds. Patterns follow the
[`expo-kit-minimal`](https://github.com/solana-mobile/templates/tree/main/mobile/expo-kit-minimal)
template.

They fall back to legacy `@solana/web3.js` with `@wallet-ui/react-native-web3js` in two cases:
the app already uses it as its Solana client, or you ask for it directly. So the skills read
`package.json` before writing wallet code, and match what is there rather than mixing stacks —
provider props, hook return values, and transaction construction all differ, and code from one
silently fails on the other.

## The CLI

These skills lean on the [`solana-mobile` CLI](https://github.com/solana-mobile/solana-mobile-cli)
rather than restating setup steps that go stale:

```bash
npx solana-mobile@latest create      # scaffold from the template catalog
```

```bash
npx solana-mobile@latest doctor      # check the local toolchain
```

```bash
npx solana-mobile@latest emu start   # manage Android emulators
```

## Scope

Mobile and Seeker-specific work only. For general Solana development — Anchor and Pinocchio
programs, Codama client generation, testing, security review — use the Solana Foundation's
[`solana-dev`](https://github.com/solana-foundation/solana-dev-skill) skill. `npx
solana-mobile create` installs it into `.agents/skills/solana-dev/` in every scaffolded
project, so it is usually already present. These skills sit alongside it rather than
duplicating it.

## Contributing

Skill content should stay portable across agents:

- Frontmatter carries `name` and `description` only, and `name` must match the directory name
- Relative links only, never pointing outside the skill's own directory
- No host-specific tool names in the prose — describe the action, not the tool

Issues and pull requests welcome. Prompts always have room to improve.
