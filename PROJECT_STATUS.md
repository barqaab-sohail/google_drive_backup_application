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

## Google Drive connection guidance - 2026-11-09 (Asia/Karachi)
- User supplied the Settings screenshot and requested step-by-step connection and first-backup guidance.
- Read project instructions, status and README; inspected OAuth read-only scope, credentials prerequisites, and Sources button labels in current source. Screenshot confirms OAuth and destination are not configured.
- Checked current official Google documentation for Drive API enablement, Google Auth Platform branding/audience/test users, Desktop OAuth client JSON, and Testing refresh-token expiration.
- No credentials accessed, Google account connected, backup performed, source changes, tests, build, or desktop interaction in this guidance session. Previous build/acceptance work remains unverified.
- Exact next step: user creates/selects a Google Cloud project, enables Google Drive API, configures consent and test user, creates a Desktop OAuth client and imports its JSON in Settings; then connects Google and runs a small folder backup to an external destination.

## Existing web OAuth credential question - 2026-11-09 (Asia/Karachi)
- Inspected status, Git status and desktop OAuth implementation; verified current official Google desktop OAuth requirements.
- Existing web callback configuration indicates a Web application client; advise creating an additional Desktop app client in the same Google Cloud project, preserving the working web client and callback. Desktop app uses a local loopback redirect with a dynamic port.
- Web storage-folder and queue environment settings are not imported by this desktop app. User must separately sign in and select the desired folder in Sources.
- No credentials or identifiers copied to progress records; no implementation changes, account connection, backup or tests performed. Prior pending verification remains pending.
- Exact next step: user opens the existing Google Cloud project, creates a Desktop app OAuth client, downloads its JSON and imports it into BARQAAB Settings, then connects and selects a small source folder and external destination.

## Download restriction diagnosis - 2026-11-09 (Asia/Karachi)
- User reported Google Drive 403 cannotDownloadAbusiveFile on some files, suspected files over 180 MB.
- Read progress and current Git status; inspected real download adapter. Ordinary files stream via files.get alt=media with Shared-drive support; no acknowledgeAbuse parameter or 180 MB file-size cap found in lib.
- Official Google Drive documentation identifies abuse-flagged downloads as requiring explicit user risk acknowledgment and owner/Shared-drive organizer eligibility. This error does not establish a file-size limit.
- No code changes, live-account checks, tests or rebuild performed. Actual file flags and user ownership remain unverified.
- Exact next step: user checks an affected file in Drive with the same account, confirms ownership/organizer eligibility and the exact warning. Any app support should require explicit acknowledgment before retrying flagged files rather than automatically acknowledging all downloads.

## Finding failed-file names and paths - 2026-11-09 (Asia/Karachi)
- User provided run rows with five failed Drive file IDs and a source value that looks like a Shared-drive ID.
- Inspected report generation and backup records. Per-file errors persist source key and Google file ID only; successful catalog records include name and ancestor hierarchy. Failed first-time downloads may not have a file catalog record because metadata is assembled in memory and stored with finalization.
- Explained direct Drive file URL and that Google UI exposes file location; no live account credentials available to resolve names/paths here. No code change or tests.
- Exact next step: user opens each provided file ID link in Drive under same account; for systematic naming/path output, implementation should include failed file name and ancestor path in error report.

## Google Drive abuse review guidance - 2026-11-09 (Asia/Karachi)
- User clarified flagged items are important ZIP backups generated by their web application, containing source code and database data.
- Checked current Google Drive Help on requesting review of a flagged violation and Drive security scanning limits. Official guidance: owner account can open Share > Request a review; file review typically around five days; must be signed in as file owner. Drive Help notes scanning limit of 100 MB, but cannot infer this caused abuse classification.
- Advised appeal as likely false positive and to preserve independent copies. No user files/account accessed, no abuse bypass, no tests/code changes.
- Exact next step: owner opens affected file in Drive and submits Request a review; if unavailable, check notification and Workspace admin path/Google support. Preserve any existing local/source backups.

## Custom logo and Windows install package - 2026-11-09 (Asia/Karachi)
- User supplied BARQAAB MONO JPG and asked to replace the default Flutter icon and get an installable Windows package.
- Converted the supplied full image to a multi-size Windows ICO at windows/runner/resources/app_icon.ico; Runner.rc already points to this resource for app/taskbar icon.
- Added packaging/Install-BARQAAB.ps1 to copy the complete release under the current user's LocalAppData and create a Start menu shortcut, plus packaging/INSTALL.txt and README package instructions.
- `C:\flutter\bin\flutter.bat build windows --release`: succeeded in 224.3 seconds.
- Created dist/BARQAAB-Drive-Backup-1.0.0.zip (14,027,664 bytes, 21 files) containing the complete Release directory and install instructions/script. This is a portable ZIP-based installer package rather than a signed MSI/setup EXE; install script requires PowerShell.
- No tests were run, per instruction. No credentials included. Existing PROJECT_STATUS changes from earlier guidance preserved.
- Exact next step: download/extract dist/BARQAAB-Drive-Backup-1.0.0.zip on the target Windows computer and run `powershell -NoProfile -ExecutionPolicy Bypass -File .\\Install-BARQAAB.ps1` from the extracted folder. If app fails due missing runtime, install Microsoft Visual C++ 2015-2022 x64 Redistributable.
