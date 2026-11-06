# BARQAAB Drive Backup

Flutter Windows desktop software for **manual, read-only** backups of My Drive and selected Shared drives/folders to your own external hard drive. No server, scheduler, Windows startup action, background service, or Google Drive writes.

## Run and build

Use Flutter stable on Windows with Visual Studio's **Desktop development with C++** workload, Windows SDK, CMake and ATL components. The development environment used here has Flutter 3.44.0 / Dart 3.12.0 and Visual Studio 2022.

```powershell
flutter pub get
flutter run -d windows
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build windows --release
```

The executable is `build/windows/x64/runner/Release/barqaab_google_drive_backup.exe`. Distribute the **whole Release directory**, preserving its structure: EXE, `flutter_windows.dll`, plugin DLLs, native SQLite assets and the `data` directory. The EXE alone is insufficient. A target PC may need the Microsoft Visual C++ 2015–2022 x64 Redistributable. See [Flutter Windows distribution documentation](https://docs.flutter.dev/platform-integration/windows/building#distributing-windows-apps).

Windows is the supported desktop target. Other generated platform folders remain from the original project; they are not validated deliverables.

## Google Cloud setup

1. Open [Google Cloud Console](https://console.cloud.google.com/), create or select your own project.
2. Under **APIs & Services → Library**, enable **Google Drive API**.
3. Open **Google Auth Platform** (or OAuth consent screen). Set the application name, support email and developer contact details. Choose **Internal** only if your Workspace organization permits it; otherwise use **External**.
4. In **Data Access / Scopes**, add only `https://www.googleapis.com/auth/drive.readonly`. This scope permits reading existing file contents across chosen sources. The narrower `drive.file` scope cannot read all existing files; metadata-only scopes cannot download contents. The app requests no write scopes. [Google's scope reference](https://developers.google.com/workspace/drive/api/guides/api-specific-auth) classifies Drive read-only as restricted.
5. For an External app in **Testing**, add your Google account under **Test users**. Such refresh tokens generally expire after seven days for this scope; reconnect when necessary. Publishing changes token behavior but does not guarantee verification or administrator approval. [Google refresh-token guidance](https://developers.google.com/identity/protocols/oauth2#expiration).
6. Under **Clients / Credentials → Create OAuth client ID**, select **Desktop app**, name it, and download the client JSON. Do not create a Web application or service-account credential. A desktop loopback listener uses a dynamically assigned port; no web-hosted callback or server is needed.
7. In BARQAAB **Settings**, choose **Import Desktop OAuth JSON**. Alternatively choose **Enter OAuth configuration** and enter that desktop client's ID and client secret. Import reads the `installed.client_id` and `installed.client_secret` fields. The source JSON can remain outside the project; do not commit or share it.
8. Click **Connect / reconnect Google** and complete login/consent yourself in your system browser. The app uses an IPv4 loopback callback, random state, and S256 PKCE. It never embeds the Google login page. [Official desktop OAuth flow](https://developers.google.com/identity/protocols/oauth2/native-app).

Workspace administrators can block restricted scopes or third-party OAuth clients. Ask your administrator to approve this client and read-only Drive scope if Google reports an organization policy restriction. Shared-drive membership and download restrictions still apply. Public distribution may require OAuth verification and, depending on how restricted data is handled, additional requirements; personal/internal exceptions and user caps vary. Review [Google's verification exceptions](https://support.google.com/cloud/answer/13464323) before distributing your OAuth client. Do not bypass an organization block.

Refresh authorization and the desktop client secret are stored with `flutter_secure_storage`: Windows Credential Manager protects the encryption key, and encrypted values stay in the local application's support directory. Access tokens remain in memory. Nonsecret preferences live under `%LOCALAPPDATA%/BARQAAB/DriveBackup/settings.json`. Credentials are never placed in the backup catalog or external drive. **Disconnect** removes the app's saved refresh authorization; you can also revoke access in your Google Account. Never paste tokens into chat.

## First backup

1. Connect the external drive and open **Settings → Choose destination**. Choose a parent folder to create an empty `BARQAAB_Backup`, or select an existing marked backup root to reopen it.
2. Open **Sources → Discover drives**. Select the whole My Drive and/or any discovered Shared drive, or use **Browse folders** to select specific folders. Application Data and HAZECO Data appear only when the signed-in account can access them; no IDs/names are hardcoded in the real adapter.
3. Review the account, source scopes, destination and free space on **Dashboard**. Click **Start Backup**.
4. Keep the external drive connected. Progress shows scan/download/verification stages, current source/file, counts, transferred bytes and average speed. Byte percentages are deliberately omitted because exports have unknown sizes.
5. Review **History** and its per-source/file errors. **Retry failed files (rescan)** safely rescans affected sources and skips verified unchanged files. Reports can be exported as JSON/CSV.

```
BARQAAB_Backup/
  .barqaab-backup.json       Persistent root identity and Windows volume GUID
  My_Drive/
  Shared_Drives/<drive-name~ID>/
  _metadata/catalog.sqlite  Authoritative SQLite catalog, memberships, commit journal
  _metadata/recovery.json   Portable mappings, source metadata and version index
  _metadata/tmp/            Incomplete/recoverable downloads
  _versions/<file-key>/     Managed historical content
  _reports/                Per-run JSON reports
```

The marker and Windows volume GUID identify a destination independently of its drive letter. If a letter changes, choose the same existing backup root again. Missing/mismatched markers or volume IDs are rejected. Volume GUIDs can differ after moving to another Windows installation; an identity mismatch requires deliberate migration/review, not silently accepting a different disk. Choose a short root path (maximum 90 characters). The app checks write access, available space and an OS-backed exclusive destination lock before starting downloads. Unknown-size exports are identified explicitly; the space estimate is a minimum, not a guarantee against disk-full errors. Leave extra space for exports and local versions.

## Incremental behavior and data protection

- Complete folder-by-folder enumeration with all pages is used on every run, including the Shared-drive parameters required by Google. No Changes API cursor is assumed. Scans are staged in memory; very large folder trees can consume substantial RAM. [Shared-drive API support](https://developers.google.com/workspace/drive/api/guides/enable-shareddrives).
- Catalog identity is account + drive ID + Google file ID, rather than filename. Overlapping scopes deduplicate content within a job. Names include deterministic ID suffixes, with ordinary extensions retained. Invalid Windows characters, reserved names and case collisions are handled. Deep paths flatten into `_long_paths`; original names, hierarchy and cloud IDs remain in the catalog/recovery metadata. Empty cloud directories are currently represented by source hierarchy when they contain backed-up files; empty directories are not materialized as standalone backups.
- Unchanged files are skipped only after checking the local SHA-256. Renames/moves copy/validate then atomically relocate the managed copy without another cloud download. Local changes detected in a managed current file are preserved as a historical copy before repair from Google.
- Blob downloads stream into temporary files; provided size and MD5 are verified, and every finalized file gets a local SHA-256. Google metadata is checked again after download to detect concurrent cloud changes. Exports receive a local checksum only; there is no invented Google source-checksum match.
- A previous current copy is archived before replacement. The commit journal supports recovery when a crash/storage failure interrupts finalization. Unexpected target changes block recovery instead of overwriting them. Files are finalized with same-volume rename after validation. Keep the full backup root together and avoid manually editing managed contents.
- Default retention is **5 historical copies plus the current copy**, configurable in Settings. Only managed historical versions are pruned, only after a fully successful job. Retention is not applied after a failed/cancelled source transfer. Local history begins with this app's backups; it is not Google's full revision history.
- Cloud deletion never removes the current local copy. After a complete successful enumeration, vanished IDs are marked **absent: deleted, moved out of scope, or inaccessible** because the API may not distinguish these cases. Explicit trashed metadata is shown as trashed. Interrupted/failed scans do not infer disappearance. A source that cannot be scanned retains its previous catalog state and reports an error.
- Temporary network/rate-limit errors use bounded exponential backoff. Cancel stops workers safely; closing during an active backup prompts to cancel and waits for work to settle. A later run verifies completed files and **restarts** partial transfers. HTTP Range resume is not assumed, especially for exports. Disk-full/disconnection errors never produce a successful job result.
- A process killed before job finalization leaves a `running` row; the next backup marks it `interrupted` and replays validated pending commits. Unjournaled `.part` downloads restart. Unknown orphan version files from an interruption are preserved rather than automatically deleted. If recovery reports an unexpectedly modified target, preserve the entire root and investigate the journal/mappings before editing anything.

## Google-native files and shortcuts

Defaults: Docs → DOCX, Sheets → XLSX, Slides → PPTX, Drawings → SVG, Apps Script → JSON when the account advertises that format. Settings can select PDF exports for Docs/Sheets/Slides/Drawings. Other types (such as Forms, Sites and Vids) report unsupported status; this version does not implement Google's long-running Vids download API. Supported exports are checked against the account's advertised export formats.

Google `files.export` has an export size limit (currently 10 MB). Restrictions/limits/unsupported types appear as errors, never empty placeholder successes. Exports do not preserve all permissions, comments, revision history, embedded features or live collaboration. [Official download/export documentation](https://developers.google.com/workspace/drive/api/guides/manage-downloads).

**Shortcuts are deliberately metadata-only** `.shortcut.json` files containing the target ID/type. Targets are not traversed or fetched: this prevents loops, duplicate downloads, and copying content outside chosen scopes. Thus target accessibility is not checked or claimed. To back up a target's contents, select its actual folder/source separately. The Restore screen labels shortcut records as metadata-only.

## Offline restore and reinstall

Open the existing external backup root in **Settings**, then **Restore**. Search files/source state, expand a file, choose its current copy or a retained version, and select a local folder outside the managed backup. Every restore verifies the stored SHA-256, copies to a local temporary file, validates the copy and finalizes it. Existing target files require explicit overwrite confirmation. Deterministic name suffixes prevent collisions; ordinary/export extensions are preserved. This version restores selected files individually, not an entire directory tree in one action, and never restores directly into Google Drive.

No Google login or internet is needed to read the local catalog and restore. After reinstall, select the marked root again; history/current files/versions remain there, while Google configuration/authorization must be set up locally again. The current content is also directly readable on disk; `recovery.json` preserves the name/ID/path/checksum mapping if SQLite tooling is unavailable. It is a recovery reference, not an automatic repair tool for a corrupted database. Do not remove `_metadata` or `_versions`.

## Verification and project continuity

Tests under `test/` use a fake Drive adapter, temporary real files/SQLite, mock HTTP responses, and an actual local OAuth callback with fake credentials. They cover initial/unchanged/changed backups, Windows naming collisions/long paths, renames/moves, deletion protection, interrupted scans, retries, permission/export failures, disk/disconnection fault injection, cancellation recovery, history retention, crash-journal recovery and offline version restore. Protocol tests cover pagination, Shared-drive parameters, export/media routing, 401/rate-limit retries and PKCE/state. A Windows disk probe and six-screen widget smoke test are included. Fakes are test-only; the production app does not show demo content.

Automated tests do **not** prove real-account access, Workspace approval, large export compatibility, or physical USB removal behavior. Follow [the real-account acceptance checklist](docs/ACCEPTANCE_CHECKLIST.md). See [PROJECT_STATUS.md](PROJECT_STATUS.md) for actual latest command/build results, known issues and the precise next step. Future sessions must read it and AGENTS.md before continuing; chat history alone is not a durable handoff.

Architecture: `lib/core` models and path mapping; `lib/drive` OAuth/read-only API adapter; `lib/services` local settings/catalog/destination; `lib/backup` engine and restore; `lib/ui` controller and screens.
