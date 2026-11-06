import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

String uid() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
String digestId(String value) =>
    sha256.convert(utf8.encode(value)).toString().substring(0, 16);

class BackupSource {
  final String account, driveId, rootId, name;
  const BackupSource({
    required this.account,
    required this.driveId,
    required this.rootId,
    required this.name,
  });
  String get key => digestId('$account|$driveId|$rootId');
  bool get isMyDrive => driveId == 'my-drive';
  Map<String, dynamic> toJson() => {
    'account': account,
    'driveId': driveId,
    'rootId': rootId,
    'name': name,
  };
  factory BackupSource.fromJson(Map<String, dynamic> j) => BackupSource(
    account: j['account'],
    driveId: j['driveId'],
    rootId: j['rootId'],
    name: j['name'],
  );
}

class CloudFile {
  final String id, name, mime, modified, revision;
  final List<String> parents;
  final int? size;
  final String? md5Checksum, targetId, targetMime;
  final bool trashed, canDownload;
  const CloudFile({
    required this.id,
    required this.name,
    this.mime = 'application/octet-stream',
    this.modified = '',
    this.revision = '',
    this.parents = const [],
    this.size,
    this.md5Checksum,
    this.targetId,
    this.targetMime,
    this.trashed = false,
    this.canDownload = true,
  });
  bool get isFolder => mime == 'application/vnd.google-apps.folder';
  bool get isShortcut => mime == 'application/vnd.google-apps.shortcut';
  bool get isNative =>
      mime.startsWith('application/vnd.google-apps.') &&
      !isFolder &&
      !isShortcut;
  String fingerprint(String? exportMime) =>
      '$revision|$modified|$size|$md5Checksum|$mime|$exportMime|$targetId';
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mimeType': mime,
    'modifiedTime': modified,
    'version': revision,
    'parents': parents,
    'size': size?.toString(),
    'md5Checksum': md5Checksum,
    'trashed': trashed,
    'capabilities': {'canDownload': canDownload},
    'shortcutDetails': {'targetId': targetId, 'targetMimeType': targetMime},
  };
  factory CloudFile.fromJson(Map<String, dynamic> j) => CloudFile(
    id: j['id'],
    name: j['name'],
    mime: j['mimeType'] ?? '',
    modified: j['modifiedTime'] ?? '',
    revision: '${j['version'] ?? ''}',
    parents: List<String>.from(j['parents'] ?? []),
    size: int.tryParse('${j['size']}'),
    md5Checksum: j['md5Checksum'],
    targetId: j['shortcutDetails']?['targetId'],
    targetMime: j['shortcutDetails']?['targetMimeType'],
    trashed: j['trashed'] == true,
    canDownload: j['capabilities']?['canDownload'] != false,
  );
}

class ExportFormat {
  final String mime, extension;
  const ExportFormat(this.mime, this.extension);
}

ExportFormat? exportFor(CloudFile file, {bool pdf = false}) {
  if (pdf &&
      const [
        'application/vnd.google-apps.document',
        'application/vnd.google-apps.spreadsheet',
        'application/vnd.google-apps.presentation',
        'application/vnd.google-apps.drawing',
      ].contains(file.mime)) {
    return const ExportFormat('application/pdf', '.pdf');
  }
  return switch (file.mime) {
    'application/vnd.google-apps.document' => const ExportFormat(
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.docx',
    ),
    'application/vnd.google-apps.spreadsheet' => const ExportFormat(
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.xlsx',
    ),
    'application/vnd.google-apps.presentation' => const ExportFormat(
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      '.pptx',
    ),
    'application/vnd.google-apps.drawing' => const ExportFormat(
      'image/svg+xml',
      '.svg',
    ),
    'application/vnd.google-apps.script' => const ExportFormat(
      'application/vnd.google-apps.script+json',
      '.json',
    ),
    _ => null,
  };
}

class Cancelled implements Exception {
  @override
  String toString() => 'Backup cancelled safely.';
}

class Cancellation {
  bool cancelled = false;
  void check() {
    if (cancelled) throw Cancelled();
  }

  Future<void> delay(Duration duration) async {
    var remaining = duration.inMilliseconds;
    while (remaining > 0) {
      check();
      final step = min(remaining, 100);
      await Future<void>.delayed(Duration(milliseconds: step));
      remaining -= step;
    }
    check();
  }
}

class DriveFailure implements Exception {
  final String message;
  final bool retryable;
  const DriveFailure(this.message, {this.retryable = false});
  @override
  String toString() => message;
}

class BackupProgress {
  String stage = 'Ready', source = '', file = '', detail = '';
  int completed = 0, skipped = 0, failed = 0, bytes = 0, totalFiles = 0;
  bool totalKnown = false;
  final Stopwatch elapsed = Stopwatch();
  double get speed => bytes / max(1, elapsed.elapsedMilliseconds / 1000);
}
