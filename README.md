# Wakeful

A macOS menu-bar app that keeps your Mac awake, including with the lid closed, for a set time that
always runs out.

It combines the two approaches of [Caffeine](https://github.com/domzilla/Caffeine) and
[Sleepless](https://github.com/Aboudjem/Sleepless):

| Mode | How it works | Needs setup |
| --- | --- | --- |
| Keep Awake | IOKit assertion that stops idle sleep, optionally keeping the display on | No |
| Keep Awake with Lid Closed | The same assertion plus `pmset -a disablesleep 1` | Yes, `scripts/install.sh` |

Every session has a timer: 15 minutes, 30 minutes, 1, 2, 4 or 8 hours. There is no "forever".

Click the cup in the menu bar to open Wakeful: pick a mode and a duration, then Start. While a
session runs, the menu bar shows the time left, and the panel shows a countdown ring with
**+15 min** (up to 8 hours left) and **Stop**. The gear opens Settings (⌘,), which also has
launch at login.

Requires macOS 14 or later. Built and tested on Apple Silicon.

## Install

Coding agents: follow [AGENTS.md](AGENTS.md) instead of this section.

```sh
scripts/install.sh
```

The script asks for your admin password once: in the terminal, or in a macOS dialog when there is
no terminal (for example when run from an agent). It:

1. builds `Wakeful.app` and copies it to `/Applications` (set `APP_DIR` to change that);
2. adds `/etc/sudoers.d/wakeful`, allowing your user to run exactly
   `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1` without a password;
3. loads the watchdog LaunchAgent, `~/Library/LaunchAgents/local.wakeful.watchdog.plist`;
4. opens Wakeful.

Keep Awake works without this; running `make app` and opening `build/Wakeful.app` is enough.

To remove everything, including the sudoers rule, the LaunchAgent and saved settings:

```sh
scripts/uninstall.sh
```

## Safety

`disablesleep` is a system-wide flag that stays on until something turns it off or the Mac reboots.
Wakeful turns it off in all of these cases:

| Trigger | Handled by |
| --- | --- |
| The timer runs out | App, with the watchdog as backup |
| Battery falls to the floor (default 15%, only while on battery) | App |
| Low Power Mode turns on | App |
| macOS reports serious or critical thermal pressure | App |
| You stop the session, quit, or the Mac sleeps or shuts down | App |
| The app is killed with SIGTERM, SIGINT or SIGHUP | App |
| The app crashes, is force-killed or hangs past its expiry | Watchdog, within 60 seconds |
| A flag left behind by an earlier crash | App, on its next launch |
| Reboot | macOS |

The cutoffs only apply to lid-closed sessions and can be changed under **Settings**.

### How the watchdog works

When a lid-closed session starts, Wakeful writes
`~/Library/Application Support/Wakeful/lid-session.json` (its pid and expiry time) *before* setting
the flag. Every 60 seconds launchd runs `wakeful-watchdog`, which turns the flag off when that
record has expired, is unreadable, or belongs to a process that is no longer Wakeful. It logs to
`~/Library/Logs/Wakeful/watchdog.log`.

The watchdog only acts when that record exists. A `SleepDisabled` flag set by something else, such
as Sleepless or `sudo pmset` by hand, is left alone. The flag is shared, though: when a Wakeful
lid-closed session ends, it turns the flag off even if another tool also wanted it on.

If Wakeful ever can't turn the flag off, it tells you. You can always do it yourself:

```sh
sudo pmset -a disablesleep 0
pmset -g | grep SleepDisabled   # should print 0, or nothing
```

Running hard with the lid shut reduces airflow. The thermal cutoff is there for that; leave it on.

## Development

```sh
make build   # swift build -c release
make test    # swift test
make app     # build/Wakeful.app, ad-hoc signed
make dist    # build/wakeful.zip of the committed source, for sharing
```

To check the UI without clicking through it, render the panel and Settings in each state, in light
and dark, to PNGs (debug builds only):

```sh
swift build && WAKEFUL_SNAPSHOT_DIR=/tmp/wakeful-snaps .build/debug/Wakeful
```

| Path | What's there |
| --- | --- |
| `Sources/WakefulCore` | Session state machine, cutoffs, watchdog decision, state file, IOKit and `pmset` wrappers |
| `Sources/Wakeful` | The menu-bar app: AppKit status item, SwiftUI panel and Settings |
| `Sources/WakefulWatchdog` | The launchd watchdog |
| `Tests/WakefulCoreTests` | Swift Testing tests for the core |
| `scripts/` | Install and uninstall |

### Checking lid-closed mode by hand

1. Start **Keep Awake with Lid Closed for 15 minutes**. `pmset -g | grep SleepDisabled` prints `1`.
2. Stop it. The same command prints `0`.
3. Start it again, then `kill -9 $(pgrep -x Wakeful)`. Within 60 seconds the flag goes back to `0`,
   and `watchdog.log` records why.

## License

MIT. See [LICENSE](LICENSE).
