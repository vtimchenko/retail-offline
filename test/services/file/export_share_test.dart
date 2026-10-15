import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/services/file/export_share.dart';

void main() {
  group('ExportShareResult', () {
    test('each outcome is a distinct result', () {
      expect(_label(const ExportShareHandedOff()), 'handedOff');
      expect(_label(const ExportShareCancelled()), 'cancelled');
      expect(_label(const ExportShareFailed()), 'failed');
      expect(_label(const ExportShareUnavailable()), 'unavailable');
      expect(
        _label(
          const ExportShareDownloadStarted(
            ExportShareDownloadReason.sharingUnavailable,
          ),
        ),
        'sharingUnavailable',
      );
      expect(
        _label(
          const ExportShareDownloadStarted(
            ExportShareDownloadReason.shareRejected,
          ),
        ),
        'shareRejected',
      );
    });

    test('a started download records why the share sheet was skipped', () {
      const unavailable = ExportShareDownloadStarted(
        ExportShareDownloadReason.sharingUnavailable,
      );
      const rejected = ExportShareDownloadStarted(
        ExportShareDownloadReason.shareRejected,
      );

      expect(unavailable.reason, ExportShareDownloadReason.sharingUnavailable);
      expect(rejected.reason, ExportShareDownloadReason.shareRejected);
    });

    test('the JSON MIME type is application/json', () {
      expect(jsonExportMimeType, 'application/json');
    });
  });

  group('shareOrDownloadJson on the VM', () {
    test('matches the ShareJson typedef', () {
      const ShareJson share = shareOrDownloadJson;
      expect(share, same(shareOrDownloadJson));
    });

    test('rejects sharing and leaves the supplied bytes unchanged', () async {
      final bytes = Uint8List.fromList([
        ...'export ProductID 1290564103789190763'.codeUnits,
        0xFF,
        0x00,
        0xFE,
      ]);
      final before = Uint8List.fromList(bytes);

      await expectLater(
        shareOrDownloadJson(
          filename: 'export_Store_01-A_20261014150722.json',
          bytes: bytes,
        ),
        throwsA(
          isA<UnsupportedError>().having(
            (error) => error.message,
            'message',
            'Sharing a file is only supported in the browser.',
          ),
        ),
      );
      expect(bytes, before);
    });
  });
}

String _label(ExportShareResult result) {
  return switch (result) {
    ExportShareHandedOff() => 'handedOff',
    ExportShareDownloadStarted(:final reason) => reason.name,
    ExportShareCancelled() => 'cancelled',
    ExportShareFailed() => 'failed',
    ExportShareUnavailable() => 'unavailable',
  };
}
