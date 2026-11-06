import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/models.dart';
import '../core/local_paths.dart';
import 'windows_disk.dart';

class Destination {
  final String root, id;
  final String? volume;
  final DiskInfo Function(String) diskInspector;
  RandomAccessFile? _lock;
  static final Set<String> _held = {};
  Destination(
    this.root,
    this.id,
    this.volume, {
    this.diskInspector = inspectDisk,
  });
  static String markerPath(String root) => p.join(root, '.barqaab-backup.json');
  static Future<Destination> open(
    String root, {
    String? expectedId,
    String? expectedVolume,
    bool initialize = false,
    DiskInfo Function(String) diskInspector = inspectDisk,
  }) async {
    root = p.normalize(p.absolute(root));
    if (root.length > 90) {
      throw StateError(
        'Choose a shorter destination path (90 characters maximum).',
      );
    }
    if (!await Directory(root).exists()) {
      throw StateError('Destination is missing. Connect the external drive.');
    }
    final marker = File(markerPath(root));
    if (!await marker.exists()) {
      if (!initialize || expectedId != null) {
        throw StateError(
          'Incorrect destination: backup-root marker is missing.',
        );
      }
      if (await Directory(root).list().isEmpty == false) {
        throw StateError(
          'Initialize an empty BARQAAB_Backup folder, or open an existing backup.',
        );
      }
      final info = diskInspector(root);
      await marker.writeAsString(
        jsonEncode({
          'format': 1,
          'id': uid(),
          'volume': info.identity,
          'created': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
    }
    final j = jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
    if (j['format'] != 1 || j['id'] is! String) {
      throw StateError('Invalid backup marker.');
    }
    final info = diskInspector(root);
    if (expectedId != null && j['id'] != expectedId) {
      throw StateError(
        'Incorrect destination: backup identity does not match.',
      );
    }
    final registered = expectedVolume ?? j['volume'] as String?;
    if (registered != null && info.identity != registered) {
      throw StateError('Incorrect or unavailable Windows volume identity.');
    }
    final result = Destination(
      root,
      j['id'],
      registered,
      diskInspector: diskInspector,
    );
    await result.verify();
    return result;
  }

  String path(String relative) {
    final result = insideRoot(root, relative);
    var current = root;
    for (final part in p.split(relative)) {
      current = p.join(current, part);
      if (FileSystemEntity.isLinkSync(current)) {
        throw StateError(
          'Links/reparse points are not allowed inside the managed backup: $relative',
        );
      }
    }
    return result;
  }

  Future<DiskInfo> verify({int requiredBytes = 0}) async {
    final marker = File(markerPath(root));
    if (!await marker.exists()) {
      throw StateError('Destination disconnected or marker missing.');
    }
    final j = jsonDecode(await marker.readAsString());
    if (j['id'] != id) throw StateError('Destination identity changed.');
    final disk = diskInspector(root);
    if (volume != null && disk.identity != volume) {
      throw StateError('Destination volume disconnected or changed.');
    }
    if (disk.freeBytes != null &&
        disk.freeBytes! < requiredBytes + 16 * 1024 * 1024) {
      throw FileSystemException('Insufficient free space on destination.');
    }
    return disk;
  }

  Future<void> acquire() async {
    final key = p.normalize(root).toLowerCase();
    if (!_held.add(key)) {
      throw StateError('Another job is using this backup destination.');
    }
    try {
      await verify();
      _lock = await File(path('.backup.lock')).open(mode: FileMode.append);
      await _lock!.lock(FileLock.exclusive);
      final probe = File(path('.write-probe-${uid()}'));
      await probe.writeAsString('BARQAAB', flush: true);
      await probe.delete();
      for (final folder in [
        '_metadata',
        '_metadata/tmp',
        '_versions',
        '_reports',
      ]) {
        await Directory(path(folder)).create(recursive: true);
      }
    } catch (_) {
      await release();
      rethrow;
    }
  }

  Future<void> release() async {
    try {
      await _lock?.close();
    } finally {
      _lock = null;
      _held.remove(p.normalize(root).toLowerCase());
    }
  }
}
