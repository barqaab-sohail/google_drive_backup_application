import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../backup/restore_service.dart';
import '../core/models.dart';
import 'app_controller.dart';

String bytes(num? value) {
  if (value == null) return 'Unknown';
  var n = value.toDouble();
  for (final suffix in ['B', 'KB', 'MB', 'GB', 'TB']) {
    if (n < 1024 || suffix == 'TB') {
      return '${n.toStringAsFixed(suffix == 'B' ? 0 : 1)} $suffix';
    }
    n /= 1024;
  }
  return '$value B';
}

String date(dynamic value) => value == null
    ? 'Never'
    : DateTime.tryParse('$value')?.toLocal().toString().split('.').first ??
          '$value';

class BackupApp extends StatelessWidget {
  final AppController controller;
  const BackupApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'BARQAAB Drive Backup',
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff12685f)),
      scaffoldBackgroundColor: const Color(0xfff4f7f8),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xffe0e7e9)),
        ),
      ),
    ),
    home: BackupShell(controller: controller),
  );
}

class BackupShell extends StatefulWidget {
  final AppController controller;
  const BackupShell({super.key, required this.controller});
  @override
  State<BackupShell> createState() => _BackupShellState();
}

class _BackupShellState extends State<BackupShell> with WindowListener {
  AppController get c => widget.controller;
  String search = '';
  bool actionBusy = false, closeDialog = false;
  static const labels = [
    'Dashboard',
    'Sources',
    'Backup progress',
    'History',
    'Restore',
    'Settings',
  ];
  @override
  void initState() {
    super.initState();
    c.addListener(_refresh);
    if (Platform.isWindows) windowManager.addListener(this);
  }

  @override
  void dispose() {
    c.removeListener(_refresh);
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> act(Future<void> Function() action) async {
    if (actionBusy) return;
    setState(() => actionBusy = true);
    try {
      await action();
    } catch (e) {
      c.message = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => actionBusy = false);
    }
  }

