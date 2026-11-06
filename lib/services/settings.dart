import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/models.dart';

class AppSettings {
  String clientId = '',
      destination = '',
      destinationId = '',
      account = '',
      email = '';
  String? volume;
  int retention = 5, concurrency = 2;
  bool exportPdf = false;
  List<BackupSource> sources = [];
  final File file;
  AppSettings(this.file);
  Future<void> load() async {
    if (!await file.exists()) return;
    final j = jsonDecode(await file.readAsString());
    clientId = j['clientId'] ?? '';
    destination = j['destination'] ?? '';
    destinationId = j['destinationId'] ?? '';
    volume = j['volume'];
    account = j['account'] ?? '';
    email = j['email'] ?? '';
    retention = (j['retention'] as int? ?? 5).clamp(1, 100);
    concurrency = (j['concurrency'] as int? ?? 2).clamp(1, 6);
    exportPdf = j['exportPdf'] == true;
    sources = (j['sources'] as List? ?? [])
        .map((e) => BackupSource.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'clientId': clientId,
        'destination': destination,
        'destinationId': destinationId,
        'volume': volume,
        'account': account,
        'email': email,
        'retention': retention,
        'concurrency': concurrency,
        'exportPdf': exportPdf,
        'sources': sources.map((s) => s.toJson()).toList(),
      }),
      flush: true,
    );
    await tmp.rename(file.path);
  }

  static AppSettings local() {
    final base =
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return AppSettings(
      File(p.join(base, 'BARQAAB', 'DriveBackup', 'settings.json')),
    );
  }
}
