import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../backup/backup_engine.dart';
import '../core/models.dart';
import '../drive/google_auth.dart';
import '../drive/google_drive.dart';
import '../services/catalog.dart';
import '../services/destination.dart';
import '../services/settings.dart';

class AppController extends ChangeNotifier {
  final AppSettings settings;
  final GoogleAuth auth;
  late final GoogleDrive drive;
  Destination? destination;
  Catalog? catalog;
  bool loading = true, busy = false, connected = false;
  int screen = 0;
  String message = '', destinationStatus = 'No destination selected';
  int? freeBytes;
  List<BackupSource> available = [];
  List<Map<String, dynamic>> runs = [],
      files = [],
      versions = [],
      sourceHistory = [];
  BackupProgress progress = BackupProgress();
  Cancellation? cancellation;
  AppController({AppSettings? settings, GoogleAuth? auth})
    : settings = settings ?? AppSettings.local(),
      auth = auth ?? GoogleAuth() {
    drive = GoogleDrive(this.auth);
  }
  void changed() => notifyListeners();
  Future<void> initialize() async {
    try {
      await settings.load();
      auth.clientId = settings.clientId;
      if (settings.destination.isNotEmpty) {
        try {
          await attach(
            settings.destination,
            expectedId: settings.destinationId,
            expectedVolume: settings.volume,
          );
        } catch (e) {
          destinationStatus = e.toString();
        }
      }
      if (await auth.hasCredentials) {
        try {
          await refreshGoogle();
        } catch (_) {
          message =
              'Saved Google authorization is unavailable. Offline restore is available; reconnect for backups.';
        }
      }
    } catch (e) {
      message = 'Setup could not be loaded: $e';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refreshGoogle() async {
    available = await drive.discover();
    connected = true;
    settings.account = drive.account;
    settings.email = drive.email;
    await settings.save();
    notifyListeners();
  }

  Future<void> connect() async {
    connected = false;
    notifyListeners();
    await auth.connect();
    await refreshGoogle();
    message = 'Connected to ${settings.email}';
    notifyListeners();
  }

  Future<void> disconnect() async {
    await auth.disconnect();
    connected = false;
    available = [];
    notifyListeners();
  }

  Future<void> importOAuth(String path) async {
    final j = jsonDecode(await File(path).readAsString());
    final installed = j['installed'];
    if (installed is! Map || installed['client_id'] is! String) {
      throw StateError(
        'Choose a Google OAuth Desktop app client JSON (with an installed section).',
      );
    }
    await auth.configure(
      installed['client_id'],
      installed['client_secret'] ?? '',
    );
    settings.clientId = auth.clientId;
    connected = false;
    available = [];
    await settings.save();
    notifyListeners();
  }

  Future<void> saveOAuth(String id, String secret) async {
    await auth.configure(id, secret);
    settings.clientId = auth.clientId;
    connected = false;
    available = [];
    await settings.save();
    notifyListeners();
  }

  Future<void> chooseDestination(String folder) async {
    var root = folder;
    if (!await File(Destination.markerPath(root)).exists()) {
      root = p.join(folder, 'BARQAAB_Backup');
      await Directory(root).create();
    }
    await attach(root, initialize: true);
    settings.destination = destination!.root;
    settings.destinationId = destination!.id;
    settings.volume = destination!.volume;
    await settings.save();
    notifyListeners();
  }

  Future<void> attach(
    String root, {
    String? expectedId,
    String? expectedVolume,
    bool initialize = false,
  }) async {
    final next = await Destination.open(
      root,
      expectedId: expectedId,
      expectedVolume: expectedVolume,
      initialize: initialize,
    );
    await next.acquire();
    Catalog? nextCatalog;
    try {
      nextCatalog = await Catalog.open(next);
    } finally {
      await next.release();
    }
    await catalog?.close();
    catalog = nextCatalog;
    destination = next;
    await refreshCatalog();
  }

  Future<void> refreshCatalog() async {
    if (catalog == null) return;
    final disk = await destination!.verify();
    freeBytes = disk.freeBytes;
    destinationStatus = 'Ready • backup identity ${destination!.id}';
    runs = await catalog!.all('runs');
    runs.sort((a, b) => (b['started'] as String).compareTo(a['started']));
    files = await catalog!.all('files');
    versions = await catalog!.all('versions');
    sourceHistory = await catalog!.all('sources');
    final memberships = await catalog!.db.query('membership');
    for (final file in files) {
      file['sourceStates'] = memberships
          .where((m) => m['file'] == file['key'])
          .map((m) => m['state'])
          .toSet()
          .join('; ');
    }
    notifyListeners();
  }

  Future<void> toggleSource(BackupSource source, bool selected) async {
    settings.sources.removeWhere((s) => s.key == source.key);
    if (selected) settings.sources.add(source);
    await settings.save();
    notifyListeners();
  }

  Future<void> start({List<BackupSource>? retrySources}) async {
    if (busy) return;
    if (!connected) throw StateError('Connect Google in Settings first.');
    if (destination == null || catalog == null) {
      throw StateError('Choose the external destination in Settings.');
    }
    final selected = (retrySources ?? settings.sources)
        .where((s) => s.account == settings.account)
        .toList();
    if (selected.isEmpty) {
      throw StateError('Select sources for the connected Google account.');
    }
    busy = true;
    screen = 2;
    cancellation = Cancellation();
    progress = BackupProgress();
    notifyListeners();
    try {
      final engine = BackupEngine(
        drive: drive,
        destination: destination!,
        catalog: catalog!,
        cancellation: cancellation,
        retention: settings.retention,
        concurrency: settings.concurrency,
        exportPdf: settings.exportPdf,
        onProgress: (value) {
          progress = value;
          notifyListeners();
        },
      );
      final result = await engine.run(selected);
      message =
          'Backup ${result['status']}: ${result['completed']} completed, ${result['skipped']} unchanged, ${result['failed']} errors.';
      if (result['persistenceError'] != null) {
        message += ' ${result['persistenceError']}';
      }
      await refreshCatalog();
    } finally {
      busy = false;
      cancellation = null;
      notifyListeners();
    }
  }

  void cancel() {
    cancellation?.cancelled = true;
    message =
        'Cancellation requested. Waiting for active operations to stop safely.';
    notifyListeners();
  }

  Future<void> retry(Map<String, dynamic> run) async {
    final failed = (run['sources'] as List)
        .where((s) => s['status'] != 'completed')
        .map((s) => BackupSource.fromJson(Map<String, dynamic>.from(s)))
        .toList();
    // A full rescan safely retries failures, while verified unchanged files are skipped.
    await start(retrySources: failed);
  }
}
