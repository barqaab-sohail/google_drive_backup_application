import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../core/models.dart';

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class WindowsSecretStore implements SecretStore {
  final FlutterSecureStorage storage = const FlutterSecureStorage();
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class GoogleAuth {
  static const scope = 'https://www.googleapis.com/auth/drive.readonly';
  final SecretStore storage;
  final http.Client client;
  final Future<bool> Function(Uri) openBrowser;
  String clientId = '';
  String? _access;
  DateTime _expiry = DateTime(2000);
  Future<String>? _refreshing;
  GoogleAuth({
    SecretStore? storage,
    http.Client? client,
    Future<bool> Function(Uri)? openBrowser,
  }) : storage = storage ?? WindowsSecretStore(),
       client = client ?? http.Client(),
       openBrowser =
           openBrowser ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));
  String get _tokenKey => 'barqaab.refresh.${digestId(clientId)}';
  String get _secretKey => 'barqaab.client.${digestId(clientId)}';
  String _random() => base64Url
      .encode(List<int>.generate(48, (_) => Random.secure().nextInt(256)))
      .replaceAll('=', '');
  Future<void> configure(String id, String secret) async {
    if (id.trim() != clientId) {
      _access = null;
      _expiry = DateTime(2000);
    }
    clientId = id.trim();
    if (secret.isNotEmpty) {
      await storage.write(_secretKey, secret.trim());
    }
  }

  Future<bool> get hasCredentials async =>
      clientId.isNotEmpty && await storage.read(_tokenKey) != null;
  Future<void> disconnect() async {
    await storage.delete(_tokenKey);
    _access = null;
    _expiry = DateTime(2000);
  }

  Future<void> connect() async {
    if (clientId.isEmpty) {
      throw StateError(
        'Import a Google Desktop OAuth client JSON in Settings first.',
      );
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}/oauth2callback';
    final state = _random(), verifier = _random();
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');
    final result = Completer<String>();
    final subscription = server.listen((request) async {
      if (request.uri.path != '/oauth2callback' ||
          request.uri.queryParameters['state'] != state) {
        request.response.statusCode = 400;
        request.response.write('Invalid OAuth callback.');
        await request.response.close();
        return;
      }
      final code = request.uri.queryParameters['code'];
      request.response.headers.contentType = ContentType.text;
      request.response.write(
        code == null
            ? 'Authorization was not granted. Return to BARQAAB.'
            : 'Authorization received. You may close this window and return to BARQAAB.',
      );
      await request.response.close();
      if (!result.isCompleted) {
        if (code == null) {
          result.completeError(
            const DriveFailure('Google authorization was denied.'),
          );
        } else {
          result.complete(code);
        }
      }
    });
    try {
      final uri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': scope,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'access_type': 'offline',
        'prompt': 'consent select_account',
      });
      if (!await openBrowser(uri)) {
        throw StateError('Unable to launch the system browser.');
      }
      final code = await result.future.timeout(
        const Duration(minutes: 4),
        onTimeout: () => throw const DriveFailure(
          'Google sign-in timed out. Click Connect to retry.',
        ),
      );
      await _token({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirect,
        'code_verifier': verifier,
      });
      if (!await hasCredentials) {
        throw const DriveFailure(
          'No refresh authorization received. Reconnect and grant offline access.',
        );
      }
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  }

  Future<String> accessToken({bool force = false}) async {
    if (!force && _access != null && DateTime.now().isBefore(_expiry)) {
      return _access!;
    }
    if (_refreshing != null) return _refreshing!;
    final future = _refresh();
    _refreshing = future;
    try {
      return await future;
    } finally {
      _refreshing = null;
    }
  }

  Future<String> _refresh() async {
    final refresh = await storage.read(_tokenKey);
    if (refresh == null) {
      throw const DriveFailure('Google is disconnected. Connect your account.');
    }
    await _token({'grant_type': 'refresh_token', 'refresh_token': refresh});
    return _access!;
  }

  Future<void> _token(Map<String, String> body) async {
    final secret = await storage.read(_secretKey);
    final response = await client
        .post(
          Uri.https('oauth2.googleapis.com', '/token'),
          body: {...body, 'client_id': clientId, 'client_secret': ?secret},
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      final invalid = response.statusCode == 400 || response.statusCode == 401;
      if (invalid) {
        _access = null;
        _expiry = DateTime(2000);
      }
      throw DriveFailure(
        invalid
            ? 'Google authorization expired or OAuth configuration is invalid. Reconnect in Settings.'
            : 'Google token service unavailable (${response.statusCode}). Retry.',
        retryable: !invalid,
      );
    }
    final j = jsonDecode(response.body);
    if (body['grant_type'] == 'authorization_code' &&
        j['refresh_token'] == null) {
      throw const DriveFailure(
        'Google did not return offline authorization. Reconnect and grant consent.',
      );
    }
    _access = j['access_token'];
    _expiry = DateTime.now().add(
      Duration(seconds: (j['expires_in'] as int? ?? 3600) - 60),
    );
    if (j['refresh_token'] != null) {
      await storage.write(_tokenKey, j['refresh_token']);
    }
  }
}
