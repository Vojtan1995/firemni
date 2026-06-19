import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ucpavky/core/app_release_info.dart';
import 'package:ucpavky/core/app_update_service.dart';

Dio _dioWithResponse(dynamic data, {int statusCode = 200}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: statusCode,
            data: data,
          ),
        );
      },
    ),
  );
  return dio;
}

Dio _dioWithError() {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        );
      },
    ),
  );
  return dio;
}

/// Zachytí query parametr `platform` z odchozího requestu.
Dio _dioCapturingPlatform(List<String?> sink) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        sink.add(options.queryParameters['platform'] as String?);
        handler.resolve(
          Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: {'platform': options.queryParameters['platform'], 'updateAvailable': false},
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  group('currentReleasePlatform', () {
    test('maps android and windows, ignores others', () {
      expect(currentReleasePlatform(platform: TargetPlatform.android), 'android');
      expect(currentReleasePlatform(platform: TargetPlatform.windows), 'windows');
      expect(currentReleasePlatform(platform: TargetPlatform.iOS), isNull);
      expect(currentReleasePlatform(platform: TargetPlatform.macOS), isNull);
    });
  });

  group('fetchAppReleaseInfo platform', () {
    test('defaults to android', () async {
      final sink = <String?>[];
      await fetchAppReleaseInfo(_dioCapturingPlatform(sink));
      expect(sink, ['android']);
    });

    test('passes windows when requested', () async {
      final sink = <String?>[];
      final info =
          await fetchAppReleaseInfo(_dioCapturingPlatform(sink), platform: 'windows');
      expect(sink, ['windows']);
      expect(info?.platform, 'windows');
    });
  });

  group('fetchAppReleaseInfo', () {
    test('parses configured release from backend', () async {
      final dio = _dioWithResponse({
        'platform': 'android',
        'updateAvailable': true,
        'versionName': '1.1.0',
        'latestBuild': 2,
        'minBuild': 1,
        'apkUrl': 'https://releases.example.com/app.apk',
        'releaseNotes': 'Changelog',
      });

      final info = await fetchAppReleaseInfo(dio);
      expect(info, isNotNull);
      expect(info!.updateAvailable, isTrue);
      expect(info.versionName, '1.1.0');
      expect(info.latestBuild, 2);
      expect(info.minBuild, 1);
      expect(info.apkUrl, 'https://releases.example.com/app.apk');
      expect(info.releaseNotes, 'Changelog');
    });

    test('returns null when backend is unavailable', () async {
      final info = await fetchAppReleaseInfo(_dioWithError());
      expect(info, isNull);
    });

    test('parses updateAvailable false without prompting client', () async {
      final dio = _dioWithResponse({
        'platform': 'android',
        'updateAvailable': false,
      });

      final info = await fetchAppReleaseInfo(dio);
      expect(info, isNotNull);
      expect(info!.updateAvailable, isFalse);
      expect(
        shouldShowAppUpdate(currentBuild: 1, release: info),
        isFalse,
      );
    });
  });

  group('version comparison scenarios', () {
    const configured = AppReleaseInfo(
      platform: 'android',
      updateAvailable: true,
      versionName: '1.1.0',
      latestBuild: 5,
      minBuild: 4,
      apkUrl: 'https://releases.example.com/app.apk',
    );

    test('no prompt when already on latest build', () {
      expect(
          shouldShowAppUpdate(currentBuild: 5, release: configured), isFalse);
    });

    test('optional prompt when below latest but above min', () {
      expect(shouldShowAppUpdate(currentBuild: 4, release: configured), isTrue);
      expect(
        isAppUpdateForced(currentBuild: 4, release: configured),
        isFalse,
      );
    });

    test('forced prompt when below minBuild', () {
      expect(shouldShowAppUpdate(currentBuild: 3, release: configured), isTrue);
      expect(
        isAppUpdateForced(currentBuild: 3, release: configured),
        isTrue,
      );
    });
  });

  group('checkAppUpdateManually', () {
    test('returns upToDate when backend has no newer build', () async {
      final result = await checkAppUpdateManually(
        _dioWithResponse({
          'platform': 'android',
          'updateAvailable': true,
          'latestBuild': 2,
          'minBuild': 1,
          'apkUrl': 'https://releases.example.com/app.apk',
        }),
        supported: true,
        buildReader: () async => 2,
      );

      expect(result.status, ManualAppUpdateStatus.upToDate);
    });

    test('returns update details when a newer build exists', () async {
      final result = await checkAppUpdateManually(
        _dioWithResponse({
          'platform': 'android',
          'updateAvailable': true,
          'latestBuild': 2,
          'minBuild': 2,
          'apkUrl': 'https://releases.example.com/app.apk',
        }),
        supported: true,
        buildReader: () async => 1,
      );

      expect(result.status, ManualAppUpdateStatus.updateAvailable);
      expect(result.update, isNotNull);
      expect(result.update!.forced, isTrue);
    });

    test('returns unavailable when backend cannot be reached', () async {
      final result = await checkAppUpdateManually(
        _dioWithError(),
        supported: true,
        buildReader: () async => 1,
      );

      expect(result.status, ManualAppUpdateStatus.unavailable);
    });
  });
}
