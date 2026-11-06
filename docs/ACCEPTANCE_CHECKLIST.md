# Real-account acceptance checklist

These checks require your Google account and an external disk. Automated tests use fakes and do not establish that Workspace policy allows your account to download everything.

- [ ] Import your Desktop OAuth client JSON, sign in through the system browser, and verify the account shown in Dashboard. Close/reopen the app and confirm refresh authorization works. Revoke access at Google and confirm reconnect instructions appear.
- [ ] Discover My Drive and all accessible Shared drives. Confirm Application Data and HAZECO Data appear if this account has access; IDs are never hardcoded. Browse and select a small test folder before selecting large drives.
- [ ] Choose a physical external drive. Check the displayed folder/free space. Run a small full backup, inspect the report and open ordinary files and DOCX/XLSX/PPTX exports.
- [ ] Run again unchanged; verify skips. Change a test file, run again, restore the previous version into a separate folder, and open it.
- [ ] Rename/move test files and include duplicate names/case variants. Verify the catalog maps the same Google IDs and no unrelated file is overwritten.
- [ ] Trash/delete a cloud test file. Confirm the current local copy remains and Restore shows its source state. Use a test file only; the app itself never modifies Google Drive.
- [ ] Select a source the account cannot fully enumerate. Confirm failure does not cause an absence/deletion inference from an incomplete scan.
- [ ] Exercise a restricted download, an unsupported Google-native type, and an export above Google's supported limit. Confirm explicit errors and a non-successful job result.
- [ ] Cancel a long test download; close the app during an active test job and confirm the cancellation prompt. Reopen/rerun and verify partial work restarts and completed copies remain valid.
- [ ] Disconnect network during a test download; confirm bounded retries, or a reported failure that can be retried from History.
- [ ] With expendable test data, disconnect the external disk during a download, then reconnect and reopen the same backup. Confirm the failed job is never called successful and the next job recovers/restarts safely. Test a full disk using a disposable small volume, not the only copy of important data.
- [ ] Change the external drive letter. Select the existing backup root again; confirm its marker and volume identity are accepted. Select a different disk/missing marker and confirm rejection of an expected destination.
- [ ] Run two app instances against the same backup destination; the second job must fail to acquire the destination lock.
- [ ] Disconnect Google/network and restore both a current file and a retained version. Repeat after reinstalling the app and opening the existing backup root. Confirm overwrite requires explicit confirmation.
- [ ] After a fully successful run, confirm configured historical retention. A failed/cancelled job must not prune history.
- [ ] Copy the entire Windows release bundle to another compatible Windows PC and test startup (install the Visual C++ runtime if required).
