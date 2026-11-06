import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:barqaab_google_drive_backup/backup/backup_engine.dart';
import 'package:barqaab_google_drive_backup/backup/restore_service.dart';
import 'package:barqaab_google_drive_backup/core/models.dart';
import 'package:barqaab_google_drive_backup/core/local_paths.dart';
import 'package:barqaab_google_drive_backup/drive/drive_adapter.dart';
import 'package:barqaab_google_drive_backup/services/catalog.dart';
import 'package:barqaab_google_drive_backup/services/destination.dart';
import 'package:barqaab_google_drive_backup/services/windows_disk.dart';

const source = BackupSource(
  account: 'account-1',
  driveId: 'my-drive',
  rootId: 'root',
  name: 'My Drive',
);

class FakeDrive implements DriveAdapter {
  final Map<String, CloudFile> nodes = {
    'root': const CloudFile(
      id: 'root',
      name: 'My Drive',
      mime: 'application/vnd.google-apps.folder',
    ),
  };
  final Map<String, List<int>> content = {};
  final Map<String, int> attempts = {};
  String? scanFailure;
  bool interruptNetworkOnce = false;
  void Function()? onChunk;
  Object? streamError;
  void blob(
    String id,
    String name,
    String data, {
    String parent = 'root',
    String revision = '1',
    bool allowed = true,
    String mime = 'application/octet-stream',
  }) {
    content[id] = utf8.encode(data);
    nodes[id] = CloudFile(
      id: id,
      name: name,
      parents: [parent],
      revision: revision,
      size: content[id]!.length,
      md5Checksum: md5.convert(content[id]!).toString(),
      canDownload: allowed,
      mime: mime,
    );
  }

  void folder(String id, String name, {String parent = 'root'}) {
    nodes[id] = CloudFile(
      id: id,
      name: name,
      mime: 'application/vnd.google-apps.folder',
      parents: [parent],
    );
  }

  @override
  Future<List<BackupSource>> discover() async => [source];
  @override
  Future<CloudFile> stat(String id, Cancellation cancellation) async {
    cancellation.check();
    if (!nodes.containsKey(id)) throw const DriveFailure('Not accessible');
    return nodes[id]!;
  }

  @override
  Future<List<CloudFile>> children(
    BackupSource source,
    String parentId,
    Cancellation cancellation,
  ) async {
    cancellation.check();
    if (parentId == scanFailure) {
      throw const DriveFailure('Permission denied during enumeration');
    }
    return nodes.values.where((f) => f.parents.contains(parentId)).toList();
  }

  @override
  Future<Stream<List<int>>> download(
    CloudFile file,
    String? exportMime,
    Cancellation cancellation,
  ) async {
    attempts[file.id] = (attempts[file.id] ?? 0) + 1;
    final attempt = attempts[file.id]!;
    Stream<List<int>> chunks() async* {
      onChunk?.call();
      if (streamError != null) throw streamError!;
      final data = content[file.id] ?? utf8.encode('exported document');
      if (interruptNetworkOnce && attempt == 1) {
        yield data.take(1).toList();
        throw const SocketException('temporary disconnect');
      }
      yield data;
    }

    return chunks();
  }
}

