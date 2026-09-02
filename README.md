# Solana Mobile dev skills

Agent skills for building Solana apps on Android with Expo and React Native. These follow the
[Agent Skills](https://agentskills.io) convention — a `SKILL.md` per skill directory — so they
work with Claude Code, Codex, OpenCode, Cline, Amp, and the other agents the installer below
supports.

The repository is also packaged as an [Agent Plugin](https://agent-plugins.org): the root
[`plugin.json`](plugin.json) manifest plus the `skills/` directory make it a portable plugin
that compatible clients can discover and load directly.

## Skills

| Skill | What it covers |
| --- | --- |
| [`integration-privy`](skills/integration-privy/SKILL.md) | Privy authentication over Mobile Wallet Adapter, via Sign-In-With-Solana |
| [`seeker-connect`](skills/seeker-connect/SKILL.md) | Seeker Connect: web dapps talking to the Seeker's built-in wallet |
| [`seeker-domains`](skills/seeker-domains/SKILL.md) | `.skr` domain resolution in both directions, with server and client integration |
| [`seeker-genesis-token`](skills/seeker-genesis-token/SKILL.md) | Seeker device ownership via SGT verification and Sign-in-with-Solana |
| [`solana-mobile`](skills/solana-mobile/SKILL.md) | Project scaffolding, templates, emulators, development builds, toolchain checks |
| [`solana-mobile-wallet`](skills/solana-mobile-wallet/SKILL.md) | Mobile Wallet Adapter: connect, disconnect, sign, send |

Each skill is a self-contained directory: a `SKILL.md` with the procedure, and `references/`
with detail the agent loads only when it needs it. That keeps the up-front context cost small
while the long-form material stays available.

Skills covering a third-party service are prefixed `integration-`, so they group together in
a listing and stay distinguishable from the first-party ones.

## Install

Use [`skills`](https://github.com/vercel-labs/skills), the same installer
`npx solana-mobile create` uses to add the Solana dev skill:

```bash
npx -y skills add solana-mobile/solana-mobile-skills
```

That prompts for which skills and which agents. To take everything without prompts:

```bash
npx -y skills add solana-mobile/solana-mobile-skills --all
```

Skills land in `.agents/skills/`, which most agents read directly, and are symlinked into the
agent-specific locations that need it. A `skills-lock.json` records the source and a content
hash of each skill, so installs are reproducible and reviewable in a diff.

Useful flags:

```bash
npx -y skills add solana-mobile/solana-mobile-skills -l          # list without installing
npx -y skills add solana-mobile/solana-mobile-skills -g          # install globally
npx -y skills add solana-mobile/solana-mobile-skills -s solana-mobile-wallet
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
- "Add Privy login to my Solana mobile app"

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

Three checks run in CI, and all of them run locally. Validate against the
[Agent Skills spec](https://agentskills.io/specification) with Anthropic's `quick_validate.py`
from [anthropics/skills](https://github.com/anthropics/skills), vendored at
[`scripts/validate-skill.py`](scripts/validate-skill.py) and wrapped to add the checks it skips,
such as the skill name matching its directory. Needs `python3` with PyYAML (`pip install pyyaml`):

```bash
./scripts/validate-skills.sh
```

Then check that every relative link resolves and stays inside its skill directory, which the
spec validator does not cover:

```bash
./scripts/check-links.sh
```

CI also validates [`plugin.json`](plugin.json) against the
[Agent Plugins schema](https://agent-plugins.org/schemas/1.0.0/plugin.schema.json). To run
that locally:

```bash
curl -sfL https://agent-plugins.org/schemas/1.0.0/plugin.schema.json -o /tmp/plugin.schema.json && npx -y ajv-cli@5 validate --spec=draft2020 -s /tmp/plugin.schema.json -d plugin.json
```

Beyond what those enforce, skill content should stay portable across agents:

- Frontmatter carries `name` and `description`; `name` must match the directory name
- Relative links only, never pointing outside the skill's own directory — a skill directory is
  the unit of distribution, so an escaping link breaks once the skill is installed alone
- No host-specific tool names in the prose — describe the action, not the tool
- Keep `SKILL.md` under 500 lines and push detail into `references/`, so activation stays cheap

Issues and pull requests welcome. Prompts always have room to improve.
