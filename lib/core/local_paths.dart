import 'dart:convert';
import 'package:path/path.dart' as p;
import 'models.dart';

/// IDs on every segment make names deterministic even on case-insensitive NTFS.
String safeSegment(String name, String id, {String extension = ''}) {
  var safe = name
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '')
      .trim();
  if (safe.isEmpty) safe = 'unnamed';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(safe)) {
    safe = '_$safe';
  }
  // Runes avoid splitting surrogate pairs in Unicode names.
  safe = String.fromCharCodes(safe.runes.take(40));
  return '$safe~${digestId(id)}$extension';
}

String relativeFilePath(
  BackupSource source,
  List<CloudFile> ancestors,
  CloudFile file,
  String extension,
) {
  var displayName = file.name;
  if (extension.isEmpty && !file.isNative && !file.isShortcut) {
    final candidate = p.extension(file.name);
    if (candidate.length <= 16 &&
        RegExp(r'^\.[a-zA-Z0-9_-]+$').hasMatch(candidate)) {
      extension = candidate;
      displayName = file.name.substring(0, file.name.length - candidate.length);
    }
  }
  final base = source.isMyDrive
      ? 'My_Drive'
      : p.join(
          'Shared_Drives',
          safeSegment(source.name.split(' / ').first, source.driveId),
        );
  final pieces = [
    ...ancestors.map((f) => safeSegment(f.name, f.id)),
    safeSegment(displayName, file.id, extension: extension),
  ];
  var relative = p.join(base, p.joinAll(pieces));
  if (relative.length > 170) {
    relative = p.join(
      base,
      '_long_paths',
      safeSegment(displayName, file.id, extension: extension),
    );
  }
  return relative;
}

String insideRoot(String root, String relative) {
  if (p.isAbsolute(relative) || p.split(relative).contains('..')) {
    throw StateError('Unsafe catalog path.');
  }
  final result = p.normalize(p.join(root, relative));
  if (!p.isWithin(p.normalize(p.absolute(root)), p.absolute(result))) {
    throw StateError('Path escapes backup root.');
  }
  return result;
}

String fileKey(BackupSource source, CloudFile file) =>
    digestId(jsonEncode([source.account, source.driveId, file.id]));
