# Verification

## Automated checks, 2026-10-05

- 33 Python tests pass. Coverage includes manual plugin discovery through the
  dashboard, repository links, remote checks and failed checks, guarded updates,
  detached launch, stopped workers, process-group timeouts, partial batch outcomes,
  self-update ordering, removal and reinstallation without duplicate records or invented
  install dates; journal and package imports; recovery policy preservation;
  incomplete snapshots blocking commands; and record/privacy safeguards.
- Native Quickshell offscreen checks exercise filtering, details, agent dispatch,
  visible failures, and reopening while the helper is busy. The pending refresh
  completes rather than being dropped. Screenshots use synthetic records only.
- `omarchy plugin validate .` passes.
- Offscreen rendering reports unsupported window masks; the checks still pass.

## Local evidence

- A manually installed Omapaste plugin is observed as present by the installed
  helper, with its installation date left unknown.
- Root and home Snapper coverage is configured. An earlier local recovery trial
  created real snapshots for both areas, recovered a disposable file from a home
  snapshot, and verified a root snapshot was readable.
- The current change creates root/home recovery points before installation.
- No full filesystem rollback has been performed or claimed. Offscreen checks
  exercise the real UI component; they are not a live desktop interaction test.
- Personal history, journals and machine snapshot receipts stay outside this
  repository and are excluded from publication.
