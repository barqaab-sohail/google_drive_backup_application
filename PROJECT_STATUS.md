# BARQAAB Drive Backup — project status

Updated: 2026-11-03 (Asia/Karachi).

## Requirements and decisions
- Build actual Flutter Windows manual Google My Drive / Shared-drive backup software in this existing project. No scheduler, startup task, service, cloud writes, or paid backend.
- Separate UI, read-only Drive adapter, backup engine, and persistence. Full enumeration; no Changes API cursors.
- Desktop OAuth via system browser, loopback and PKCE; read-only Drive scope; Windows-protected token storage on local machine only.
- External destination holds marker, SQLite catalog, current files, managed versions, metadata and reports. Check marker/volume, write access, space and exclusive lock.
- Track source/file IDs; protect current copies, preserve versions, stream/validate downloads, safe cancellation, offline restore, report errors explicitly.
- Six Material 3 screens: dashboard, sources, progress, history, restore, settings. Fake-adapter tests plus analysis and release build. Credentials and physical-drive acceptance remain user-dependent.
- Preserve all existing work. Folder currently has no Git repository (git status reports fatal).

## Verified baseline
- Inspected source, pubspec, README, starter test and Windows platform folder: untouched Flutter counter scaffold.
- No existing AGENTS.md or PROJECT_STATUS.md found in project or E:/ parent instructions.
- Flutter 3.44.0 stable / Dart 3.12.0 available at C:/flutter/bin.
- Consulted official Flutter Windows distribution and Google native OAuth / Drive download documentation before implementation.

## Completed
- Durable handoff instructions created in AGENTS.md.
- Core implementation verified with fake Drive + real temporary files/SQLite: models/path mapping, marker/volume/free-space/lock checks, incremental engine, versions, journal recovery, cancellation and offline restore.
- Google protocol tests pass: actual local loopback callback with fake OAuth credentials, PKCE/state, token refresh, REST pagination/Shared-drive parameters, exports/download routing and rate-limit retry.
- Six desktop screens pass widget smoke testing. Close protection implemented; active-job physical desktop acceptance remains user-dependent.
- README Google setup/build/backup/restore documentation and docs/ACCEPTANCE_CHECKLIST.md added.
- Windows release build succeeded; bundle contains EXE, Flutter/plugins/SQLite DLLs, native assets and data directory.

## In progress / pending
1. Runtime UI inspection was interrupted by the user's physical Escape key. No further computer-use actions were taken. The first capture showed an occluding browser, so the actual rendered BARQAAB UI has NOT been visually verified.
2. Final format/analyze/test and release rebuild after the latest review edits are still pending. An earlier Windows release build succeeded; do not assume its binary includes every latest source correction.

## Files changed
- AGENTS.md: continuity requirement.
- PROJECT_STATUS.md: this handoff.
- lib/core/: cloud/source models, cancellation, export selection, deterministic Windows-safe paths.
- lib/services/: destination verification/locking, SQLite, local settings, Windows disk APIs.
- lib/drive/: read-only Drive abstraction, Google OAuth and REST adapter.
- lib/backup/: streamed/incremental/versioned backup, commit recovery, offline restore.
- lib/ui/, lib/main.dart: controller and six Material 3 screens.
- pubspec.yaml, pubspec.lock: desktop-compatible dependencies resolved.
- test/: 22 fake-adapter/storage/restore scenarios, 7 Google/Windows protocol/probe checks and a six-screen widget smoke test (30 total).
- windows/runner/: branded app title/product metadata and long-path manifest support.
- .gitignore: excludes OAuth configuration and local backup data.

## Commands and results
- rg --files / Get-Content: confirmed starter only.
- git status --short: failed because folder is not a Git repository.
- flutter --version: succeeded, versions above.
- flutter pub add: succeeded.
- flutter doctor -v: Windows/Visual Studio toolchain ready; unrelated Android license warning.
- Initial analysis found starter-test compile failure and style/nullability findings; fixed implementation findings and replaced starter test.
- Initial test pass found a Material ancestor assertion in navigation and a test preflight expectation error; corrected both.
- dart format lib test: succeeded.
- flutter analyze: no issues found (latest complete run).
- flutter test --reporter expanded: 30 tests passed (latest complete run).
- flutter build windows --release: succeeded in 142.1 seconds. Final rebuild after review may still be needed.

## Known limitations / configuration
- OAuth desktop client not supplied; no real Google account or physical external drive validation yet.
- No real-account/physical-USB completion claim. Runtime UI review stopped at user request; the application was launched, but its screenshot was not successfully verified.
- README documents current scope limits: individual-file restore, shortcut metadata only, unsupported native types reported, empty directories not materialized, in-memory enumeration, and no automatic repair of a corrupted catalog.
- Shortcut policy is metadata-only (no target traversal); repeated/overlapping source files deduplicated by account/drive/file ID.
- Historical retention defaults to 5 retained historical copies plus current. Long cloud paths flatten to _long_paths with original hierarchy in metadata.
- Downloads restart safely after interruption; partial HTTP range resume is deliberately not assumed.

## Exact next step
On the next authorized session: read AGENTS.md and this file; inspect source and Git status; run formatting check, flutter analyze, flutter test, then rebuild the Windows release to synchronize the binary with current source. Resume desktop visual QA only when the user wants computer use resumed. Then provide the bundle and walk through README Google OAuth setup and docs/ACCEPTANCE_CHECKLIST.md; never request refresh tokens in chat.

## Configuration guidance session — 2026-11-05 (Asia/Karachi)
- User requested backup configuration guidance only. Read status, README, acceptance checklist, and inspected OAuth import, destination selection, source selection and backup prerequisites in the current implementation.
- Git status still fails: this directory is not a Git repository. Confirmed the release EXE exists; its freshness remains unverified.
- Checked current official Google setup documentation for Drive API, consent configuration and Desktop OAuth credentials. No credentials read or recorded, no account connected, and no backup run.
- No source changes, automated tests, rebuild, or desktop interaction performed in this guidance session. Prior pending verification remains pending.
- Exact next step: user creates/imports a Desktop OAuth client, connects Google, chooses an external destination and selects a small test folder, then runs and checks the first backup. For implementation work, first complete the previously pending format/analyze/test/release rebuild; visual QA remains opt-in.

## Conductor option request — 2026-11-05 (Asia/Karachi)
- Requested an empty option in all conductor selectors, meaning no conductor available.
- Read project status and searched current project sources: no conductor references found. This workspace contains the Google Drive backup app. Git status still reports no Git repository.
- No implementation changes or tests performed; need the intended application/project location before editing.
- Exact next step: identify the project containing conductor selectors, then inspect its instructions and implement the empty selection across those fields.
