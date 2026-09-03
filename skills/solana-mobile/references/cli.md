# solana-mobile CLI reference

The complete command surface of the `solana-mobile` CLI. [SKILL.md](../SKILL.md) covers the
commands used in the normal build loop; this file covers everything, including the flags worth
knowing when a command needs to run unattended.

Run it without installing, and always with `@latest` so the runner does not reuse an older
cached version:

```bash
npx solana-mobile@latest <command>
```

`pnpm dlx solana-mobile@latest` and `bunx solana-mobile@latest` are the equivalents. Match
whichever package manager the project already uses. There is no global install.

| Command | Does |
| --- | --- |
| `create` | Scaffold a new Solana Mobile project from a template |
| `device` | Work with connected devices and emulators over adb |
| `doctor` | Check the local development toolchain |
| `emulator` (`emu`) | Manage Android emulators and system images |
| `localnet` | Run a local validator and forward its ports to devices |
| `playground` | Serve a wallet testing page and open it on a device |
| `templates` | Maintain a template repository (template authors only) |
| `webshell` | Wrap a web app in an Android WebView shell |

Every command accepts `--skip-version-check`, which suppresses the update check. Worth passing
in CI and scripted runs so an unreachable registry cannot add noise to the output.

## create

```bash
npx solana-mobile@latest create my-app --template expo-kit-wallet
```

