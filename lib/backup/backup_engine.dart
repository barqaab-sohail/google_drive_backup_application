import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../core/models.dart';
import '../core/local_paths.dart';
import '../drive/drive_adapter.dart';
import '../services/catalog.dart';
import '../services/destination.dart';

Future<String> checksum(String path, {bool useMd5 = false}) => Isolate.run(
  () async => (await (useMd5 ? md5 : sha256).bind(File(path).openRead()).first)
      .toString(),
);

class _Entry {
  final CloudFile file;
  final List<CloudFile> ancestors;
  _Entry(this.file, this.ancestors);
}

class BackupEngine {
  final DriveAdapter drive;
  final Destination destination;
  final Catalog catalog;
  final Cancellation cancellation;
  final int retention, concurrency;
  final bool exportPdf;
  final void Function(BackupProgress)? onProgress;
  final BackupProgress progress = BackupProgress();
  final List<Map<String, dynamic>> _errors = [];
  final Set<String> _processed = {};
  String _runId = '';
  BackupEngine({
    required this.drive,
    required this.destination,
    required this.catalog,
    Cancellation? cancellation,
    this.retention = 5,
    this.concurrency = 2,
    this.exportPdf = false,
    this.onProgress,
  }) : cancellation = cancellation ?? Cancellation();
  void _emit() => onProgress?.call(progress);
  void _error(String source, String? file, Object error) {
    progress.failed++;
    _errors.add({'source': source, 'file': file, 'message': error.toString()});
    _emit();
  }

  Future<Map<String, dynamic>> run(List<BackupSource> sources) async {
    if (sources.isEmpty) throw StateError('Select at least one backup source.');
    await destination.acquire();
    _runId = uid();
    final run = <String, dynamic>{
      'id': _runId,
      'started': DateTime.now().toUtc().toIso8601String(),
      'status': 'running',
      'sources': <Map<String, dynamic>>[],
      'errors': _errors,
    };
    var acquired = true;
    try {
      progress.elapsed.start();
      await recover();
      await catalog.put('runs', _runId, run);
      for (final source in sources) {
        cancellation.check();
        progress.stage = 'Scanning';
        progress.source = source.name;
        progress.file = '';
        progress.totalKnown = false;
        _emit();
        final summary = <String, dynamic>{
          ...source.toJson(),
          'key': source.key,
          'scanComplete': false,
          'status': 'running',
          'started': DateTime.now().toUtc().toIso8601String(),
        };
        (run['sources'] as List).add(summary);
        final beforeCompleted = progress.completed,
            beforeSkipped = progress.skipped,
            beforeFailed = progress.failed;
        try {
          final entries = await _scan(source);
          cancellation.check();
          summary['scanComplete'] = true;
          // Estimate only new/changed blobs, with room for preserving current content.
          var knownBytes = 0, unknown = 0;
          for (final entry in entries.where(
            (e) => !e.file.isFolder && !e.file.trashed,
          )) {
            final file = entry.file;
            final old = await catalog.get('files', fileKey(source, file));
            final export = exportFor(file, pdf: exportPdf);
            if (old?['fingerprint'] != file.fingerprint(export?.mime) ||
                old?['path'] == null) {
              if (file.size != null && !file.isNative) {
                knownBytes += file.size!;
              } else {
                unknown++;
              }
              knownBytes += (old?['bytes'] as int? ?? 0);
            }
          }
          final disk = await destination.verify(requiredBytes: knownBytes);
          progress.detail =
              'Minimum new/changed data and version space: $knownBytes bytes. ${unknown > 0 ? '$unknown exports/files have unknown size; required space cannot be estimated accurately.' : ''} ${disk.freeBytes == null ? 'Free space unavailable.' : ''}';
          summary['spaceEstimate'] = progress.detail;
          progress.stage = 'Downloading';
          progress.totalFiles = entries
              .where((e) => !e.file.isFolder && !e.file.trashed)
              .length;
          progress.totalKnown = true;
          _emit();
          final seen = <String>{};
          final work = <_Entry>[];
          for (final entry in entries) {
            final key = fileKey(source, entry.file);
            seen.add(key);
            await catalog.member(
              source.key,
              key,
              entry.file.trashed ? 'trashed (local copy retained)' : 'present',
            );
            if (entry.file.isFolder || entry.file.trashed) continue;
            if (_processed.add(key)) work.add(entry);
          }
          var next = 0;
          Future<void> worker() async {
            while (next < work.length) {
              cancellation.check();
              final entry = work[next++];
              try {
                await _backupFile(source, entry);
              } on Cancelled {
                rethrow;
              } catch (e) {
                _error(source.key, entry.file.id, e);
              }
            }
          }

          // Workers always settle before releasing the destination lock, including cancellation.
          final outcomes = await Future.wait(
            List.generate(
              min(concurrency.clamp(1, 6), max(1, work.length)),
              (_) => worker(),
            ).map((future) async {
              try {
                await future;
                return null;
              } catch (e) {
                return e;
              }
            }),
          );
          if (outcomes.any((e) => e is Cancelled)) throw Cancelled();
          for (final error in outcomes.whereType<Object>()) {
            _error(source.key, null, error);
          }
          cancellation.check();
          await destination.verify();
          await catalog.completeScan(source.key, seen);
          summary['status'] = progress.failed == beforeFailed
              ? 'completed'
              : 'completed with errors';
        } on Cancelled {
          summary['status'] = 'cancelled';
          rethrow;
        } catch (e) {
          summary['status'] = 'failed';
          _error(source.key, null, e);
        } finally {
          summary['completed'] = progress.completed - beforeCompleted;
          summary['skipped'] = progress.skipped - beforeSkipped;
          summary['failed'] = progress.failed - beforeFailed;
          summary['ended'] = DateTime.now().toUtc().toIso8601String();
          final previous = await catalog.get('sources', source.key);
          summary['lastSuccessful'] = summary['status'] == 'completed'
              ? summary['ended']
              : previous?['lastSuccessful'];
          await catalog.put('sources', source.key, summary);
          await catalog.put('runs', _runId, run);
        }
      }
      cancellation.check();
      run['status'] = progress.failed == 0
          ? 'completed'
          : progress.completed + progress.skipped > 0
          ? 'completed with errors'
          : 'failed';
      if (run['status'] == 'completed') {
        progress.stage = 'Pruning managed history';
        _emit();
        await _prune();
      }
    } on Cancelled {
      run['status'] = 'cancelled';
    } catch (e) {
      run['status'] = 'failed';
      _error(progress.source, null, e);
    } finally {
      progress.elapsed.stop();
      run.addAll({
        'ended': DateTime.now().toUtc().toIso8601String(),
        'completed': progress.completed,
        'skipped': progress.skipped,
        'failed': progress.failed,
        'bytes': progress.bytes,
      });
      try {
        await catalog.put('runs', _runId, run);
        await File(destination.path('_reports/$_runId.json')).writeAsString(
          const JsonEncoder.withIndent('  ').convert(run),
          flush: true,
        );
        await exportRecoveryMetadata();
      } catch (e) {
        run['status'] = 'failed';
        run['persistenceError'] = 'Destination/catalog/report write failed: $e';
        try {
          await catalog.put('runs', _runId, run);
        } catch (_) {
          /* UI receives failed result even if drive disconnected. */
        }
      }
      if (acquired) {
        await destination.release();
        acquired = false;
      }
      progress.stage = '${run['status']}';
      progress.totalKnown = false;
      _emit();
    }
    return run;
  }

