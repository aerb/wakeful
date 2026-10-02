# Wakeful: instructions for coding agents

Wakeful is a macOS menu-bar app that keeps the Mac awake for a set time, optionally with the lid
closed. Read this before building, installing or changing it. The human-facing overview is in
`README.md`.

## Before you start

Check the machine meets the requirements:

```sh
sw_vers -productVersion   # needs 14.0 or later
swift --version           # needs Swift 6.0 or later (Xcode 16+ or its Command Line Tools)
```

If Swift is missing, ask the user to install the Command Line Tools with `xcode-select --install`.
Don't try to install a toolchain yourself.

Also check whether something else is already holding the Mac awake:

```sh
pmset -g | grep SleepDisabled                               # 1 means some tool set the flag
ls ~/Library/Application\ Support/Wakeful/lid-session.json   # exists only while a Wakeful lid session runs
```

If `SleepDisabled` is `1` and there is no Wakeful session file, another tool (for example
Sleepless or Amphetamine) or the user set it. Tell the user: a Wakeful lid-closed session turns
this shared flag off when it ends.

## Install

1. Run the tests with `make test`, not plain `swift test`: the Makefile works around a toolchain
   bug that makes clean builds fail intermittently with "plugin for module 'TestingMacros' not
   found". All tests should pass. If the build fails with concurrency or
   other compiler errors, report the Swift version and the error to the user rather than
   rewriting code to get past it.
2. Tell the user an admin password prompt is coming, then run `scripts/install.sh`.
   - With a terminal, `sudo` asks in the terminal. Without one (the usual case for an agent), a
     macOS password dialog appears on the user's screen. The script waits for it.
   - The password is only needed to write `/etc/sudoers.d/wakeful`. Never ask the user to paste
     their password into the conversation.
   - Rerunning the script is safe. It skips the password step once the rule is in place.
3. Verify the install:

   ```sh
   pgrep -lx Wakeful                                          # app is running
   sudo -n -l /usr/bin/pmset -a disablesleep 1                # prints the command: sudoers rule works
   launchctl print gui/$UID/local.wakeful.watchdog | grep -E "state|last exit|run interval"
   ```

   Expect the watchdog's `last exit code = 0` and `run interval = 60 seconds`.
4. Tell the user to click the cup icon in the menu bar. If the Lid closed card says "Needs setup",
   the sudoers step didn't finish; rerun `scripts/install.sh`.

The script installs:

| What | Where |
| --- | --- |
| App (includes the watchdog binary) | `/Applications/Wakeful.app` (override with `APP_DIR=…`) |
| Sudoers rule: only `pmset -a disablesleep 0` and `1`, for this user | `/etc/sudoers.d/wakeful` |
| Watchdog LaunchAgent, runs every 60 s | `~/Library/LaunchAgents/local.wakeful.watchdog.plist` |
| Session record, only during a lid-closed session | `~/Library/Application Support/Wakeful/lid-session.json` |
| Watchdog log, written only when it acts | `~/Library/Logs/Wakeful/watchdog.log` |

## Updating an existing install

Reinstalling quits Wakeful, which ends any running session. Check first:

```sh
ls ~/Library/Application\ Support/Wakeful/lid-session.json 2>/dev/null && echo "lid session running"
pgrep -x Wakeful >/dev/null && echo "Wakeful running"
```

If a session is running, ask the user before running `scripts/install.sh`.

## Things not to do without asking the user

- Don't run `pmset -a disablesleep 0` or `1` yourself. The flag is system-wide and other tools
  may rely on it.
- Don't run the `kill -9` watchdog test from the README. It ends the user's session and turns the
  shared flag off.
- Don't edit files in `/etc/sudoers.d/` by hand, and don't touch other tools' rules there.
- Don't reinstall or quit Wakeful while a session is running.

## Uninstall

`scripts/uninstall.sh` removes the app, the LaunchAgent, the sudoers rule, settings and logs. It
needs the admin password the same way the install does.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `sudo: a terminal is required to read the password` | You have an old copy of the scripts. Use the current `scripts/install.sh`, or ask the user to run it in Terminal |
| Lid closed card says "Needs setup" | Rerun `scripts/install.sh` |
| Mac won't sleep after Wakeful quit | Check the watchdog log, then ask the user before running `sudo pmset -a disablesleep 0` |
| Launch at login shows an error | The app is ad-hoc signed; this can fail on some setups. Not needed for the app to work |

## Working on the code

```sh
make test    # Swift Testing suite for WakefulCore
make app     # build/Wakeful.app, ad-hoc signed
make dist    # build/wakeful.zip of the committed source, for sharing
swift build && WAKEFUL_SNAPSHOT_DIR=/tmp/wakeful-snaps .build/debug/Wakeful   # renders the UI to PNGs
```

- `Sources/WakefulCore`: session state machine, safety cutoffs, watchdog decision, session record,
  IOKit and `pmset` wrappers. All session logic lives here and is unit tested. Keep it that way:
  add a test in `Tests/WakefulCoreTests` for any change to how or when a session ends.
- `Sources/Wakeful`: the menu-bar app (AppKit status item, SwiftUI panel and Settings window).
- `Sources/WakefulWatchdog`: the launchd watchdog.
- The watchdog only ever acts when a Wakeful session record exists. Don't change that: without
  it, Wakeful would turn off `SleepDisabled` flags set by other tools.
- Look at the rendered PNGs after UI changes. The app has no UI tests.
