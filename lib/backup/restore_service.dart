import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/models.dart';
import '../core/local_paths.dart';
import '../services/destination.dart';
import 'backup_engine.dart';

class RestoreService {
  final Destination destination;
  RestoreService(this.destination);

  /// Restore one current/historical file using an atomic local temp. No network calls.
  Future<String> restore(
    Map<String, dynamic> record,
    String folder, {
    bool overwrite = false,
  }) async {
    await destination.verify();
    final source = File(destination.path(record['path']));
    if (!await source.exists()) throw StateError('Backed-up file is missing.');
    if (await checksum(source.path) != record['sha256']) {
      throw StateError('Backup checksum mismatch. Restore stopped.');
    }
    folder = p.absolute(folder);
    if (!await Directory(folder).exists()) {
      throw StateError('Restore folder does not exist.');
    }
    folder = await Directory(folder).resolveSymbolicLinks();
    final backupRoot = await Directory(destination.root).resolveSymbolicLinks();
    if (p.equals(folder.toLowerCase(), backupRoot.toLowerCase()) ||
        p.isWithin(backupRoot.toLowerCase(), folder.toLowerCase())) {
      throw StateError('Choose a restore folder outside the managed backup.');
    }
    final target = File(p.join(folder, restoreName(record)));
    if (await target.exists() && !overwrite) {
      throw StateError(
        'Restore target exists; explicit overwrite confirmation is required.',
      );
    }
    final tmp = File(p.join(folder, '.barqaab-restore-${uid()}.part'));
    try {
      await source.copy(tmp.path);
      if (await checksum(tmp.path) != record['sha256']) {
        throw StateError('Restored copy failed verification.');
      }
      if (await target.exists() && !overwrite) {
        throw StateError(
          'Restore target appeared during copy; confirmation required.',
        );
      }
      await tmp.rename(target.path);
    } finally {
      if (await tmp.exists()) await tmp.delete();
    }
    return target.path;
  }

  String restoreName(Map<String, dynamic> record) {
    // Use original name with a deterministic ID, retaining the actual backed-up extension.
    final extension = p.extension(record['path'] as String);
    var name = (record['name'] as String?) ?? 'restored';
    if (extension.isNotEmpty &&
        name.toLowerCase().endsWith(extension.toLowerCase())) {
      name = name.substring(0, name.length - extension.length);
    }
    return safeSegment(
      name,
      record['key'] ?? record['id'],
      extension: extension,
    );
  }
}