  Future<List<_Entry>> _scan(BackupSource source) async {
    final root = await drive.stat(source.rootId, cancellation);
    if (!root.isFolder || root.trashed) {
      throw const DriveFailure(
        'Selected source root is unavailable or trashed. No deletion inference was made.',
      );
    }
    final queue = <(String, List<CloudFile>)>[
      (
        root.id,
        source.rootId == source.driveId ||
                source.isMyDrive && root.parents.isEmpty
            ? []
            : [root],
      ),
    ];
    final visited = <String>{};
    final entries = <_Entry>[];
    var index = 0;
    while (index < queue.length) {
      cancellation.check();
      final (id, ancestors) = queue[index++];
      if (!visited.add(id)) continue;
      progress.file = ancestors.map((f) => f.name).join(' / ');
      _emit();
      final children = await drive.children(source, id, cancellation);
      for (final file in children) {
        entries.add(_Entry(file, ancestors));
        if (file.isFolder && !file.trashed) {
          queue.add((file.id, [...ancestors, file]));
        }
      }
    }
    return entries;
  }

  Future<void> _backupFile(BackupSource source, _Entry entry) async {
    cancellation.check();
    final file = entry.file, key = fileKey(source, entry.file);
    progress.file = file.name;
    _emit();
    final old = await catalog.get('files', key);
    final export = exportFor(file, pdf: exportPdf);
    final record = <String, dynamic>{
      'key': key,
      'account': source.account,
      'driveId': source.driveId,
      'fileId': file.id,
      'name': file.name,
      'ancestors': entry.ancestors.map((f) => f.toJson()).toList(),
      'cloud': file.toJson(),
      'fingerprint': file.fingerprint(export?.mime),
      'exportMime': export?.mime,
      'updated': DateTime.now().toUtc().toIso8601String(),
    };
    if (file.isNative && export == null ||
        !file.canDownload && !file.isShortcut) {
      if (old == null) {
        await catalog.put('files', key, {
          ...record,
          'status': 'unsupported or download restricted',
        });
      }
      throw DriveFailure(
        file.isNative && export == null
            ? 'Unsupported Google-native file type: ${file.mime}. No content downloaded.'
            : 'Download permission denied by source owner or policy.',
      );
    }
    final relative = relativeFilePath(
      source,
      entry.ancestors,
      file,
      file.isShortcut ? '.shortcut.json' : export?.extension ?? '',
    );
    final target = File(destination.path(relative));
    final oldFile = old?['path'] == null
        ? null
        : File(destination.path(old!['path']));
    final oldExists = oldFile != null && await oldFile.exists();
    final oldValid =
        oldExists &&
        old?['sha256'] != null &&
        await checksum(oldFile.path) == old!['sha256'];
    final unchanged = oldValid && old['fingerprint'] == record['fingerprint'];
    if (unchanged && old['path'] == relative) {
      await catalog.put('files', key, {
        ...old,
        ...record,
        'status': 'backed up',
      });
      progress.skipped++;
      _emit();
      return;
    }
    await destination.verify(
      requiredBytes:
          (unchanged ? old['bytes'] as int : file.size ?? 0) +
          (oldExists && !unchanged ? await oldFile.length() : 0),
    );
    await target.parent.create(recursive: true);
    if (await target.exists() &&
        (oldFile == null ||
            p.normalize(oldFile.path).toLowerCase() !=
                p.normalize(target.path).toLowerCase())) {
      throw StateError(
        'Unmanaged destination collision. Existing file was preserved: $relative',
      );
    }
    final temp = File(destination.path('_metadata/tmp/$key-${uid()}.part'));
    try {
      if (unchanged) {
        await oldFile.copy(temp.path);
      } else if (file.isShortcut) {
        // Deliberate policy: do not traverse shortcut targets. They may be outside selected scopes.
        await temp.writeAsString(
          jsonEncode({
            'kind': 'Google Drive shortcut',
            'shortcut': file.toJson(),
            'policy':
                'Metadata only. Select target folder separately to back up its contents; no shortcut traversal or duplicate content download.',
          }),
          flush: true,
        );
      } else {
        await _download(file, export?.mime, temp);
      }
      cancellation.check();
      progress.stage = 'Verifying';
      _emit();
      final length = await temp.length();
      if (!file.isNative &&
          !file.isShortcut &&
          file.size != null &&
          length != file.size) {
        throw const DriveFailure('Downloaded size differs from Google source.');
      }
      if (!file.isNative &&
          !file.isShortcut &&
          file.md5Checksum != null &&
          await checksum(temp.path, useMd5: true) !=
              file.md5Checksum!.toLowerCase()) {
        throw const DriveFailure('Google MD5 verification failed.');
      }
      final sha = await checksum(temp.path);
      if (!unchanged && !file.isShortcut) {
        final current = await drive.stat(file.id, cancellation);
        if (current.fingerprint(export?.mime) !=
            file.fingerprint(export?.mime)) {
          throw const DriveFailure(
            'Source changed during download. Retry on the next run.',
          );
        }
      }
      record.addAll({
        'path': relative,
        'sha256': sha,
        'bytes': length,
        'status': file.isShortcut
            ? 'shortcut metadata only (target not traversed)'
            : 'backed up',
        'verification': file.isNative
            ? 'local SHA-256 only; export has no source-checksum match'
            : file.md5Checksum == null
            ? 'local SHA-256; source checksum unavailable'
            : 'source MD5 and local SHA-256',
      });
      if (oldExists && !unchanged) {
        final versionId = uid();
        final versionPath = p.join(
          '_versions',
          key,
          '$versionId${p.extension(oldFile.path)}',
        );
        final version = File(destination.path(versionPath));
        await version.parent.create(recursive: true);
        final versionTemp = File('${version.path}.part');
        await oldFile.copy(versionTemp.path);
        final versionSha = await checksum(versionTemp.path);
        await versionTemp.rename(version.path);
        await catalog.put('versions', versionId, {
          'id': versionId,
          'key': key,
          'name': old!['name'],
          'path': versionPath,
          'sha256': versionSha,
          'bytes': await version.length(),
          'created': DateTime.now().toUtc().toIso8601String(),
          'cloud': old['cloud'],
          'locallyModified': !oldValid,
        });
      }
      cancellation.check();
      await destination.verify();
      final pending = <String, dynamic>{
        'key': key,
        'record': record,
        'temp': p.relative(temp.path, from: destination.root),
        'oldPath': old?['path'],
        'oldChecksum': oldExists ? await checksum(oldFile.path) : null,
        'targetChecksum': await target.exists()
            ? await checksum(target.path)
            : null,
      };
      await catalog.put('pending', key, pending);
      await _commit(pending);
      if (unchanged) {
        progress.skipped++;
      } else {
        progress.completed++;
      }
      progress.stage = 'Downloading';
      _emit();
    } finally {
      // Journaled files are retained for recovery if commit failed.
      if (await temp.exists() && await catalog.get('pending', key) == null) {
        await temp.delete();
      }
    }
  }

