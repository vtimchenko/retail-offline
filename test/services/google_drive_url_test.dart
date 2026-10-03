import 'package:flutter_test/flutter_test.dart';
import 'package:retail_offline/core/errors/import_exception.dart';
import 'package:retail_offline/services/file/google_drive_url.dart';

const _id = '1AbCdEfGhIjKlMnOpQrStUvWxYz_0123-45';

void main() {
  group('GoogleDriveUrl.parseFileId – supported links', () {
    final supported = <String, String>{
      'view link': 'https://drive.google.com/file/d/$_id/view?usp=sharing',
      'view with resourcekey':
          'https://drive.google.com/file/d/$_id/view?usp=drive_link&resourcekey=0-abc',
      'edit link': 'https://drive.google.com/file/d/$_id/edit',
      'no trailing part': 'https://drive.google.com/file/d/$_id',
      'multi-account path': 'https://drive.google.com/file/u/0/d/$_id/view',
      'open?id': 'https://drive.google.com/open?id=$_id',
      'uc?id': 'https://drive.google.com/uc?id=$_id',
      'uc export=download':
          'https://drive.google.com/uc?export=download&id=$_id',
      'usercontent download link pasted by a user':
          'https://drive.usercontent.google.com/download?id=$_id&export=download',
      'spreadsheets /edit': 'https://docs.google.com/spreadsheets/d/$_id/edit',
      'spreadsheets /view': 'https://docs.google.com/spreadsheets/d/$_id/view',
      'spreadsheets /edit with Google share parameters':
          'https://docs.google.com/spreadsheets/d/$_id/edit'
              '?usp=share_link&ouid=100030604935764437060&rtpof=true&sd=true',
      'spreadsheets /edit with gid fragment':
          'https://docs.google.com/spreadsheets/d/$_id/edit?gid=0#gid=0',
      'spreadsheets without trailing part':
          'https://docs.google.com/spreadsheets/d/$_id',
      'spreadsheets multi-account path':
          'https://docs.google.com/spreadsheets/u/0/d/$_id/edit',
      'no scheme': 'drive.google.com/file/d/$_id/view',
      'spreadsheets no scheme': 'docs.google.com/spreadsheets/d/$_id/edit',
      'surrounding whitespace':
          '  https://drive.google.com/file/d/$_id/view \n',
    };
    supported.forEach((name, url) {
      test(name, () => expect(GoogleDriveUrl.parseFileId(url), _id));
    });

    test('the real public test links yield their file ids', () {
      // Ids only; the automated suite never contacts Google.
      expect(
        GoogleDriveUrl.parseFileId(
          'https://docs.google.com/spreadsheets/d/'
          '1yDipQXXT3RV7m3aiXeWVKxUrrYFm0gwf/edit'
          '?usp=share_link&ouid=100030604935764437060&rtpof=true&sd=true',
        ),
        '1yDipQXXT3RV7m3aiXeWVKxUrrYFm0gwf',
      );
      expect(
        GoogleDriveUrl.parseFileId(
          'https://docs.google.com/spreadsheets/d/'
          '1miw2Bnq8VSzFouKpeOB8IefVqGUKKnVo/edit'
          '?usp=share_link&ouid=100030604935764437060&rtpof=true&sd=true',
        ),
        '1miw2Bnq8VSzFouKpeOB8IefVqGUKKnVo',
      );
    });

    test('query parameters never influence the result', () {
      final plain = GoogleDriveUrl.parseFileId(
        'https://docs.google.com/spreadsheets/d/$_id/edit',
      );
      final withParams = GoogleDriveUrl.parseFileId(
        'https://docs.google.com/spreadsheets/d/$_id/edit?sd=false&rtpof=false',
      );
      expect(withParams, plain);
    });
  });

  group('GoogleDriveUrl.exportUri', () {
    test('is the Google Sheets XLSX export endpoint', () {
      expect(
        GoogleDriveUrl.exportUri(_id).toString(),
        'https://docs.google.com/spreadsheets/d/$_id/export?format=xlsx',
      );
    });

    test('is the same for every link form of one file', () {
      final links = [
        'https://drive.google.com/file/d/$_id/view',
        'https://drive.google.com/open?id=$_id',
        'https://drive.google.com/uc?export=download&id=$_id',
        'https://docs.google.com/spreadsheets/d/$_id/edit?rtpof=true&sd=true',
      ];
      final uris = links
          .map((l) => GoogleDriveUrl.exportUri(GoogleDriveUrl.parseFileId(l)))
          .toSet();
      expect(uris, hasLength(1));
      expect(uris.single.host, 'docs.google.com');
    });
  });

  group('GoogleDriveUrl.parseFileId – rejected input', () {
    String messageOf(String input) {
      try {
        GoogleDriveUrl.parseFileId(input);
      } on ImportException catch (e) {
        return e.message;
      }
      fail('Expected ImportException for "$input"');
    }

    test('empty', () => expect(messageOf('   '), contains('Вставте')));

    test(
      'not a URL',
      () => expect(messageOf('hello world'), contains('Google Drive')),
    );

    test('other host', () {
      expect(messageOf('https://example.com/file/d/$_id/view'), isNotEmpty);
      expect(
        messageOf('https://example.com/spreadsheets/d/$_id/edit'),
        isNotEmpty,
      );
    });

    test('drive link without a file id', () {
      expect(messageOf('https://drive.google.com/file/d/'), isNotEmpty);
      expect(messageOf('https://drive.google.com/'), isNotEmpty);
    });

    test('spreadsheets link without a file id', () {
      expect(messageOf('https://docs.google.com/spreadsheets/'), isNotEmpty);
      expect(messageOf('https://docs.google.com/spreadsheets/d/'), isNotEmpty);
      expect(messageOf('https://docs.google.com/spreadsheets/u/0/'), isNotEmpty);
    });

    test('published-to-web spreadsheet link is not a file link', () {
      expect(
        messageOf(
          'https://docs.google.com/spreadsheets/d/e/2PACX-1vSabcdefghij/pubhtml',
        ),
        isNotEmpty,
      );
    });

    test('too short id', () {
      expect(messageOf('https://drive.google.com/open?id=abc'), isNotEmpty);
      expect(
        messageOf('https://docs.google.com/spreadsheets/d/abc/edit'),
        isNotEmpty,
      );
    });

    test('folder link has a specific message', () {
      expect(
        messageOf('https://drive.google.com/drive/folders/$_id'),
        contains('папку'),
      );
      expect(
        messageOf('https://drive.google.com/drive/u/0/folders/$_id'),
        contains('папку'),
      );
    });

    test('Google Docs link is rejected with a specific message', () {
      expect(
        messageOf('https://docs.google.com/document/d/$_id/edit'),
        contains('документ'),
      );
    });

    test('Google Slides link is rejected with a specific message', () {
      expect(
        messageOf('https://docs.google.com/presentation/d/$_id/edit'),
        contains('презентацію'),
      );
    });

    test('Google Forms link is rejected with a specific message', () {
      expect(
        messageOf('https://docs.google.com/forms/d/$_id/edit'),
        contains('форму'),
      );
    });
  });
}
