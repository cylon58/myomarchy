# Verification

## Automated checks, 2026-10-05

- 39 Python tests pass. Coverage includes manual plugin discovery through the
  dashboard, repository links, remote checks and failed checks, guarded updates,
  detached launch, stopped workers, process-group timeouts, partial batch outcomes,
  self-update ordering, removal and reinstallation without duplicate records or invented
  install dates; journal and package imports; recovery policy preservation;
  incomplete snapshots blocking commands; and record/privacy safeguards.
- Native Quickshell offscreen checks exercise filtering, details, agent dispatch,
  visible failures, and reopening while the helper is busy. The pending refresh
  completes rather than being dropped. Screenshots use synthetic records only.
- Responsive UI checks pass at 1120×740, 1005×544, 800×600, 600×400,
  420×360 and 360×300 logical pixels. They verify scrollable whole-detail content,
  narrow Back navigation, new-selection scroll reset, empty-result placement and
  recovery dialog bounds. QtTest wheel events over text and buttons scroll the
  whole pane; arrow/Enter/Escape input exercises narrow keyboard navigation.
- Installation-evidence tests cover clone corroboration, copied old repositories,
  re-clones after first observation, missing/malformed evidence, and preservation
  of stronger recorded or verified dates.
- `omarchy plugin validate .` passes.
- Offscreen rendering reports unsupported window masks; the checks still pass.

## Local evidence

- A manually installed Omapaste plugin is observed as present by the installed
  helper. Clone logs and filesystem creation evidence recover dates across the
  installed inventory, with source and certainty preserved.
- Root and home Snapper coverage is configured. An earlier local recovery trial
  created real snapshots for both areas, recovered a disposable file from a home
  snapshot, and verified a root snapshot was readable.
- The current change creates root/home recovery points before installation.
- No full filesystem rollback has been performed or claimed. Offscreen checks
  exercise the real UI component; they are not a live desktop interaction test.
- Personal history, journals and machine snapshot receipts stay outside this
  repository and are excluded from publication.

## Installed release verification

- The protected detached worker successfully updated My Omarchy from the prior
  public revision, recording root/home snapshots and before/after revisions.
- A stock Omarchy shell restart replaced the stale cached interface. The visible
  installed window reports 0.3.0 and fits the previously failing 1005×544 tile.
- Inventory dates are recovered for every installed plugin, with estimates,
  location creation and first observation clearly distinguished.