  Future<void> _download(CloudFile file, String? exportMime, File temp) async {
    for (var attempt = 0; ; attempt++) {
      cancellation.check();
      try {
        final stream = await drive.download(file, exportMime, cancellation);
        final output = await temp.open(mode: FileMode.write);
        try {
          await for (final chunk in stream) {
            cancellation.check();
            await output.writeFrom(chunk);
            progress.bytes += chunk.length;
            _emit();
          }
          await output.flush();
        } finally {
          await output.close();
        }
        return;
      } catch (e) {
        final retry =
            e is SocketException ||
            e is TimeoutException ||
            e is http.ClientException ||
            e is DriveFailure && e.retryable;
        if (!retry || attempt >= 3) rethrow;
        progress.detail =
            'Temporary network failure. Restarting ${file.name}; retry ${attempt + 1}/3.';
        _emit();
        await cancellation.delay(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
  }

  Future<void> _commit(Map<String, dynamic> pending) async {
    final record = Map<String, dynamic>.from(pending['record']);
    final target = File(destination.path(record['path']));
    final temp = File(destination.path(pending['temp']));
    if (!await target.exists() ||
        await checksum(target.path) != record['sha256']) {
      if (await target.exists() &&
          await checksum(target.path) !=
              (pending['targetChecksum'] ??
                  (pending['oldPath'] == record['path']
                      ? pending['oldChecksum']
                      : null))) {
        throw StateError(
          'Recovery target was modified unexpectedly. File preserved; review the pending commit before retrying.',
        );
      }
      if (!await temp.exists() ||
          await checksum(temp.path) != record['sha256']) {
        throw StateError(
          'Recovery data missing or invalid; current copies preserved.',
        );
      }
      await destination.verify();
      await target.parent.create(recursive: true);
      // Rename on the same volume is atomic. The prior current was already archived.
      await temp.rename(target.path);
    }
    await catalog.put('files', pending['key'], record);
    final oldPath = pending['oldPath'];
    if (oldPath != null && oldPath != record['path']) {
      final old = File(destination.path(oldPath));
      if (await old.exists() &&
          await checksum(old.path) == pending['oldChecksum']) {
        await old.delete();
      }
    }
    if (await temp.exists()) await temp.delete();
    await catalog.remove('pending', pending['key']);
  }

  /// Must run under the destination lock. Replays validated commits, never partial downloads.
  Future<void> recover() async {
    for (final pending in await catalog.all('pending')) {
      await _commit(pending);
    }
    for (final previous in await catalog.all('runs')) {
      if (previous['status'] == 'running') {
        previous['status'] = 'interrupted';
        previous['ended'] = DateTime.now().toUtc().toIso8601String();
        await catalog.put('runs', previous['id'], previous);
      }
    }
    final tmp = Directory(destination.path('_metadata/tmp'));
    if (await tmp.exists()) {
      await for (final entity in tmp.list()) {
        if (entity is File && entity.path.endsWith('.part')) {
          await entity.delete();
        }
      }
    }
  }

  Future<void> _prune() async {
    final versions = await catalog.all('versions');
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final version in versions) {
      (grouped[version['key']] ??= []).add(version);
    }
    for (final group in grouped.values) {
      group.sort((a, b) => (b['created'] as String).compareTo(a['created']));
      for (final version in group.skip(retention.clamp(1, 100))) {
        cancellation.check();
        await destination.verify();
        final file = File(destination.path(version['path']));
        if (await file.exists()) {
          if (await checksum(file.path) != version['sha256']) {
            continue; // Preserve unexpected user changes.
          }
          await file.delete();
        }
        await catalog.remove('versions', version['id']);
      }
    }
  }

  Future<void> exportRecoveryMetadata() async {
    final temp = File(destination.path('_metadata/recovery.json.tmp'));
    await temp.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'format': 1,
        'files': await catalog.all('files'),
        'versions': await catalog.all('versions'),
        'sources': await catalog.all('sources'),
        'memberships': await catalog.db.query('membership'),
      }),
      flush: true,
    );
    await temp.rename(destination.path('_metadata/recovery.json'));
  }
}
