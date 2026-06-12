import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/core/app_release_info.dart';

void main() {
  const release = AppReleaseInfo(
    platform: 'android',
    updateAvailable: true,
    versionName: '1.1.0',
    latestBuild: 3,
    minBuild: 2,
    apkUrl: 'https://example.com/app.apk',
  );

  group('isForcedAppUpdate', () {
    test('true when current below minBuild', () {
      expect(
        isForcedAppUpdate(currentBuild: 1, release: release),
        isTrue,
      );
    });

    test('false when current at or above minBuild', () {
      expect(
        isForcedAppUpdate(currentBuild: 2, release: release),
        isFalse,
      );
    });
  });

  group('isOptionalAppUpdate', () {
    test('true when below latest but not forced', () {
      expect(
        isOptionalAppUpdate(currentBuild: 2, release: release),
        isTrue,
      );
    });

    test('false when already on latest', () {
      expect(
        isOptionalAppUpdate(currentBuild: 3, release: release),
        isFalse,
      );
    });

    test('false when update not available', () {
      const noUpdate = AppReleaseInfo(
        platform: 'android',
        updateAvailable: false,
      );
      expect(
        isOptionalAppUpdate(currentBuild: 1, release: noUpdate),
        isFalse,
      );
    });
  });

  group('shouldShowAppUpdate', () {
    test('true for forced or optional', () {
      expect(shouldShowAppUpdate(currentBuild: 1, release: release), isTrue);
      expect(shouldShowAppUpdate(currentBuild: 2, release: release), isTrue);
      expect(shouldShowAppUpdate(currentBuild: 3, release: release), isFalse);
    });
  });

  group('isApkDownloadUrlValid', () {
    test('accepts https URL', () {
      expect(isApkDownloadUrlValid('https://releases.example.com/app.apk'), isTrue);
    });

    test('rejects empty, http and malformed URLs', () {
      expect(isApkDownloadUrlValid(null), isFalse);
      expect(isApkDownloadUrlValid(''), isFalse);
      expect(isApkDownloadUrlValid('http://example.com/app.apk'), isFalse);
      expect(isApkDownloadUrlValid('not-a-url'), isFalse);
    });
  });
}
