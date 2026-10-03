import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:retail_offline/core/constants/import_messages.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/models/imported_file.dart';
import 'package:retail_offline/services/excel/excel_import_service.dart';
import 'package:retail_offline/services/file/google_drive_file_service.dart';

import '../support/fixtures.dart';

const _id = '1AbCdEfGhIjKlMnOpQrStUvWxYz_0123-45';
const _driveUrl = 'https://drive.google.com/file/d/$_id/view?usp=sharing';
const _sheetsUrl =
    'https://docs.google.com/spreadsheets/d/$_id/edit?usp=share_link'
    '&ouid=100030604935764437060&rtpof=true&sd=true';
const _exportUrl =
    'https://docs.google.com/spreadsheets/d/$_id/export?format=xlsx';

/// No test touches Google: the HTTP client is a stub.
GoogleDriveFileService _service(MockClientHandler handler) =>
    GoogleDriveFileService(client: MockClient(handler));

Future<ImportException> _failure(
  GoogleDriveFileService s, [
  String url = _driveUrl,
]) async {
  try {
    await s.download(url);
  } on ImportException catch (e) {
    return e;
  }
  fail('Expected ImportException');
}

void main() {
  final xlsx = ordersXlsx([orderRow()]);

  group('request', () {
    test('Google Sheets link → XLSX export endpoint, nothing else', () async {
      final requested = <Uri>[];
      await _service((request) async {
        requested.add(request.url);
        expect(request.method, 'GET');
        return http.Response.bytes(xlsx, 200);
      }).download(_sheetsUrl);

      expect(requested, hasLength(1));
      expect(requested.single.toString(), _exportUrl);
    });

    test('Drive file link → the same XLSX export endpoint', () async {
      late Uri requested;
      await _service((request) async {
        requested = request.url;
        return http.Response.bytes(xlsx, 200);
      }).download(_driveUrl);

      expect(requested.toString(), _exportUrl);
      expect(requested.host, isNot('drive.usercontent.google.com'));
    });

    for (final url in [
      'https://drive.google.com/open?id=$_id',
      'https://drive.google.com/uc?id=$_id',
      'https://drive.google.com/uc?export=download&id=$_id',
      'https://docs.google.com/spreadsheets/d/$_id/view',
    ]) {
      test('$url → export endpoint', () async {
        late Uri requested;
        await _service((request) async {
          requested = request.url;
          return http.Response.bytes(xlsx, 200);
        }).download(url);
        expect(requested.toString(), _exportUrl);
      });
    }

    test('invalid link fails before any request', () async {
      var called = false;
      final e = await _failure(
        _service((_) async {
          called = true;
          return http.Response('', 200);
        }),
        'https://example.com/x',
      );
      expect(called, isFalse);
      expect(e.message, contains('Google Drive'));
    });

    test('Docs / Slides / Forms / folders fail before any request', () async {
      var called = false;
      final s = _service((_) async {
        called = true;
        return http.Response('', 200);
      });
      for (final url in [
        'https://docs.google.com/document/d/$_id/edit',
        'https://docs.google.com/presentation/d/$_id/edit',
        'https://docs.google.com/forms/d/$_id/edit',
        'https://drive.google.com/drive/folders/$_id',
      ]) {
        await _failure(s, url);
      }
      expect(called, isFalse);
    });
  });

  group('successful download', () {
    test('returns XLSX bytes as a Google Drive ImportedFile', () async {
      final file = await _service(
        (_) async => http.Response.bytes(
          xlsx,
          200,
          headers: {
            'content-type':
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'content-disposition': 'attachment; filename="orders.xlsx"',
          },
        ),
      ).download(_sheetsUrl);

      expect(file.source, FileSource.googleDrive);
      expect(file.name, 'orders.xlsx');
      expect(file.bytes, xlsx);
    });

    test('the downloaded bytes are accepted by the Excel reader', () async {
      final file = await _service(
        (_) async => http.Response.bytes(xlsx, 200),
      ).download(_sheetsUrl);
      final sheet = ExcelImportService().readFirstSheet(file.bytes);
      expect(sheet.rows, isNotEmpty);
    });

    test('Content-Disposition: plain filename', () async {
      final file = await _service(
        (_) async => http.Response.bytes(
          xlsx,
          200,
          headers: {'content-disposition': 'attachment; filename=plain.xlsx'},
        ),
      ).download(_sheetsUrl);
      expect(file.name, 'plain.xlsx');
    });

    test('Content-Disposition: UTF-8 filename* decoded', () async {
      final file = await _service(
        (_) async => http.Response.bytes(
          xlsx,
          200,
          headers: {
            'content-disposition':
                "attachment; filename*=UTF-8''%D0%B7%D0%B0%D0%BC.xlsx",
          },
        ),
      ).download(_sheetsUrl);
      expect(file.name, 'зам.xlsx');
    });

    test('filename* is preferred over filename', () async {
      final file = await _service(
        (_) async => http.Response.bytes(
          xlsx,
          200,
          headers: {
            'content-disposition':
                'attachment; filename="listOrders _.xlsx"; '
                "filename*=UTF-8''listOrders%20%D0%BA%D0%BE%D0%BF%D1%96%D1%8F.xlsx",
          },
        ),
      ).download(_sheetsUrl);
      expect(file.name, 'listOrders копія.xlsx');
    });

    test('malformed filename* falls back to filename', () async {
      final file = await _service(
        (_) async => http.Response.bytes(
          xlsx,
          200,
          headers: {
            'content-disposition':
                'attachment; filename="safe.xlsx"; filename*=UTF-8\'\'%E0%A4%A',
          },
        ),
      ).download(_sheetsUrl);
      expect(file.name, 'safe.xlsx');
    });

    test('unparsable Content-Disposition falls back to <id>.xlsx', () async {
      final file = await _service(
        (_) async => http.Response.bytes(
          xlsx,
          200,
          headers: {'content-disposition': 'attachment'},
        ),
      ).download(_sheetsUrl);
      expect(file.name, '$_id.xlsx');
    });

    test('missing Content-Disposition (not exposed) → <id>.xlsx', () async {
      final file = await _service(
        (_) async => http.Response.bytes(xlsx, 200),
      ).download(_sheetsUrl);
      expect(file.name, '$_id.xlsx');
      expect(file.bytes, xlsx);
    });
  });

  group('failures share one clear Ukrainian message', () {
    void expectBlocked(ImportException e) {
      expect(e.message, ImportMessages.driveDownloadBlocked);
      expect(e.message, contains('Обрати файл'));
    }

    test('network/CORS failure', () async {
      final e = await _failure(
        _service((_) => throw http.ClientException('XMLHttpRequest error.')),
      );
      expectBlocked(e);
      expect(e.message, isNot(contains('XMLHttpRequest')));
    });

    test('HTTP error status (incl. 404 for an unknown id, 401/403)', () async {
      for (final status in [401, 403, 404, 429, 500]) {
        final e = await _failure(
          _service((_) async => http.Response('nope', status)),
        );
        expectBlocked(e);
        expect(e.technical, 'HTTP $status');
      }
    });

    test('HTML sign-in / permission page with status 200', () async {
      final e = await _failure(
        _service(
          (_) async => http.Response(
            '<!DOCTYPE html><html><body>Sign in</body></html>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        ),
      );
      expectBlocked(e);
      expect(e.technical, contains('HTML'));
    });

    test('HTML page with leading whitespace', () async {
      final e = await _failure(
        _service((_) async => http.Response('\n  <html><body/></html>', 200)),
      );
      expectBlocked(e);
      expect(e.technical, contains('HTML'));
    });

    test('a 200 response with unsupported content', () async {
      final e = await _failure(
        _service(
          (_) async =>
              http.Response.bytes(Uint8List.fromList([1, 2, 3, 4, 5]), 200),
        ),
      );
      expectBlocked(e);
      expect(e.technical, contains('not a ZIP'));
    });

    test('empty body', () async {
      final e = await _failure(
        _service((_) async => http.Response.bytes(Uint8List(0), 200)),
      );
      expectBlocked(e);
    });

    test('PK prefix but not a ZIP local header', () async {
      final e = await _failure(
        _service(
          (_) async => http.Response.bytes(
            Uint8List.fromList([0x50, 0x4B, 0x00, 0x00, 1, 2]),
            200,
          ),
        ),
      );
      expectBlocked(e);
    });

    test('timeout', () async {
      final service = GoogleDriveFileService(
        client: MockClient(
          (_) => Future.delayed(
            const Duration(seconds: 2),
            () => http.Response('', 200),
          ),
        ),
        timeout: const Duration(milliseconds: 20),
      );
      final e = await _failure(service);
      expectBlocked(e);
      expect(e.cause, isA<TimeoutException>());
    });
  });
}
