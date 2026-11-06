import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../core/models.dart';
import 'drive_adapter.dart';
import 'google_auth.dart';

class GoogleDrive implements DriveAdapter {
  final GoogleAuth auth;
  final http.Client client;
  String account = '', email = '';
  Map<String, List<String>> exportFormats = {};
  static const fields =
      'id,name,mimeType,parents,size,md5Checksum,modifiedTime,version,trashed,capabilities(canDownload),shortcutDetails(targetId,targetMimeType)';
  GoogleDrive(this.auth, {http.Client? client})
    : client = client ?? http.Client();
  Future<http.StreamedResponse> _get(
    String path,
    Map<String, String> query,
    Cancellation cancel,
  ) async {
    for (var attempt = 0; ; attempt++) {
      cancel.check();
      try {
        final token = await auth.accessToken();
        final request = http.Request(
          'GET',
          Uri.https('www.googleapis.com', '/drive/v3/$path', query),
        );
        request.headers['Authorization'] = 'Bearer $token';
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 30));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        final text = await response.stream.bytesToString().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode == 401 && attempt == 0) {
          await auth.accessToken(force: true);
          continue;
        }
        String reason = '';
        try {
          reason =
              '${jsonDecode(text)['error']['errors']?[0]?['reason'] ?? ''}';
        } catch (_) {
          /* Status is sufficient. */
        }
        final retry =
            response.statusCode == 429 ||
            response.statusCode >= 500 ||
            [
              'rateLimitExceeded',
              'userRateLimitExceeded',
              'downloadQuotaExceeded',
            ].contains(reason);
        throw DriveFailure(
          'Google Drive ${response.statusCode}${reason.isEmpty ? '' : ' ($reason)'}. ${response.statusCode == 401 ? 'Reconnect your account.' : 'File may be inaccessible, restricted, or over an export/download limit.'}',
          retryable: retry,
        );
      } catch (e) {
        final retry =
            e is SocketException ||
            e is TimeoutException ||
            e is http.ClientException ||
            e is DriveFailure && e.retryable;
        if (!retry || attempt >= 3) rethrow;
        await cancel.delay(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
  }

  Future<Map<String, dynamic>> _json(
    String path,
    Map<String, String> query,
    Cancellation cancel,
  ) async {
    final response = await _get(path, query, cancel);
    return jsonDecode(
          await response.stream.bytesToString().timeout(
            const Duration(seconds: 30),
          ),
        )
        as Map<String, dynamic>;
  }

  Future<void> identify() async {
    final j = await _json('about', {
      'fields': 'user(emailAddress,permissionId),exportFormats',
    }, Cancellation());
    account = j['user']['permissionId'];
    email = j['user']['emailAddress'] ?? account;
    exportFormats = (j['exportFormats'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, List<String>.from(value)),
    );
  }

  @override
  Future<List<BackupSource>> discover() async {
    await identify();
    final cancel = Cancellation();
    final root = await stat('root', cancel);
    final result = [
      BackupSource(
        account: account,
        driveId: 'my-drive',
        rootId: root.id,
        name: 'My Drive',
      ),
    ];
    String? page;
    do {
      final j = await _json('drives', {
        'pageSize': '100',
        'fields': 'nextPageToken,drives(id,name)',
        'pageToken': ?page,
      }, cancel);
      for (final d in j['drives'] ?? []) {
        result.add(
          BackupSource(
            account: account,
            driveId: d['id'],
            rootId: d['id'],
            name: d['name'],
          ),
        );
      }
      page = j['nextPageToken'];
    } while (page != null);
    return result;
  }

  @override
  Future<CloudFile> stat(String id, Cancellation cancellation) async =>
      CloudFile.fromJson(
        await _json('files/${Uri.encodeComponent(id)}', {
          'supportsAllDrives': 'true',
          'fields': fields,
        }, cancellation),
      );
  @override
  Future<List<CloudFile>> children(
    BackupSource source,
    String parentId,
    Cancellation cancellation,
  ) async {
    final files = <CloudFile>[];
    String? page;
    do {
      final escaped = parentId.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      final j = await _json('files', {
        'q': "'$escaped' in parents",
        'pageSize': '1000',
        'spaces': 'drive',
        'supportsAllDrives': 'true',
        'includeItemsFromAllDrives': 'true',
        'corpora': source.isMyDrive ? 'user' : 'drive',
        if (!source.isMyDrive) 'driveId': source.driveId,
        'fields': 'nextPageToken,incompleteSearch,files($fields)',
        'pageToken': ?page,
      }, cancellation);
      if (j['incompleteSearch'] == true) {
        throw const DriveFailure(
          'Google returned an incomplete source scan. Deletion detection is disabled for this source.',
        );
      }
      files.addAll(
        (j['files'] as List? ?? []).map((f) => CloudFile.fromJson(f)),
      );
      page = j['nextPageToken'];
    } while (page != null);
    return files;
  }

  @override
  Future<Stream<List<int>>> download(
    CloudFile file,
    String? exportMime,
    Cancellation cancellation,
  ) async {
    if (!file.canDownload) {
      throw const DriveFailure(
        'Download restricted by owner or Workspace policy.',
      );
    }
    if (exportMime != null &&
        !(exportFormats[file.mime]?.contains(exportMime) ?? false)) {
      throw const DriveFailure(
        'This Google-native export format is unsupported by this account.',
      );
    }
    final response = await _get(
      'files/${Uri.encodeComponent(file.id)}${exportMime == null ? '' : '/export'}',
      exportMime == null
          ? {'alt': 'media', 'supportsAllDrives': 'true'}
          : {'mimeType': exportMime},
      cancellation,
    );
    return response.stream.timeout(const Duration(seconds: 30));
  }
}