  @override
  void onWindowClose() async {
    if (closeDialog) return;
    if (c.busy) {
      closeDialog = true;
      final confirmed = await confirm(
        'Cancel backup and close?',
        'The active backup must stop safely before the application closes. Completed files and previous copies will be retained.',
      );
      closeDialog = false;
      if (!confirmed) return;
      c.cancel();
      while (c.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    await c.catalog?.close();
    await windowManager.destroy();
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) {
    final locked = c.busy || actionBusy;
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 228,
            child: Material(
              color: const Color(0xff102f36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 32, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.cloud_done_outlined,
                          color: Color(0xff7cd7c4),
                          size: 34,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'BARQAAB',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        Text(
                          'DRIVE BACKUP',
                          style: TextStyle(
                            color: Color(0xffa7c9cc),
                            fontSize: 11,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...List.generate(
                    labels.length,
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      child: ListTile(
                        selected: c.screen == i,
                        selectedTileColor: const Color(0xff24545b),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        leading: Icon(
                          [
                            Icons.dashboard_outlined,
                            Icons.folder_copy_outlined,
                            Icons.sync,
                            Icons.history,
                            Icons.restore,
                            Icons.settings_outlined,
                          ][i],
                          color: c.screen == i
                              ? const Color(0xff8de4d0)
                              : const Color(0xffa7c9cc),
                        ),
                        title: Text(
                          labels[i],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        onTap: () => setState(() => c.screen = i),
                      ),
                    ),
                  ),
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Manual backups.\nYour files, on your drive.',
                      style: TextStyle(color: Color(0xffa7c9cc), height: 1.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 22,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              labels[c.screen],
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.busy
                                  ? 'Backup in progress • keep your external drive connected'
                                  : 'Google Drive → your external hard drive',
                              style: const TextStyle(color: Colors.blueGrey),
                            ),
                          ],
                        ),
                      ),
                      if (c.loading || actionBusy)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      const SizedBox(width: 18),
                      Chip(
                        avatar: Icon(
                          c.connected ? Icons.check_circle : Icons.link_off,
                          size: 16,
                        ),
                        label: Text(
                          c.connected
                              ? 'Google connected'
                              : 'Google disconnected',
                        ),
                      ),
                    ],
                  ),
                ),
                if (c.message.isNotEmpty)
                  Container(
                    color: const Color(0xffe4eeef),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18),
                        const SizedBox(width: 12),
                        Expanded(child: Text(c.message)),
                        IconButton(
                          tooltip: 'Dismiss',
                          onPressed: () => setState(() => c.message = ''),
                          icon: const Icon(Icons.close, size: 16),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: c.loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(28),
                          child: switch (c.screen) {
                            0 => dashboard(locked),
                            1 => sources(locked),
                            2 => progress(),
                            3 => history(locked),
                            4 => restore(locked),
                            _ => settings(locked),
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget panel(String title, List<Widget> children, {Widget? trailing}) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    ),
  );
  Widget info(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(title, style: const TextStyle(color: Colors.blueGrey)),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
  Widget dashboard(bool locked) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      panel('Ready when you are', [
        const Text(
          'Connect your external drive, review the selected sources, then start a manual backup.',
          style: TextStyle(height: 1.6),
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: locked ? null : () => act(() => c.start()),
            icon: const Icon(Icons.backup_outlined),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Start Backup'),
            ),
          ),
        ),
      ]),
      panel('Connection & destination', [
        info(
          'Google account',
          c.settings.email.isEmpty
              ? 'Connect your Google account in Settings'
              : '${c.settings.email} ${c.connected ? '' : '(reconnect required)'}',
        ),
        info(
          'Backup folder',
          c.settings.destination.isEmpty
              ? 'Choose an external folder in Settings'
              : c.settings.destination,
        ),
        info('Drive status', c.destinationStatus),
        info('Available space', bytes(c.freeBytes)),
        TextButton.icon(
          onPressed: locked
              ? null
              : () => act(() async {
                  if (c.settings.destination.isNotEmpty) {
                    await c.attach(
                      c.settings.destination,
                      expectedId: c.settings.destinationId,
                      expectedVolume: c.settings.volume,
                    );
                  }
                }),
          icon: const Icon(Icons.refresh),
          label: const Text('Recheck destination'),
        ),
      ]),
      panel('Selected sources', [
        if (c.settings.sources.isEmpty)
          const Text(
            'No sources selected. Open Sources after connecting Google.',
          ),
        ...c.settings.sources.map((source) {
          final previous = c.sourceHistory
              .where((s) => s['key'] == source.key)
              .firstOrNull;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_outlined),
            title: Text(source.name),
            subtitle: Text(
              'Last run: ${date(previous?['ended'])} • ${previous?['status'] ?? 'not backed up'}\nLast fully successful: ${date(previous?['lastSuccessful'])}${source.account != c.settings.account ? '\nDifferent Google account — not included in the next run' : ''}',
            ),
          );
        }),
      ]),
      panel('Latest backup', [
        if (c.runs.isEmpty)
          const Text('No backup history on this destination.')
        else ...[
          info('Result', c.runs.first['status']),
          info('Finished', date(c.runs.first['ended'])),
          info(
            'Files',
            '${c.runs.first['completed'] ?? 0} completed • ${c.runs.first['skipped'] ?? 0} unchanged • ${c.runs.first['failed'] ?? 0} errors',
          ),
        ],
      ]),
    ],
  );
  Widget sources(bool locked) => Column(
    children: [
      panel('Choose what to protect', [
        const Text(
          'Select whole drives or browse to one or more folders. Shared drives are discovered from your account; shortcut targets are not traversed.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: locked || !c.connected
                ? null
                : () => act(c.refreshGoogle),
            icon: const Icon(Icons.refresh),
            label: const Text('Discover drives'),
          ),
        ),
        ...c.available.map(
          (source) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Checkbox(
              value: c.settings.sources.any((s) => s.key == source.key),
              onChanged: locked
                  ? null
                  : (value) => act(() => c.toggleSource(source, value!)),
            ),
            title: Text(source.name),
            subtitle: const Text('Whole drive'),
            trailing: OutlinedButton(
              onPressed: locked ? null : () => browse(source),
              child: const Text('Browse folders'),
            ),
          ),
        ),
      ]),
      panel('Selected scope', [
        if (c.settings.sources.isEmpty) const Text('Nothing selected.'),
        ...c.settings.sources.map(
          (s) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.name),
            subtitle: Text('Root ID: ${s.rootId}'),
            trailing: IconButton(
              tooltip: 'Remove source',
              onPressed: locked
                  ? null
                  : () => act(() => c.toggleSource(s, false)),
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ),
        ),
      ]),
    ],
  );
  Future<void> browse(BackupSource source) async {
    final chosen = await showDialog<BackupSource>(
      context: context,
      builder: (_) => FolderBrowser(controller: c, source: source),
    );
    if (chosen != null) await act(() => c.toggleSource(chosen, true));
  }

  Widget progress() {
    final value = c.progress;
    return Column(
      children: [
        panel(c.busy ? value.stage : 'Backup ${value.stage}', [
          info('Source', value.source),
          info('Current file', value.file),
          const SizedBox(height: 12),
          LinearProgressIndicator(value: c.busy ? null : 1),
          const SizedBox(height: 12),
          const Text(
            'Sources are enumerated completely before downloads. Exports can have unknown sizes; a byte percentage is not shown.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 24,
            runSpacing: 14,
            children: [
              metric('Completed', '${value.completed}'),
              metric('Unchanged', '${value.skipped}'),
              metric('Errors', '${value.failed}'),
              metric('Transferred', bytes(value.bytes)),
              metric('Average speed', '${bytes(value.speed)}/s'),
            ],
          ),
          const SizedBox(height: 18),
          Text(value.detail),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: c.busy ? c.cancel : null,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('Cancel safely'),
            ),
          ),
        ]),
      ],
    );
  }

  Widget metric(String label, String value) => SizedBox(
    width: 135,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
        ),
        Text(label, style: const TextStyle(color: Colors.blueGrey)),
      ],
    ),
  );
  Widget history(bool locked) => Column(
    children: [
      if (c.runs.isEmpty)
        panel('Backup history', [
          const Text(
            'Run your first backup to see per-source results and file errors.',
          ),
        ]),
      ...c.runs.map(
        (run) => panel('${date(run['started'])} • ${run['status']}', [
          Text(
            '${run['completed'] ?? 0} completed • ${run['skipped'] ?? 0} unchanged • ${run['failed'] ?? 0} errors • ${bytes(run['bytes'] ?? 0)} transferred',
          ),
          ...((run['sources'] as List?) ?? []).map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s['name']),
              subtitle: Text(
                '${s['status']} • scan ${s['scanComplete'] == true ? 'complete' : 'incomplete'} • ${s['completed'] ?? 0} downloaded, ${s['skipped'] ?? 0} skipped, ${s['failed'] ?? 0} errors',
              ),
            ),
          ),
          if (((run['errors'] as List?) ?? []).isNotEmpty)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('File and source errors'),
              children: (run['errors'] as List)
                  .map<Widget>(
                    (e) => ListTile(
                      title: SelectableText('${e['file'] ?? e['source']}'),
                      subtitle: SelectableText(e['message']),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton(
                onPressed:
                    locked ||
                        !c.connected ||
                        !((run['sources'] as List? ?? []).any(
                          (s) => s['status'] != 'completed',
                        ))
                    ? null
                    : () => act(() => c.retry(run)),
                child: const Text('Retry failed files (rescan)'),
              ),
              TextButton(
                onPressed: locked
                    ? null
                    : () => act(() => exportReport(run, false)),
                child: const Text('Export JSON'),
              ),
              TextButton(
                onPressed: locked
                    ? null
                    : () => act(() => exportReport(run, true)),
                child: const Text('Export CSV'),
              ),
            ],
          ),
        ]),
      ),
    ],
  );
  Future<void> exportReport(Map<String, dynamic> run, bool csv) async {
    final location = await getSaveLocation(
      suggestedName: 'BARQAAB-${run['id']}.${csv ? 'csv' : 'json'}',
    );
    if (location == null) return;
    String cell(dynamic v) => '"${'$v'.replaceAll('"', '""')}"';
    final text = csv
        ? [
            ['run', 'status', 'source', 'file', 'message'],
            ...((run['sources'] as List? ?? []).map(
              (s) => [
                run['id'],
                s['status'],
                s['name'],
                '',
                'scanComplete=${s['scanComplete']}; completed=${s['completed']}; skipped=${s['skipped']}; failed=${s['failed']}',
              ],
            )),
            ...((run['errors'] as List? ?? []).map(
              (e) => [
                run['id'],
                run['status'],
                e['source'],
                e['file'] ?? '',
                e['message'],
              ],
            )),
          ].map((row) => row.map(cell).join(',')).join('\r\n')
        : const JsonEncoder.withIndent('  ').convert(run);
    await File(location.path).writeAsString(text, flush: true);
    c.message = 'Report saved to ${location.path}';
  }

  Widget restore(bool locked) {
    final matches = c.files.where(
      (f) => '${f['name']} ${f['path']} ${f['sourceStates']}'
          .toLowerCase()
          .contains(search.toLowerCase()),
    );
    return Column(
      children: [
        panel('Restore from your external drive', [
          const Text(
            'Works without Google or internet. Browse current files and retained local versions. Restore copies to a folder you choose; existing files require confirmation.',
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search backed-up files or source state',
            ),
            onChanged: (value) => setState(() => search = value),
          ),
        ]),
        panel('Backed-up files (${matches.length})', [
          if (c.destination == null)
            const Text('Open an existing backup folder in Settings.'),
          ...matches.take(200).map((file) {
            final retained =
                c.versions.where((v) => v['key'] == file['key']).toList()..sort(
                  (a, b) => (b['created'] as String).compareTo(a['created']),
                );
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(file['name']),
              subtitle: Text(
                '${file['status']} • ${bytes(file['bytes'])}\n${file['sourceStates'] ?? ''}',
              ),
              children: [
                if (file['path'] != null)
                  ListTile(
                    title: const Text('Current local copy'),
                    subtitle: SelectableText(
                      '${file['path']}\n${file['verification']}',
                    ),
                    trailing: TextButton(
                      onPressed: locked
                          ? null
                          : () => act(() => restoreFile(file)),
                      child: const Text('Restore'),
                    ),
                  ),
                ...retained.map(
                  (v) => ListTile(
                    title: Text('Version • ${date(v['created'])}'),
                    subtitle: Text(
                      '${bytes(v['bytes'])}${v['locallyModified'] == true ? ' • preserved local modification' : ''}',
                    ),
                    trailing: TextButton(
                      onPressed: locked
                          ? null
                          : () => act(() => restoreFile(v)),
                      child: const Text('Restore version'),
                    ),
                  ),
                ),
              ],
            );
          }),
          if (matches.length > 200)
            const Text('Showing the first 200 matches. Refine your search.'),
        ]),
      ],
    );
  }

  Future<void> restoreFile(Map<String, dynamic> file) async {
    final folder = await getDirectoryPath(confirmButtonText: 'Restore here');
    if (folder == null) return;
    final service = RestoreService(c.destination!);
    final target = File(p.join(folder, service.restoreName(file)));
    var overwrite = false;
    if (await target.exists()) {
      overwrite = await confirm('Overwrite existing local file?', target.path);
      if (!overwrite) return;
    }
    await c.destination!.acquire();
    try {
      final output = await service.restore(file, folder, overwrite: overwrite);
      c.message = 'Restored and verified: $output';
    } finally {
      await c.destination!.release();
    }
  }

  Widget settings(bool locked) => Column(
    children: [
      panel('Google authorization', [
        const Text(
          'Use your own Google Cloud OAuth client of type Desktop app. Sign-in opens your system browser. Refresh authorization is protected by Windows and stays on this computer.',
        ),
        const SizedBox(height: 12),
        info(
          'OAuth client ID',
          c.settings.clientId.isEmpty ? 'Not configured' : c.settings.clientId,
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton(
              onPressed: locked
                  ? null
                  : () => act(() async {
                      final file = await openFile(
                        acceptedTypeGroups: [
                          const XTypeGroup(
                            label: 'Google OAuth JSON',
                            extensions: ['json'],
                          ),
                        ],
                      );
                      if (file != null) await c.importOAuth(file.path);
                    }),
              child: const Text('Import Desktop OAuth JSON'),
            ),
            TextButton(
              onPressed: locked ? null : configureOAuth,
              child: const Text('Enter OAuth configuration'),
            ),
            FilledButton(
              onPressed: locked || c.settings.clientId.isEmpty
                  ? null
                  : () => act(c.connect),
              child: const Text('Connect / reconnect Google'),
            ),
            TextButton(
              onPressed: locked ? null : () => act(c.disconnect),
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ]),
      panel('External backup destination', [
        info(
          'Folder',
          c.settings.destination.isEmpty
              ? 'Not selected'
              : c.settings.destination,
        ),
        info(
          'Identity',
          c.settings.destinationId.isEmpty
              ? 'Not initialized'
              : c.settings.destinationId,
        ),
        info(
          'Windows volume',
          c.settings.volume ?? 'Unavailable — root marker will be used',
        ),
        const Text(
          'Choose an existing backup root to reopen it, or a parent folder in which an empty BARQAAB_Backup folder will be created. To follow a drive-letter change, select the same existing backup root again.',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: locked
                ? null
                : () => act(() async {
                    final folder = await getDirectoryPath(
                      confirmButtonText: 'Use backup destination',
                    );
                    if (folder != null) await c.chooseDestination(folder);
                  }),
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose destination / open existing backup'),
          ),
        ),
      ]),
      panel('Backup options', [
        Row(
          children: [
            const Expanded(
              child: Text('Retained historical versions per file'),
            ),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<int>(
                initialValue:
                    [1, 3, 5, 10, 20, 50, 100].contains(c.settings.retention)
                    ? c.settings.retention
                    : 5,
                items: [1, 3, 5, 10, 20, 50, 100]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: locked
                    ? null
                    : (v) => act(() async {
                        c.settings.retention = v!;
                        await c.settings.save();
                      }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Text('Concurrent file downloads')),
            SizedBox(
              width: 110,
              child: DropdownButtonFormField<int>(
                initialValue: c.settings.concurrency,
                items: List.generate(
                  6,
                  (i) =>
                      DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                ),
                onChanged: locked
                    ? null
                    : (v) => act(() async {
                        c.settings.concurrency = v!;
                        await c.settings.save();
                      }),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Export Google documents as PDF'),
          subtitle: const Text(
            'Default: Docs → DOCX, Sheets → XLSX, Slides → PPTX. Drawings → SVG. Unsupported types are reported.',
          ),
          value: c.settings.exportPdf,
          onChanged: locked
              ? null
              : (v) => act(() async {
                  c.settings.exportPdf = v;
                  await c.settings.save();
                }),
        ),
        const Divider(),
        const Text(
          'Version history starts with this app’s backups; it is not Google’s full revision history. Current copies remain when cloud files disappear. Retention only prunes managed historical versions after a successful job.\n\nExports do not reproduce all permissions, comments, revision history, or live collaboration. Shortcuts are saved as metadata JSON without following their targets. See README.md for Google setup and limitations.',
          style: TextStyle(height: 1.6),
        ),
      ]),
    ],
  );
  Future<void> configureOAuth() async {
    final id = TextEditingController(text: c.settings.clientId),
        secret = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Desktop OAuth configuration'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: id,
                decoration: const InputDecoration(labelText: 'Client ID'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: secret,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Client secret (blank preserves saved value)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) await act(() => c.saveOAuth(id.text, secret.text));
    // Dialog route finishes its animation before controllers are disposed.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    id.dispose();
    secret.dispose();
  }
}

class FolderBrowser extends StatefulWidget {
  final AppController controller;
  final BackupSource source;
  const FolderBrowser({
    super.key,
    required this.controller,
    required this.source,
  });
  @override
  State<FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends State<FolderBrowser> {
  final List<CloudFile> trail = [];
  final Cancellation cancellation = Cancellation();
  late Future<List<CloudFile>> folders;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    folders = widget.controller.drive
        .children(
          widget.source,
          trail.isEmpty ? widget.source.rootId : trail.last.id,
          cancellation,
        )
        .then(
          (files) => files.where((f) => f.isFolder && !f.trashed).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            ),
        );
  }

  @override
  void dispose() {
    cancellation.cancelled = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Select a folder'),
    content: SizedBox(
      width: 620,
      height: 420,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.source.name}${trail.isEmpty ? '' : ' / ${trail.map((f) => f.name).join(' / ')}'}',
          ),
          TextButton.icon(
            onPressed: trail.isEmpty
                ? null
                : () => setState(() {
                    trail.removeLast();
                    load();
                  }),
            icon: const Icon(Icons.arrow_upward),
            label: const Text('Parent folder'),
          ),
          Expanded(
            child: FutureBuilder<List<CloudFile>>(
              future: folders,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SelectableText('${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.data!.isEmpty) {
                  return const Center(
                    child: Text('No subfolders. You can select this folder.'),
                  );
                }
                return ListView(
                  children: snapshot.data!
                      .map(
                        (folder) => ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name),
                          subtitle: Text(folder.id),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => setState(() {
                            trail.add(folder);
                            load();
                          }),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final source = widget.source;
          Navigator.pop(
            context,
            BackupSource(
              account: source.account,
              driveId: source.driveId,
              rootId: trail.isEmpty ? source.rootId : trail.last.id,
              name:
                  '${source.name}${trail.isEmpty ? '' : ' / ${trail.map((f) => f.name).join(' / ')}'}',
            ),
          );
        },
        child: const Text('Select this folder'),
      ),
    ],
  );
}
