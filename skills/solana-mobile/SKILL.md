---
name: solana-mobile
description: Scaffold, configure, and troubleshoot Solana Mobile apps for Android using the solana-mobile CLI, Expo, and React Native. Use when creating a new Solana mobile app, picking a template, adding Solana to an existing Expo app, checking the Android toolchain, managing Android emulators or connected devices, installing a wallet APK for testing, running a local validator the device can reach, or producing a development build.
---

# Solana Mobile projects

Set up and maintain Solana Mobile apps. The `solana-mobile` CLI does the scaffolding,
environment checks, and emulator management — prefer it over hand-rolled setup.

Run it without installing:

```bash
npx solana-mobile@latest --help
```

`pnpm dlx solana-mobile@latest` and `bunx solana-mobile@latest` are the equivalents. Match
whichever package manager the project already uses, and keep `@latest` so the runner does not
reuse an older cached version.

| Command | Use for |
| --- | --- |
| `create` | [Scaffolding a new project](#create-a-new-project) |
| `device` | [Installing APKs, opening URLs, preparing a device](#work-with-a-connected-device) |
| `doctor` | [Checking the toolchain](#check-the-environment) |
| `emulator` (`emu`) | [Creating and running emulators](#manage-android-emulators) |
| `localnet` | [A local validator the device can reach](#run-a-local-validator) |
| `playground` | [Testing a wallet without building an app](#test-a-wallet-without-an-app) |
| `templates` | Maintaining a template repository — template authors only |
| `webshell` | Wrapping an existing web app in an Android WebView shell |

Every flag of every command: [references/cli.md](references/cli.md). Do not guess at flags —
the CLI ships its own help, and `--help` on any command is authoritative.

## Non-negotiable constraint

**Mobile Wallet Adapter requires a development build. Expo Go will not work** — MWA depends
on native Android modules that Expo Go does not bundle. If someone reports wallet
connection failing in Expo Go, that is the cause; there is no workaround, they need
`expo run:android`.

Android is the only platform with wallet support. iOS builds run, but no MWA.

## First: work out which situation you are in

| Situation | Do this |
| --- | --- |
| No project yet | [Create a new project](#create-a-new-project) |
| Existing Expo app, no Solana | Read [references/add-to-existing-app.md](references/add-to-existing-app.md) |
| Project exists, build or toolchain broken | [Check the environment](#check-the-environment) |
| Project exists, needs wallet features | Use the `solana-mobile-wallet` skill |
| Wallet connect or signing needs testing | [Test a wallet without an app](#test-a-wallet-without-an-app) |

## Create a new project

```bash
npx solana-mobile@latest create
```

Interactive by default. To skip the prompts, name the project and template:

```bash
npx solana-mobile@latest create my-app --template expo-kit-wallet
```

Useful flags:

| Flag | Effect |
| --- | --- |
| `-t, --template <id>` | Pick a template non-interactively |
| `--pm <manager>` | Package manager to use |
| `--minimal` | Use the minimal template |
| `--list-templates` | Print the template catalog |
| `--list-template-ids` | Print template ids as a JSON array |
| `--skip-install` | Do not install dependencies |
| `--skip-git` | Do not initialise a git repo |
| `-d, --dry-run` | Show what would happen, write nothing |

### Choosing a template

Templates come in two families. **Pick an `expo-kit-*` template.** `@solana/kit` is the current
Solana client library, and these are the templates the CLI maintains most actively.

Reach for `expo-web3js-*` only when the user is deliberately continuing an existing
`@solana/web3.js` codebase, or asks for it by name. If they ask without a reason, say kit is the
better starting point before going along with it — a new app on web3.js starts life needing a
migration.

`expo-kit-minimal` is the clearest reference for how the kit pieces fit together, and worth
reading even when building on a different template.

| Template | Stack | Use for |
| --- | --- | --- |
| `expo-kit-wallet` | Kit + MWA + Uniwind | **Best default.** Wallet connect, sign, send already wired |
| `expo-kit-minimal` | Kit | Bare starting point, no UI kit |
| `expo-kit-uniwind` | Kit + Uniwind | Tailwind-style styling, no wallet yet |
| `expo-kit-privy` | Kit + Privy + Uniwind | Privy auth instead of, or alongside, MWA |
| `expo-web3js-wallet` | web3.js + MWA | Legacy wallet app |
| `expo-web3js-paper` | web3.js + RN Paper | Legacy, Material UI |
| `expo-web3js-minimal` | web3.js | Legacy bare starting point |

Template ids are also accepted in full `gh:solana-mobile/templates/mobile/<name>` form.
Re-run `--list-templates` rather than trusting this table if a template seems missing — the
catalog ships with the CLI, not with this skill.

### After scaffolding

```bash
cd my-app && npm run android
```

That runs `expo run:android`, which builds and installs the development build. The first
Android build is slow (Gradle cold start); later builds reuse the cache.

## Check the environment

Before debugging a build failure, check the toolchain:

```bash
npx solana-mobile@latest doctor
```

It reports on the local Android and Node toolchain with recommendations for anything
missing. `--json` gives a stable report worth parsing when you need to branch on a specific
check; `--verbose` adds resolved paths and diagnostics.

Run `doctor` first whenever a build fails for reasons that are not obviously in app code.

## Manage Android emulators

```bash
npx solana-mobile@latest emu list
npx solana-mobile@latest emu status
npx solana-mobile@latest emu create
npx solana-mobile@latest emu start my_phone
npx solana-mobile@latest emu stop my_phone
```

`emu` is an alias for `emulator`. Subcommands: `create`, `delete`, `images`, `list`, `start`,
`status`, `stop`, `tune`. System images live under `emu images` (`install`, `list`, `delete`).

Create a named emulator on a specific device profile:

```bash
npx solana-mobile@latest emu create local_phone --device pixel_9
```

### Prepare a fresh emulator

A newly created AVD is not ready for wallet work: it is not running, its first-run dialogs are
still armed, and it has no wallet app. Boot it tuned, then install one — in that order, since
`device install` needs a booted device to install onto:

```bash
npx solana-mobile@latest emu start local_phone --tune
npx solana-mobile@latest device install fakewallet
```

`--tune` disables the animations, first-run dialogs, lock screen, and notifications that
otherwise sit on top of the app on a fresh AVD. Tuning is opt-in — `emu start` and
`emu create --start` apply it only when passed `--tune` — and in that form it is
non-interactive, which is what makes it the one to reach for in a script. `emu create` takes
`--start --tune` to do all of this at creation time.

`device install fakewallet` puts the Mobile Wallet Adapter test wallet on the running emulator.
Without a wallet app, MWA has nothing to hand off to and connect silently does nothing — the
most common cause of "connect does nothing on the emulator".

Anything gated on the Seeker Genesis Token still needs a real Seeker device; an emulator cannot
hold one. See the `seeker-genesis-token` skill.

## Work with a connected device

`device` covers everything that goes over adb, for emulators and physical phones alike.

```bash
npx solana-mobile@latest device list                       # serials, states, names
npx solana-mobile@latest device install fakewallet         # catalog APK
npx solana-mobile@latest device install ./app-release.apk  # local file
npx solana-mobile@latest device open http://localhost:3000 # opens on the device
npx solana-mobile@latest device tune --all -y              # prepare for automation
```

`device open` creates the `adb reverse` for a localhost URL itself, so a dev server on this
machine is reachable from a USB-connected phone. Prefer it to hand-written `adb reverse` plus
`am start` incantations.

`device tune` and `emu tune` apply the same tweaks but differ in two ways, and the second one
bites in scripts. `device tune` accepts physical devices, takes `--device <serial>` or `--all`,
and falls back to the only connected device. `emu tune` refuses non-emulator serials, takes the
AVD name or serial as a positional argument, and opens a picker whenever it is given none — even
with exactly one emulator running, and even under `-y`, which skips the tweak prompt and not the
emulator one. Name the target in anything unattended: `emu tune local_phone -y`.

## Run a local validator

```bash
npx solana-mobile@latest localnet start
npx solana-mobile@latest localnet check
```

`localnet start` gets a validator serving on the host and forwards its ports to every connected
device, so the app reaches `localhost:8899` as if the validator ran on the device. It reuses a
localnet container it already started, attaches to a validator already answering on those ports
— a native one, needing no Docker at all — and starts a container only when neither is there.
`check`
verifies reachability from each device — which is the question to ask when an app cannot see a
validator that is plainly running on this machine.

`localnet forward` re-applies the forwards after plugging in a new device, and `logs`, `status`,
and `stop` do what they say.

## Test a wallet without an app

```bash
npx solana-mobile@latest playground
```

Serves a wallet testing page, opens it on the device, and streams every MWA interaction back to
the terminal: connect, sign in (SIWS), sign message, sign transaction, sign and send. It runs
against devnet by default; `--cluster localnet` points it at the `localnet` validator, and
mainnet needs your own `--url` because the public endpoint rejects browser-origin requests.

**Use this to split an app bug from a setup bug.** If the playground cannot sign either, the
problem is the wallet or the device, not the code being debugged. It needs an MWA wallet
installed — `device install fakewallet` if there is none.

## Reference material

- [references/cli.md](references/cli.md) — every `solana-mobile` command and flag, including
  `templates` and `webshell`
- [references/add-to-existing-app.md](references/add-to-existing-app.md) — wiring Solana
  into an Expo app that already exists: crypto polyfill, providers, dependencies
- [references/troubleshooting.md](references/troubleshooting.md) — build, polyfill, and
  emulator failures with known causes

## Related skills

- `solana-mobile-wallet` — connecting wallets, signing, sending transactions
- `seeker-genesis-token` — verifying Seeker device ownership
- `seeker-domains` — `.skr` domain name resolution

For general non-mobile Solana work — Anchor or Pinocchio programs, Codama client generation,
testing, security review — use the Solana Foundation's `solana-dev` skill instead. `create`
installs it into `.agents/skills/solana-dev/`, so a scaffolded project already has it.

## Links

- CLI source: https://github.com/solana-mobile/solana-mobile-cli
- Templates: https://github.com/solana-mobile/templates
- Solana Mobile docs: https://docs.solanamobile.com
