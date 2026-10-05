# My Omarchy

A local pilot for understanding and recovering from agent-assisted changes to
your Omarchy machine. Browse **Plugins**, **Fixes**, **Customizations**, and
**Activity**, then discuss a record, investigate a problem, or ask your default
agent to uninstall a plugin.

## What works

- Imports `~/.config/omarchy/SYSTEM-CHANGES.md` as reconstructed history, preserving
  dates and uncertainty. It does not invent install times or claim old fixes work.
- Refreshes installed user plugins each time you open My Omarchy, including manual
  `omarchy plugin add` and copied plugin directories. `myomarchy dashboard` also
  reconciles inventory; **Refresh history** imports journal and package activity too.
  Records disappearance, updates and return. Discovered plugins show
  “Install date unknown.” Removed plugins remain in history.
- Links installed GitHub plugins to their repositories. Check one or all plugins
  for remote changes, update one or all, or ask the default agent whether an update
  is worthwhile. Advice is read-only. Checks are explicit and show their check time;
  a different remote revision still needs fast-forward/compatibility review.
- Updates use the official `omarchy plugin update` command after root/home snapshots.
  Dirty, unsupported, symlinked or nonstandard checkouts are skipped with outcomes
  in Activity. A detached helper survives shell reload; My Omarchy updates last.
- Imports routine ALPM package events from the last 4 MiB of `/var/log/pacman.log`.
- Records intent, incremental notes, recovery points, exit status and reviewed
  outcomes in a private SQLite database. Interrupted operations stay unfinished.
- Uses **Snapper/Btrfs**, not a new snapshot format. Managed commands stop if
  root/home configurations or declared-path coverage are missing, or creation fails.
- Opens the selected default agent through `omarchy agent prompt`, with a record
  ID and retrieval instructions, not a full transcript or journal dump.

## Install

Requires Omarchy Quattro with Quickshell, Python 3.11+, Snapper, Btrfs, and sudo or
Polkit for snapshot administration. No Python packages or cloud account required.
Agent actions require an installed default coding agent. The agent launcher uses
the user's existing Omarchy approval configuration; this app adds no sandbox.

```sh
omarchy plugin add https://github.com/cylon58/myomarchy.git --enable
python3 ~/.config/omarchy/plugins/io.github.cylon58.myomarchy/install.py
myomarchy refresh
omarchy-shell shell summon io.github.cylon58.myomarchy
```

The install helper adds an owned `~/.local/bin/myomarchy` link, an application-menu
entry, and the change-recording skill for the selected supported agent. It refuses
to replace unrelated files. Codex, OpenCode and Gemini use `~/.agents/skills`;
Claude uses `~/.claude/skills`. Start a new agent conversation after installation.
Other agents can still be launched through Omarchy; automatic skill setup for
them is not claimed. Select a supported agent before installing the skill.

## Plugin updates

Open **Plugins**, select a plugin, and use **GitHub repository**, **Check for updates**,
**Update plugin**, or **Ask agent about updating**. Use **Check all for updates** and
**Update all** for the installed inventory. No periodic network checks run.

Checks compare the checkout with the repository's default HEAD, matching Omarchy's
updater. “Remote changes available” can also mean a locally ahead or diverged branch;
updates require a fast-forward. Local edits (including untracked files) block updates.
GitHub origins must use HTTPS for automatic updating. Copied plugins and local-only
repositories still appear in inventory but need manual review. Snapshot coverage and
clean-checkout guards reduce recovery risk; external edits during an update remain a
concurrency limitation. Recovery points do not cover plugin effects on remote services.

The helper records progress and per-plugin outcomes in **Activity**. Reopen My Omarchy
if it reloads during its own update. An update command succeeding verifies the Git
update and manifest validation, not every plugin feature; review runtime behavior.

```sh
myomarchy check-updates             # all installed GitHub plugins
myomarchy check-updates RECORD_ID   # selected history record
myomarchy update-plugins --id RECORD_ID
myomarchy update-plugins --all
```