Interactive without arguments. See [SKILL.md](../SKILL.md#choosing-a-template) for which
template to pick.

| Option | Effect |
| --- | --- |
| `-d, --dry-run` | Show what would happen, write nothing |
| `--list-template-ids` | Print template ids as a JSON array |
| `--list-templates` | Print the template catalog |
| `--list-versions` | Report local Anchor, AVM, Rust, and Solana versions |
| `--minimal` | Use the minimal template (rejected together with `--template`) |
| `--pm, --package-manager <manager>` | Package manager to use |
| `--skip-git` | Do not initialise a git repository |
| `--skip-init` | Do not run the template's init script |
| `--skip-install` | Do not install dependencies |
| `-t, --template <id>` | Pick a template non-interactively |
| `-v, --verbose` | Verbose output |

Flags the CLI does not recognise are forwarded to the selected template as boolean options, so
`create my-app --minimal --reset-project` passes `--reset-project` through. A `--template` value
starting with `/`, `./`, or `../` is treated as a local template directory rather than a GitHub
shorthand.

## device

Everything here talks to devices over adb, so `adb` must be on `PATH` and the device authorised.
`doctor` verifies both.

Where a command takes a target: no flag uses the only connected device, or prompts when several
are connected; `--device <serial>` names one; `--all` (on `install` and `tune`) applies to every
connected device. `--all` and `--device` are mutually exclusive. `emulator tune` does **not**
follow this rule — see [emulator tune](#emulator-tune).

### device install

```bash
npx solana-mobile@latest device install                     # pick from the catalog
npx solana-mobile@latest device install fakewallet          # install a catalog APK by name
npx solana-mobile@latest device install app.apk ./builds/   # local files and directories
```

**This is how you get a wallet onto an emulator.** `fakewallet` is the Mobile Wallet Adapter
test wallet, and a fresh emulator has no wallet at all, so MWA has nothing to hand off to until
it is installed. Catalog APKs are downloaded from GitHub releases and cached under
`~/.cache/solana-mobile/apks/` (`$XDG_CACHE_HOME` is honoured), so repeat installs skip the
network.

| Option | Effect |
| --- | --- |
| `--all` | Install on every connected device |
| `--device <serial>` | Target a device serial |
| `--downgrade` | Allow version downgrades (`adb install -d`) |
| `--force` | Re-download catalog APKs even when cached |
| `--grant` | Grant all runtime permissions (`adb install -g`) |
| `--list` | Print the catalog and exit |
| `-v, --verbose` | Verbose output |

Installs continue past a failure and report a summary, exiting non-zero if anything failed.

### device list

```bash
npx solana-mobile@latest device list
```

Every adb device with its state and a human-readable name — the AVD name for emulators, the
product model for physical devices. `--json` prints a stable report worth parsing when a script
needs to pick a serial.

### device open

```bash
npx solana-mobile@latest device open http://localhost:3000
npx solana-mobile@latest device open 3000          # bare port means http://localhost:<port>
npx solana-mobile@latest device open myapp://claim # deep links work too
```

Replaces `adb -s <serial> shell am start -a android.intent.action.VIEW -d <url>`. For a
`localhost` URL with an explicit port it runs `adb reverse` first, so a dev server on this
machine is reachable from a USB device. An existing reverse on that port is left alone rather
than clobbered — it may be localnet's.

| Option | Effect |
| --- | --- |
| `--device <serial>` | Target a device serial |
| `--no-forward` | Do not create an adb reverse for localhost URLs |
| `-v, --verbose` | Explain each URL and port forwarding decision |

With no URL it offers the device's existing reverses as suggestions, which are exactly the
localhost ports the device can reach.

### device tune

```bash
npx solana-mobile@latest device tune --all --yes
```

Silences the first-contact noise that trips up automation on a fresh device or AVD: animations,
Chrome's first-run and notification prompts, the lock screen, system notifications, autofill,
touch sounds. **Run this before driving a device with an automation agent** — most of what looks
like a broken flow on a fresh emulator is one of these dialogs sitting on top of the app.

| Option | Effect |
| --- | --- |
| `--all` | Tune every connected device |
| `--device <serial>` | Target a device serial |
| `-y, --yes` | Apply every tweak without prompting |

Without `-y` it shows a picker with every tweak pre-selected, so `Enter` applies the lot. That
prompt blocks an unattended run, so always pass `-y` in a script. Physical devices are accepted
here; a tweak the device refuses — a phone with a screen lock keeps its lock screen — is
reported as skipped rather than failing the run.

The tweaks: `animations-off`, `autofill-off`, `chrome-notifications-off`, `chrome-quiet`,
`keyboard-feedback-off`, `lockscreen-off`, `provisioning-complete`, `screen-awake`,
`stylus-handwriting`, `system-notifications-off`.

## doctor

```bash
npx solana-mobile@latest doctor
```

Checks the operating system, JavaScript runtimes and package managers, Java, the Android SDK
and its tools, and connected devices, then prints a readiness summary per workflow — project
creation, Android build, emulator, physical device — with recommendations for anything missing.

| Option | Effect |
| --- | --- |
| `--json` | Print a stable JSON report |
| `--verbose` | Include resolved paths and diagnostic details |

Exits non-zero when something needed is missing, so it works as a CI gate. Run it first
whenever a build fails for reasons that are not obviously in app code — but see
[troubleshooting.md](troubleshooting.md) for the one case where a green `doctor` still leaves
Gradle unable to find the SDK.

## emulator

`emu` is an alias for `emulator`. Subcommands: `create`, `delete`, `images`, `list`, `start`,
`status`, `stop`, `tune`.

```bash
npx solana-mobile@latest emu list                            # installed AVDs
npx solana-mobile@latest emu status                          # running ones, with serials
npx solana-mobile@latest emu create local_phone --device pixel_9 --start --tune
npx solana-mobile@latest emu start my_phone
npx solana-mobile@latest emu stop my_phone
```

`emu status` is the command to reach for when you need an AVD name: `expo run:android --device`
wants the name from its `name` column, not the adb serial.

### emulator create

Creates or updates an AVD, installing a system image if one is missing. Interactive without
arguments.

| Option | Effect |
| --- | --- |
| `--data-size <size>` | Data partition size |
| `--device <profile>` | Android device profile id, e.g. `pixel_9` |
| `--profile <profile>` | Solana Mobile emulator profile |
| `--ram-mb <mb>` | RAM size in MB |
| `--sdcard-size <size>` | SD card size |
| `--sdk-root <path>` | Android SDK root |
| `--start` | Start the emulator after creating it |
| `--system-image <package>` | Android system image package |
| `--tune` | Apply the tweaks after booting (requires `--start`) |
| `-v, --verbose` | Verbose output |
| `--vm-heap-mb <mb>` | VM heap size in MB |

### emulator delete

```bash
npx solana-mobile@latest emu delete old_phone
```

Takes any number of names and accepts `--sdk-root`. Idempotent: deleting an AVD that is not
installed reports it and exits 0, so "remove any leftover, then create" needs no probe first.

### emulator images

`install`, `list`, and `delete` for Android system images. `install` takes `--all` to show every
available image rather than the recommended shortlist; `install` and `delete` take `-v`; all
three take `--sdk-root`.

### emulator start

Starts an AVD, prompting for one when no name is given. `--sdk-root` and `--tune`.

### emulator tune

```bash
npx solana-mobile@latest emu tune my_phone -y
```

The same tweaks as [`device tune`](#device-tune), addressed by AVD name or serial. **Tuning is
opt-in.** `emu start` and `emu create --start` apply the tweaks only when passed `--tune`, and
that form is non-interactive.

**Give this one a target in a script.** Unlike `device tune`, it has no single-candidate
shortcut: with no positional argument it opens an emulator picker whenever any emulator is
running, one or many, and `-y` does not suppress it — that flag skips the tweak multiselect
only. With no emulator running it prints a hint and exits without tuning. A name that matches
no running emulator is an error, and one that matches more than one asks for a serial.

Physical device serials are refused here — the target must report an emulator property before
any tuning command runs. Use `device tune` for a real phone.

## localnet

```bash
npx solana-mobile@latest localnet start
```

Gets a local validator serving and forwards its ports to every connected device, so an app on
the device reaches `localhost:8899` as if the validator ran there. Subcommands: `check`,
`forward`, `logs`, `start`, `status`, `stop`. Bare `localnet` is `localnet start`.

`start` picks one of three paths rather than always running `docker run`. A localnet container
it started already is reused. Otherwise it probes the RPC port first: something already
answering there — a native validator, or one started by hand — is attached to, which needs no
Docker at all and avoids failing on the port bind. Only when neither holds does it start a
container, and that path is the one that requires Docker. A stopped container of its own it
removes first; an unlabelled namesake it refuses to touch.

`start`, `check`, `forward`, `status`, and `stop` share the target options, and accept them on
either side of the subcommand:

| Option | Effect |
| --- | --- |
| `--device <serial>` | Target a device serial (repeatable) |
| `--engine <engine>` | Validator engine: `surfpool` or `test-validator` |
| `--port <port>` | Host port for the RPC endpoint |
| `--studio-port <port>` | Host port for the Studio UI |
| `--ws-port <port>` | Host port for the WebSocket endpoint |

Per subcommand:

| Subcommand | Options |
| --- | --- |
| `check` | `--json`, `--open` (also open the Studio UI on the device) |
| `forward` | `--watch` |
| `logs` | `--lines <count>` |
| `start` | `--detach`, `--image <image>`, `--no-watch` |
| `status` | `--json` |

`localnet check` is the command that answers "why can the app not reach my validator" — it
verifies reachability from every device rather than just from this machine. Plug in a device
after the validator is already running and its ports are not forwarded yet; `localnet forward`
fixes that, and `start` keeps watching for device changes unless `--no-watch` is passed.

## playground

```bash
npx solana-mobile@latest playground
npx solana-mobile@latest playground --cluster localnet
```

Serves a bundled wallet testing page, forwards it to a device, opens it in the device browser,
and streams every MWA interaction back to the terminal until interrupted. It covers connect,
sign in (SIWS), sign message, sign transaction, and sign and send.

**Reach for this before scaffolding an app to test a wallet.** It is the fastest way to
establish whether a signing failure is in the app or in the wallet and device setup — if the
playground cannot sign either, the app is not the problem. It needs an MWA wallet on the device;
`device install fakewallet` puts one there.

| Option | Effect |
| --- | --- |
| `--cluster <cluster>` | `devnet` (default), `localnet`, `mainnet`, or `testnet` |
| `--device <serial>` | Target a device serial |
| `--no-open` | Print the URL instead of opening it on the device |
| `--port <port>` | Host port for the playground server |
| `--url <url>` | Custom RPC URL for the selected cluster |
| `-v, --verbose` | Verbose output |

Mainnet always needs `--url`: the page runs in the device browser, and Solana's public mainnet
endpoint answers browser-origin requests with `403`. With `--cluster localnet`, start `localnet`
first. The device always opens port 4747; `--port` moves the host side of the reverse.

## templates

Maintains a template repository such as [solana-mobile/templates](https://github.com/solana-mobile/templates),
the source of the templates `create` uses. Only relevant when authoring templates, not when
building an app.

| Subcommand | Does |
| --- | --- |
| `check` | Verify generated template artifacts are up to date |
| `generate` | Generate template artifacts |
| `sync <target>` | Sync git-tracked templates to another repository |

All three take `--root <path>`. `sync` also takes `--dry-run` and `--force`, the latter syncing
even when the target has uncommitted changes, which may overwrite or remove files there.

## webshell

Generates and builds an Android WebView wrapper around an existing web app or PWA. This is a
packaging path for a web app, not a React Native app — the wrapper ships a WebView, not the RN
runtime, so nothing in these skills about Expo builds applies to it.

The generated shell does handle Mobile Wallet Adapter: it forwards `solana-wallet:` navigations
to the installed wallet as a `VIEW` intent, and dispatches a synthetic `blur` event afterwards
because the MWA web library detects the wallet handoff through `window.blur`, which a WebView
never fires on its own. It leaves subframe navigation alone so cross-origin iframe SDKs such as
Privy keep working.

```bash
npx solana-mobile@latest webshell init ./my-shell --url https://example.com
npx solana-mobile@latest webshell build ./my-shell
```

`init` takes `--app-name`, `--application-id`, `--force`, `--keystore-alias`, `--keystore-path`,
`--manifest <path-or-url>` (a web `manifest.json` or a Bubblewrap `twa-manifest.json`), `--url`,
`--version-code`, and `--version-name`. `build` takes `--keystore-alias`, `--keystore-path`, and
`--stacktrace`.