void main() {
  late Directory root;
  late Destination destination;
  late Catalog catalog;
  late FakeDrive drive;
  var free = 1 << 40;
  Future<Map<String, dynamic>> run({
    Cancellation? cancel,
    int retention = 5,
    List<BackupSource> sources = const [source],
  }) => BackupEngine(
    drive: drive,
    destination: destination,
    catalog: catalog,
    concurrency: 2,
    retention: retention,
    cancellation: cancel,
  ).run(sources);
  Future<Map<String, dynamic>> record(String id) async =>
      (await catalog.get('files', fileKey(source, drive.nodes[id]!)))!;
  Future<String> current(String id) async =>
      File(destination.path((await record(id))['path'])).readAsString();
  setUp(() async {
    root = await Directory.systemTemp.createTemp('bq-');
    free = 1 << 40;
    destination = await Destination.open(
      root.path,
      initialize: true,
      diskInspector: (_) => DiskInfo('fake-volume', free),
    );
    await destination.acquire();
    try {
      catalog = await Catalog.open(destination);
    } finally {
      await destination.release();
    }
    drive = FakeDrive();
  });
  tearDown(() async {
    await catalog.close();
    await destination.release();
    expect(p.dirname(root.path), p.normalize(Directory.systemTemp.path));
    expect(p.basename(root.path).startsWith('bq-'), isTrue);
    await root.delete(recursive: true);
  });
  test('first backup and checksum-verified unchanged second run', () async {
    drive.blob('a', 'report.txt', 'first');
    expect((await run())['status'], 'completed');
    expect(await current('a'), 'first');
    final second = await run();
    expect(second['skipped'], 1);
    expect(second['completed'], 0);
    expect(drive.attempts['a'], 1);
    expect((await record('a'))['verification'], 'source MD5 and local SHA-256');
    expect((await record('a'))['path'], endsWith('.txt'));
    expect(
      await File(destination.path('_metadata/recovery.json')).exists(),
      isTrue,
    );
  });
  test(
    'changed content archives old copy and offline restore verifies checksums and overwrite',
    () async {
      drive.blob('a', 'report.txt', 'first');
      await run();
      drive.blob('a', 'report.txt', 'second', revision: '2');
      expect((await run())['status'], 'completed');
      expect(await current('a'), 'second');
      final versions = await catalog.all('versions');
      expect(versions.length, 1);
      final outputDir = await Directory(
        p.join(root.path, 'restore-test'),
      ).create();
      // Restore into a separate directory outside managed backup.
      final restoreDir = await Directory.systemTemp.createTemp('bq-restore-');
      try {
        final service = RestoreService(destination);
        await expectLater(
          service.restore(versions.single, outputDir.path),
          throwsStateError,
        );
        final output = await service.restore(versions.single, restoreDir.path);
        expect(await File(output).readAsString(), 'first');
        await expectLater(
          service.restore(versions.single, restoreDir.path),
          throwsStateError,
        );
        expect(
          await service.restore(
            versions.single,
            restoreDir.path,
            overwrite: true,
          ),
          output,
        );
      } finally {
        expect(
          p.dirname(restoreDir.path),
          p.normalize(Directory.systemTemp.path),
        );
        await restoreDir.delete(recursive: true);
      }
    },
  );
  test(
    'duplicate names, Windows collisions and deep hierarchy remain distinct',
    () async {
      for (var i = 0; i < 6; i++) {
        drive.blob(
          '$i',
          ['Report.txt', 'report.txt', 'CON', 'x:y?', 'x/y*', 'Report.txt'][i],
          '$i',
        );
      }
      var parent = 'root';
      for (var i = 0; i < 12; i++) {
        drive.folder(
          'folder$i',
          'Very long folder name number $i',
          parent: parent,
        );
        parent = 'folder$i';
      }
      drive.blob('deep', 'deep.txt', 'deep', parent: parent);
      expect((await run())['status'], 'completed');
      final files = await catalog.all('files');
      expect(
        files.map((f) => (f['path'] as String).toLowerCase()).toSet().length,
        7,
      );
      expect((await record('deep'))['path'], contains('_long_paths'));
      expect((await record('deep'))['ancestors'].length, 12);
      for (var i = 0; i < 6; i++) {
        expect(await current('$i'), '$i');
      }
      expect(safeSegment('NUL.', 'id'), startsWith('_NUL'));
      expect(() => destination.path('../outside'), throwsStateError);
    },
  );
  test(
    'rename and folder move relocate same ID without another download or version',
    () async {
      drive.folder('one', 'First');
      drive.folder('two', 'Second');
      drive.blob('a', 'before.txt', 'same', parent: 'one');
      await run();
      final before = (await record('a'))['path'];
      drive.blob('a', 'after.txt', 'same', parent: 'two');
      final result = await run();
      expect(result['status'], 'completed');
      expect(result['skipped'], 1);
      expect(drive.attempts['a'], 1);
      expect(await current('a'), 'same');
      expect(await File(destination.path(before)).exists(), isFalse);
      expect(await catalog.all('versions'), isEmpty);
    },
  );
  test(
    'source deletion retains current and records absence only after successful scan',
    () async {
      drive.blob('a', 'retained.txt', 'keep');
      await run();
      final saved = await record('a');
      drive.nodes.remove('a');
      expect((await run())['status'], 'completed');
      expect(
        await File(destination.path(saved['path'])).readAsString(),
        'keep',
      );
      expect(
        (await catalog.memberships(saved['key'])).single['state'],
        startsWith('absent:'),
      );
    },
  );
  test(
    'interrupted scan never infers deletion from partial enumeration',
    () async {
      drive.folder('folder', 'Folder');
      drive.blob('a', 'retained.txt', 'keep');
      await run();
      final saved = await record('a');
      drive.nodes.remove('a');
      drive.scanFailure = 'folder';
      final result = await run();
      expect(result['status'], 'failed');
      expect(result['sources'][0]['scanComplete'], false);
      expect(
        (await catalog.memberships(saved['key'])).single['state'],
        'present',
      );
      expect(
        await File(destination.path(saved['path'])).readAsString(),
        'keep',
      );
    },
  );
  test(
    'network interruption restarts temporary download and validates content',
    () async {
      drive.blob('a', 'network.txt', 'whole content');
      drive.interruptNetworkOnce = true;
      expect((await run())['status'], 'completed');
      expect(drive.attempts['a'], 2);
      expect(await current('a'), 'whole content');
    },
  );
  test(
    'permission denial and unsupported exports are explicit file errors',
    () async {
      drive.blob('denied', 'restricted', 'private', allowed: false);
      drive.blob(
        'form',
        'survey',
        '',
        mime: 'application/vnd.google-apps.form',
      );
      final result = await run();
      expect(result['status'], 'failed');
      expect(result['failed'], 2);
      expect(drive.attempts, isEmpty);
      expect(
        result['errors'].toString(),
        contains('Unsupported Google-native'),
      );
      expect(result['errors'].toString(), contains('permission denied'));
    },
  );
  test(
    'native exports record local checksum without source-match claim',
    () async {
      drive.blob(
        'doc',
        'Notes',
        'docx data',
        mime: 'application/vnd.google-apps.document',
      );
      expect((await run())['status'], 'completed');
      final saved = await record('doc');
      expect(saved['path'], endsWith('.docx'));
      expect(saved['verification'], contains('no source-checksum match'));
    },
  );
  test(
    'disk-full and insufficient-space failures preserve prior copy',
    () async {
      drive.blob('a', 'data', 'old');
      await run();
      drive.blob('a', 'data', 'new', revision: '2');
      drive.streamError = const FileSystemException('Disk full');
      expect((await run())['status'], 'failed');
      expect(await current('a'), 'old');
      drive.streamError = null;
      free = 16 * 1024 * 1024 + 1;
      expect((await run())['status'], 'failed');
      expect(await current('a'), 'old');
    },
  );
  test(
    'destination disconnect during stream retains current and reports failure',
    () async {
      drive.blob('a', 'data', 'old');
      await run();
      drive.blob('a', 'data', 'new', revision: '2');
      final marker = File(Destination.markerPath(root.path));
      drive.onChunk = () => marker.renameSync('${marker.path}.offline');
      final result = await run();
      expect(result['status'], 'failed');
      expect(await current('a'), 'old');
      await File('${marker.path}.offline').rename(marker.path);
      drive.onChunk = null;
      expect((await run())['status'], 'completed');
      expect(await current('a'), 'new');
    },
  );
  test(
    'cancelled work preserves versions and next run restarts unfinished file',
    () async {
      drive.blob('a', 'data', 'old');
      await run();
      drive.blob('a', 'data', 'middle', revision: '2');
      await run();
      drive.blob('a', 'data', 'new', revision: '3');
      final cancellation = Cancellation();
      drive.onChunk = () => cancellation.cancelled = true;
      expect(
        (await run(cancel: cancellation, retention: 1))['status'],
        'cancelled',
      );
      expect(await current('a'), 'middle');
      expect((await catalog.all('versions')).length, 1);
      drive.onChunk = null;
      expect((await run())['status'], 'completed');
      expect(await current('a'), 'new');
    },
  );
  test('local modifications are archived before cloud repair', () async {
    drive.blob('a', 'data', 'cloud');
    await run();
    final old = await record('a');
    await File(destination.path(old['path'])).writeAsString('local edit');
    expect((await run())['status'], 'completed');
    expect(await current('a'), 'cloud');
    final v = (await catalog.all('versions')).single;
    expect(v['locallyModified'], true);
    expect(
      await File(destination.path(v['path'])).readAsString(),
      'local edit',
    );
  });
  test('retention prunes history only after fully successful job', () async {
    for (var i = 0; i < 4; i++) {
      drive.blob('a', 'data', 'value $i', revision: '$i');
      expect((await run(retention: 2))['status'], 'completed');
    }
    expect((await catalog.all('versions')).length, 2);
    expect(await current('a'), 'value 3');
    drive.blob('a', 'data', 'value 4', revision: '4');
    drive.blob('bad', 'bad', '', allowed: false);
    expect((await run(retention: 1))['status'], 'completed with errors');
    expect((await catalog.all('versions')).length, 3);
  });
  test(
    'shortcuts preserve targets as metadata without traversal or download',
    () async {
      drive.nodes['s'] = const CloudFile(
        id: 's',
        name: 'shortcut',
        mime: 'application/vnd.google-apps.shortcut',
        parents: ['root'],
        targetId: 'root',
        targetMime: 'application/vnd.google-apps.folder',
      );
      expect((await run())['status'], 'completed');
      expect(drive.attempts, isEmpty);
      expect(await current('s'), contains('root'));
    },
  );
  test('overlapping scopes deduplicate content by drive and file ID', () async {
    drive.folder('folder', 'Folder');
    drive.blob('a', 'data', 'same', parent: 'folder');
    const nested = BackupSource(
      account: 'account-1',
      driveId: 'my-drive',
      rootId: 'folder',
      name: 'My Drive / Folder',
    );
    expect((await run(sources: [source, nested]))['status'], 'completed');
    expect(drive.attempts['a'], 1);
    expect((await catalog.all('files')).length, 1);
  });
  test(
    'incorrect identity, volume, missing root and concurrent lock are rejected',
    () async {
      await expectLater(
        Destination.open(root.path, expectedId: 'wrong'),
        throwsStateError,
      );
      await expectLater(
        Destination.open(
          root.path,
          diskInspector: (_) => const DiskInfo('wrong-volume', 1 << 40),
        ),
        throwsStateError,
      );
      await expectLater(
        Destination.open(p.join(root.path, 'missing')),
        throwsStateError,
      );
      await destination.acquire();
      final other = Destination(
        root.path,
        destination.id,
        'fake-volume',
        diskInspector: (_) => DiskInfo('fake-volume', free),
      );
      await expectLater(other.acquire(), throwsStateError);
      await destination.release();
    },
  );
  test('unmanaged path collision is never overwritten', () async {
    drive.blob('a', 'data', 'cloud');
    final path = relativeFilePath(source, [], drive.nodes['a']!, '');
    final existing = File(destination.path(path));
    await existing.parent.create(recursive: true);
    await existing.writeAsString('unmanaged');
    expect((await run())['status'], 'failed');
    expect(await existing.readAsString(), 'unmanaged');
  });
  test('checksum mismatch cannot finalize content', () async {
    drive.blob('a', 'data', 'expected');
    drive.content['a'] = utf8.encode('corrupted');
    expect((await run())['status'], 'failed');
    expect(
      await catalog.get('files', fileKey(source, drive.nodes['a']!)),
      isNull,
    );
  });
  test('validated commit journal replays interrupted finalization', () async {
    drive.blob('a', 'data', 'old');
    await run();
    final saved = await record('a');
    final temp = File(destination.path('_metadata/tmp/recovered.part'));
    await temp.writeAsString('recovered');
    final updated = {...saved, 'sha256': await checksum(temp.path), 'bytes': 9};
    await catalog.put('pending', saved['key'], {
      'key': saved['key'],
      'record': updated,
      'temp': '_metadata/tmp/recovered.part',
      'oldPath': saved['path'],
      'oldChecksum': saved['sha256'],
    });
    await destination.acquire();
    try {
      await BackupEngine(
        drive: drive,
        destination: destination,
        catalog: catalog,
      ).recover();
    } finally {
      await destination.release();
    }
    expect(await current('a'), 'recovered');
    expect(await catalog.all('pending'), isEmpty);
  });
  test(
    'SQLite failure after atomic rename is recovered with previous version intact',
    () async {
      drive.blob('a', 'data.txt', 'old');
      await run();
      await catalog.db.execute(
        "CREATE TRIGGER simulate_failure BEFORE INSERT ON files BEGIN SELECT RAISE(ABORT, 'simulated storage interruption'); END",
      );
      drive.blob('a', 'data.txt', 'new', revision: '2');
      expect((await run())['status'], 'failed');
      expect((await catalog.all('pending')).length, 1);
      final historical = (await catalog.all('versions')).single;
      expect(
        await File(destination.path(historical['path'])).readAsString(),
        'old',
      );
      await catalog.db.execute('DROP TRIGGER simulate_failure');
      expect((await run())['status'], 'completed');
      expect(await current('a'), 'new');
      expect(await catalog.all('pending'), isEmpty);
      expect(drive.attempts['a'], 2);
    },
  );
  test(
    'recovery refuses to overwrite a target modified after an interrupted commit',
    () async {
      drive.blob('a', 'data.txt', 'old');
      await run();
      final saved = await record('a');
      final temp = File(destination.path('_metadata/tmp/recovered.part'));
      await temp.writeAsString('new');
      await catalog.put('pending', saved['key'], {
        'key': saved['key'],
        'record': {...saved, 'sha256': await checksum(temp.path), 'bytes': 3},
        'temp': '_metadata/tmp/recovered.part',
        'oldPath': saved['path'],
        'oldChecksum': saved['sha256'],
        'targetChecksum': saved['sha256'],
      });
      await File(destination.path(saved['path'])).writeAsString('manual edit');
      expect((await run())['status'], 'failed');
      expect(await current('a'), 'manual edit');
      expect((await catalog.all('pending')).length, 1);
    },
  );
}
