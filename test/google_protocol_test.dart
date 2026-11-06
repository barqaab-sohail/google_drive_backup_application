import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:barqaab_google_drive_backup/core/models.dart';
import 'package:barqaab_google_drive_backup/drive/google_auth.dart';
import 'package:barqaab_google_drive_backup/drive/google_drive.dart';
import 'package:barqaab_google_drive_backup/services/windows_disk.dart';

class MemorySecrets implements SecretStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

class FakeAuth extends GoogleAuth {
  int forced = 0;
  @override
  Future<String> accessToken({bool force = false}) async {
    if (force) forced++;
    return 'fake-access';
  }
}

http.Response jsonResponse(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'OAuth uses loopback, state and S256 PKCE; refresh tokens stay in secret store',
    () async {
      final secrets = MemorySecrets();
      late Uri authorization;
      final callbackDone = Completer<void>();
      final client = MockClient((request) async {
        expect(request.url.host, 'oauth2.googleapis.com');
        final body = Uri.splitQueryString(request.body);
        final challenge = base64Url
            .encode(sha256.convert(ascii.encode(body['code_verifier']!)).bytes)
            .replaceAll('=', '');
        expect(challenge, authorization.queryParameters['code_challenge']);
        expect(body['grant_type'], 'authorization_code');
        expect(body['code'], 'fake-code');
        return jsonResponse({
          'access_token': 'fake-access',
          'refresh_token': 'fake-refresh',
          'expires_in': 3600,
        });
      });
      final auth = GoogleAuth(
        storage: secrets,
        client: client,
        openBrowser: (uri) async {
          authorization = uri;
          expect(uri.host, 'accounts.google.com');
          expect(uri.queryParameters['scope'], GoogleAuth.scope);
          expect(uri.queryParameters['code_challenge_method'], 'S256');
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          expect(redirect.host, '127.0.0.1');
          // Exercise the actual loopback HTTP server; no Google account is used.
          unawaited(() async {
            try {
              final wrong = await http.get(
                redirect.replace(
                  queryParameters: {'state': 'wrong', 'code': 'bad'},
                ),
              );
              expect(wrong.statusCode, 400);
              final valid = await http.get(
                redirect.replace(
                  queryParameters: {
                    'state': uri.queryParameters['state']!,
                    'code': 'fake-code',
                  },
                ),
              );
              expect(valid.statusCode, 200);
              callbackDone.complete();
            } catch (e, stack) {
              callbackDone.completeError(e, stack);
            }
          }());
          return true;
        },
      );
      await auth.configure('fake-desktop-client', 'fake-client-secret');
      await auth.connect();
      await callbackDone.future;
      expect(await auth.accessToken(), 'fake-access');
      expect(await auth.hasCredentials, isTrue);
      expect(secrets.data.values, contains('fake-refresh'));
      expect(secrets.data.values, isNot(contains('fake-access')));
      await auth.disconnect();
      expect(await auth.hasCredentials, isFalse);
      client.close();
    },
  );
  test(
    'parallel requests share one refresh and expired authorization reports reconnect',
    () async {
      final secrets = MemorySecrets();
      final auth = GoogleAuth(storage: secrets);
      auth.clientId = 'client';
      await secrets.write(
        'barqaab.refresh.${digestId('client')}',
        'fake-refresh',
      );
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return jsonResponse({'access_token': 'new-access', 'expires_in': 3600});
      });
      final usable = GoogleAuth(storage: secrets, client: client)
        ..clientId = 'client';
      expect(
        await Future.wait(List.generate(4, (_) => usable.accessToken())),
        everyElement('new-access'),
      );
      expect(calls, 1);
      final expired = GoogleAuth(
        storage: secrets,
        client: MockClient(
          (_) async => jsonResponse({'error': 'invalid_grant'}, 400),
        ),
      )..clientId = 'client';
      await expectLater(
        expired.accessToken(),
        throwsA(
          isA<DriveFailure>().having(
            (e) => e.message,
            'message',
            contains('Reconnect'),
          ),
        ),
      );
      client.close();
      auth.client.close();
    },
  );
  test(
    'discovery paginates Shared drives and children use required parameters',
    () async {
      var drivePages = 0, filePages = 0;
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer fake-access');
        final url = request.url, query = request.url.queryParameters;
        if (url.path.endsWith('/about')) {
          return jsonResponse({
            'user': {
              'permissionId': 'account',
              'emailAddress': 'account@example.test',
            },
            'exportFormats': {},
          });
        }
        if (url.path.endsWith('/files/root')) {
          return jsonResponse({
            'id': 'my-root',
            'name': 'My Drive',
            'mimeType': 'application/vnd.google-apps.folder',
          });
        }
        if (url.path.endsWith('/drives')) {
          drivePages++;
          if (query['pageToken'] == null) {
            return jsonResponse({
              'drives': [
                {'id': 'shared-a', 'name': 'Application Data'},
              ],
              'nextPageToken': 'page2',
            });
          }
          expect(query['pageToken'], 'page2');
          return jsonResponse({
            'drives': [
              {'id': 'shared-b', 'name': 'HAZECO Data'},
            ],
          });
        }
        expect(query['supportsAllDrives'], 'true');
        expect(query['includeItemsFromAllDrives'], 'true');
        expect(query['corpora'], 'drive');
        expect(query['driveId'], 'shared-a');
        filePages++;
        return jsonResponse({
          'files': [
            {'id': '$filePages', 'name': 'file$filePages'},
          ],
          if (query['pageToken'] == null) 'nextPageToken': 'more',
        });
      });
      final drive = GoogleDrive(FakeAuth(), client: client);
      final sources = await drive.discover();
      expect(sources.length, 3);
      expect(drivePages, 2);
      expect(
        (await drive.children(
          sources[1],
          sources[1].rootId,
          Cancellation(),
        )).length,
        2,
      );
      expect(filePages, 2);
      client.close();
    },
  );
  test(
    'incompleteSearch fails instead of permitting deletion inference',
    () async {
      final drive = GoogleDrive(
        FakeAuth(),
        client: MockClient(
          (_) async => jsonResponse({'files': [], 'incompleteSearch': true}),
        ),
      );
      const source = BackupSource(
        account: 'a',
        driveId: 'my-drive',
        rootId: 'root',
        name: 'My Drive',
      );
      await expectLater(
        drive.children(source, 'root', Cancellation()),
        throwsA(isA<DriveFailure>()),
      );
      drive.client.close();
    },
  );
  test(
    'media download and export use distinct supported API parameters',
    () async {
      var calls = 0;
      final drive = GoogleDrive(
        FakeAuth(),
        client: MockClient((request) async {
          calls++;
          final query = request.url.queryParameters;
          if (request.url.path.endsWith('/export')) {
            expect(query['mimeType'], 'application/pdf');
            expect(query.containsKey('supportsAllDrives'), false);
          } else {
            expect(query['alt'], 'media');
            expect(query['supportsAllDrives'], 'true');
          }
          return http.Response('content', 200);
        }),
      );
      drive.exportFormats['application/vnd.google-apps.document'] = [
        'application/pdf',
      ];
      expect(
        await (await drive.download(
          const CloudFile(id: 'blob', name: 'blob'),
          null,
          Cancellation(),
        )).expand((bytes) => bytes).length,
        7,
      );
      await (await drive.download(
        const CloudFile(
          id: 'doc',
          name: 'Doc',
          mime: 'application/vnd.google-apps.document',
        ),
        'application/pdf',
        Cancellation(),
      )).drain<void>();
      expect(calls, 2);
      await expectLater(
        drive.download(
          const CloudFile(
            id: 'doc',
            name: 'Doc',
            mime: 'application/vnd.google-apps.document',
          ),
          'unsupported',
          Cancellation(),
        ),
        throwsA(isA<DriveFailure>()),
      );
      drive.client.close();
    },
  );
  test('401 refresh and bounded rate-limit retry recover', () async {
    var calls = 0;
    final auth = FakeAuth();
    final drive = GoogleDrive(
      auth,
      client: MockClient((_) async {
        calls++;
        return calls == 1
            ? jsonResponse({}, 401)
            : calls == 2
            ? jsonResponse({
                'error': {
                  'errors': [
                    {'reason': 'rateLimitExceeded'},
                  ],
                },
              }, 403)
            : jsonResponse({'id': 'x', 'name': 'X'});
      }),
    );
    expect((await drive.stat('x', Cancellation())).id, 'x');
    expect(auth.forced, 1);
    expect(calls, 3);
    drive.client.close();
  });
  test('Windows disk probe returns free space and stable volume GUID', () {
    if (!Platform.isWindows) return;
    final disk = inspectDisk(Directory.systemTemp.path);
    expect(disk.freeBytes, greaterThan(0));
    expect(disk.identity, startsWith(r'\\?\Volume{'));
  });
}
