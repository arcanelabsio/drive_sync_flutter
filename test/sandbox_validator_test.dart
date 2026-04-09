import 'package:test/test.dart';
import 'package:drive_sync_flutter/drive_sync_flutter.dart';

void main() {
  group('SandboxValidator.validateAppName', () {
    test('accepts valid lowercase snake_case names', () {
      expect(
        () => SandboxValidator.validateAppName('longeviti'),
        returnsNormally,
      );
      expect(() => SandboxValidator.validateAppName('my_app'), returnsNormally);
      expect(() => SandboxValidator.validateAppName('app123'), returnsNormally);
      expect(() => SandboxValidator.validateAppName('a'), returnsNormally);
    });

    test('rejects empty string', () {
      expect(() => SandboxValidator.validateAppName(''), throwsArgumentError);
    });

    test('rejects uppercase', () {
      expect(
        () => SandboxValidator.validateAppName('MyApp'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateAppName('MYAPP'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateAppName('myApp'),
        throwsArgumentError,
      );
    });

    test('rejects hyphens', () {
      expect(
        () => SandboxValidator.validateAppName('my-app'),
        throwsArgumentError,
      );
    });

    test('rejects spaces', () {
      expect(
        () => SandboxValidator.validateAppName('my app'),
        throwsArgumentError,
      );
      expect(() => SandboxValidator.validateAppName(' '), throwsArgumentError);
    });

    test('rejects path traversal', () {
      expect(() => SandboxValidator.validateAppName('..'), throwsArgumentError);
      expect(
        () => SandboxValidator.validateAppName('../hack'),
        throwsArgumentError,
      );
    });

    test('rejects slashes', () {
      expect(
        () => SandboxValidator.validateAppName('app/sub'),
        throwsArgumentError,
      );
    });

    test('rejects names starting with digit', () {
      expect(
        () => SandboxValidator.validateAppName('123abc'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateAppName('1app'),
        throwsArgumentError,
      );
    });

    test('rejects names starting with underscore', () {
      expect(
        () => SandboxValidator.validateAppName('_app'),
        throwsArgumentError,
      );
    });

    test('rejects special characters', () {
      expect(
        () => SandboxValidator.validateAppName("app'name"),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateAppName('app"name'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateAppName('app@name'),
        throwsArgumentError,
      );
    });
  });

  group('SandboxValidator.validateSubPath', () {
    test('accepts null and empty', () {
      expect(() => SandboxValidator.validateSubPath(null), returnsNormally);
      expect(() => SandboxValidator.validateSubPath(''), returnsNormally);
    });

    test('accepts valid paths', () {
      expect(() => SandboxValidator.validateSubPath('Plans'), returnsNormally);
      expect(
        () => SandboxValidator.validateSubPath('Backups'),
        returnsNormally,
      );
      expect(
        () => SandboxValidator.validateSubPath('deep/nested/path'),
        returnsNormally,
      );
      expect(
        () => SandboxValidator.validateSubPath('Longevity Plans'),
        returnsNormally,
      );
    });

    test('rejects path traversal', () {
      expect(() => SandboxValidator.validateSubPath('..'), throwsArgumentError);
      expect(
        () => SandboxValidator.validateSubPath('../etc'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateSubPath('a/../b'),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.validateSubPath('a/../../root'),
        throwsArgumentError,
      );
    });

    test('rejects absolute paths', () {
      expect(
        () => SandboxValidator.validateSubPath('/absolute'),
        throwsArgumentError,
      );
      expect(() => SandboxValidator.validateSubPath('/'), throwsArgumentError);
    });

    test('rejects empty segments (double slashes)', () {
      expect(
        () => SandboxValidator.validateSubPath('a//b'),
        throwsArgumentError,
      );
    });

    test('rejects dot segments', () {
      expect(() => SandboxValidator.validateSubPath('.'), throwsArgumentError);
      expect(
        () => SandboxValidator.validateSubPath('a/./b'),
        throwsArgumentError,
      );
    });
  });

  group('SandboxValidator.buildSandboxPath', () {
    test('builds path without subPath', () {
      expect(SandboxValidator.buildSandboxPath('my_app', null), '.app/my_app');
      expect(SandboxValidator.buildSandboxPath('my_app', ''), '.app/my_app');
    });

    test('builds path with subPath', () {
      expect(
        SandboxValidator.buildSandboxPath('my_app', 'Plans'),
        '.app/my_app/Plans',
      );
      expect(
        SandboxValidator.buildSandboxPath('my_app', 'deep/nested'),
        '.app/my_app/deep/nested',
      );
    });

    test('validates appName during build', () {
      expect(
        () => SandboxValidator.buildSandboxPath('', null),
        throwsArgumentError,
      );
      expect(
        () => SandboxValidator.buildSandboxPath('BadName', null),
        throwsArgumentError,
      );
    });

    test('validates subPath during build', () {
      expect(
        () => SandboxValidator.buildSandboxPath('app', '../etc'),
        throwsArgumentError,
      );
    });
  });

  group('SandboxValidator.escapeDriveQuery', () {
    test('returns normal strings unchanged', () {
      expect(SandboxValidator.escapeDriveQuery('normal'), 'normal');
      expect(SandboxValidator.escapeDriveQuery('file.json'), 'file.json');
    });

    test('escapes single quotes', () {
      expect(SandboxValidator.escapeDriveQuery("it's"), "it\\'s");
      expect(SandboxValidator.escapeDriveQuery("a'b'c"), "a\\'b\\'c");
    });

    test('handles empty string', () {
      expect(SandboxValidator.escapeDriveQuery(''), '');
    });
  });
}