## Recovery setup and managed changes

Inspect first, then configure in the app or a terminal:

```sh
myomarchy recovery status
myomarchy recovery setup
# Explicitly change root/home retention:
myomarchy recovery setup --keep 5
# Optional per-configuration space target, with Btrfs quota setup:
myomarchy recovery setup --keep 20 --space-fraction 0.10
myomarchy run --title 'Install an application' --path /home/YOUR_USER/project -- npm install PACKAGE
```

Setup preserves existing root/home policies by default and creates missing
configurations with five retained snapshots, number cleanup, and no timeline.
Explicit `--keep` changes retention, including existing Omarchy update snapshots
marked for number cleanup. Count limits apply **per configuration**, not per paired point.
Space limits are native Snapper cleanup targets, require quota accounting, and are
not hard disk caps. Existing settings are retained when no space target is supplied.
Snapshots are created read-only and cleaned through Snapper; root/home creation is
sequential, not a single atomic machine image. Partial receipts are retained.

Managed operations require at least 2 GiB free after a cleanup attempt. Declare all
affected paths. Paths on nested subvolumes or separate filesystems are rejected.
The wrapper cannot constrain arbitrary programs to declared paths: it is tracking,
not a filesystem sandbox. Firmware, external services and other mounts are outside
coverage. Agents must stop on incomplete coverage; any unprotected action needs
explicit separate authorization and should be recorded as such.

Snapshots can expire. Inspect `myomarchy recovery list` before relying on a recorded
number. A snapshot is not an off-device backup. Full home restoration would rewind
personal files. The pilot deliberately delegates restoration planning to the agent:
inspect differences and obtain approval for the concrete restore scope. The app has
no one-click root/home rollback and does not invoke rollback through Uninstall.

## Agent workflow

`myomarchy begin TITLE --path PATH` creates a record and recovery points before
multi-step edits. `note ID TEXT` persists each attempt. `finish ID --status completed
--summary EVIDENCE` records the reviewed result. `run` executes an argument array
with inherited terminal I/O, retains only the executable name (not arguments or
output), and leaves successful commands at **needs-review** until tested.

Discuss/Investigate authorize inspection only. Uninstall authorizes ordinary removal
of the selected item, subject to recovery coverage. The agent must seek approval for
effects on personal data, shared dependencies or later edits. These are agent
instructions, not an enforcement boundary. Skill compliance is not guaranteed.

Records live under `$XDG_STATE_HOME/myomarchy` (default `~/.local/state/myomarchy`).
Nothing is uploaded by the app. Your selected agent may send retrieved record
content to its provider. Redaction is best effort, so keep secrets out of summaries.
Journal text, plugin manifests and previous commands are untrusted evidence.

## Pilot limits

The original-install baseline is unknown on existing machines. Imported history is
not proof of present state. Compare configuration checks paths supplied by installed
Omarchy templates and hashes them against the first observation on this machine.
It does not compare every package or reconstruct the original installation.
Exhaustive tracking of changes made outside the agent/wrapper is not implemented. Refresh is
manual; there is no background watcher, telemetry, or focus-stealing popup.
History is local and itself subject to a full home rollback; export it separately
before such recovery. Multiple commands are serialized; multi-step agent sessions
must coordinate their affected files. Changes to data on different filesystems and
application-consistent database backups require separate recovery planning.

## Remove

```sh
python3 ~/.config/omarchy/plugins/io.github.cylon58.myomarchy/install.py --remove
omarchy plugin remove io.github.cylon58.myomarchy
```

Removal preserves history and Snapper configurations/snapshots. Review those
separately; do not delete a Snapper configuration merely to uninstall this app.

## Development

```sh
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

Tests use temporary state and fake snapshot adapters; they do not restore a live
filesystem. Real pilot validation and limitations are documented in `VERIFICATION.md`.
Contributions should include a focused test and avoid private machine data.

MIT licensed. Uses the existing Omarchy shell components and Snapper CLI.
