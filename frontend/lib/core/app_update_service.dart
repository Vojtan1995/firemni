import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_release_info.dart';

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.release,
    required this.currentBuild,
    required this.forced,
  });

  final AppReleaseInfo release;
  final int currentBuild;
  final bool forced;
}

enum ManualAppUpdateStatus {
  updateAvailable,
  upToDate,
  unavailable,
  unsupported,
}

class ManualAppUpdateCheckResult {
  const ManualAppUpdateCheckResult({
    required this.status,
    this.update,
  });

  final ManualAppUpdateStatus status;
  final AppUpdateCheckResult? update;
}

/// Načte informace o release z backendu.
Future<AppReleaseInfo?> fetchAppReleaseInfo(Dio dio) async {
  try {
    final res = await dio.get(
      '/api/app/release',
      queryParameters: {'platform': 'android'},
    );
    return AppReleaseInfo.fromJson(
      (res.data as Map).cast<String, dynamic>(),
    );
  } catch (_) {
    return null;
  }
}

Future<int?> readCurrentAppBuild() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber);
  } catch (_) {
    return null;
  }
}

Future<bool> openApkDownloadUrl(String url) async {
  if (!isApkDownloadUrlValid(url)) return false;
  final uri = Uri.parse(url.trim());
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Vyhodnotí, zda zobrazit dialog aktualizace (jen Android release).
Future<AppUpdateCheckResult?> evaluateAppUpdate(Dio dio) async {
  if (kDebugMode || defaultTargetPlatform != TargetPlatform.android) {
    return null;
  }

  final currentBuild = await readCurrentAppBuild();
  if (currentBuild == null) return null;

  final release = await fetchAppReleaseInfo(dio);
  if (release == null) return null;
  if (!shouldShowAppUpdate(currentBuild: currentBuild, release: release)) {
    return null;
  }

  return AppUpdateCheckResult(
    release: release,
    currentBuild: currentBuild,
    forced: isAppUpdateForced(currentBuild: currentBuild, release: release),
  );
}

Future<ManualAppUpdateCheckResult> checkAppUpdateManually(
  Dio dio, {
  bool? supported,
  Future<int?> Function()? buildReader,
}) async {
  final isSupported = supported ??
      (!kDebugMode && defaultTargetPlatform == TargetPlatform.android);
  if (!isSupported) {
    return const ManualAppUpdateCheckResult(
      status: ManualAppUpdateStatus.unsupported,
    );
  }

  final currentBuild = await (buildReader ?? readCurrentAppBuild)();
  if (currentBuild == null) {
    return const ManualAppUpdateCheckResult(
      status: ManualAppUpdateStatus.unavailable,
    );
  }

  final release = await fetchAppReleaseInfo(dio);
  if (release == null) {
    return const ManualAppUpdateCheckResult(
      status: ManualAppUpdateStatus.unavailable,
    );
  }
  if (!shouldShowAppUpdate(currentBuild: currentBuild, release: release)) {
    return const ManualAppUpdateCheckResult(
      status: ManualAppUpdateStatus.upToDate,
    );
  }

  return ManualAppUpdateCheckResult(
    status: ManualAppUpdateStatus.updateAvailable,
    update: AppUpdateCheckResult(
      release: release,
      currentBuild: currentBuild,
      forced: isAppUpdateForced(currentBuild: currentBuild, release: release),
    ),
  );
}
