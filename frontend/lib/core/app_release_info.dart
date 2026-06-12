/// Informace o dostupné verzi klienta z backendu.
class AppReleaseInfo {
  const AppReleaseInfo({
    required this.platform,
    required this.updateAvailable,
    this.versionName,
    this.latestBuild,
    this.minBuild,
    this.apkUrl,
    this.releaseNotes,
  });

  final String platform;
  final bool updateAvailable;
  final String? versionName;
  final int? latestBuild;
  final int? minBuild;
  final String? apkUrl;
  final String? releaseNotes;

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    return AppReleaseInfo(
      platform: json['platform'] as String? ?? 'android',
      updateAvailable: json['updateAvailable'] as bool? ?? false,
      versionName: json['versionName'] as String?,
      latestBuild: json['latestBuild'] as int?,
      minBuild: json['minBuild'] as int?,
      apkUrl: json['apkUrl'] as String?,
      releaseNotes: json['releaseNotes'] as String?,
    );
  }
}

/// Aktuální build je pod minimem — vynucená aktualizace.
bool isForcedAppUpdate({
  required int currentBuild,
  required AppReleaseInfo release,
}) {
  if (!release.updateAvailable) return false;
  final minBuild = release.minBuild ?? 0;
  return currentBuild < minBuild;
}

/// Novější build je k dispozici, ale není vynucený.
bool isOptionalAppUpdate({
  required int currentBuild,
  required AppReleaseInfo release,
}) {
  if (!release.updateAvailable) return false;
  final latest = release.latestBuild ?? 0;
  if (currentBuild >= latest) return false;
  return !isForcedAppUpdate(currentBuild: currentBuild, release: release);
}

/// Má se zobrazit dialog aktualizace (volitelná nebo vynucená).
bool shouldShowAppUpdate({
  required int currentBuild,
  required AppReleaseInfo release,
}) {
  return isForcedAppUpdate(currentBuild: currentBuild, release: release) ||
      isOptionalAppUpdate(currentBuild: currentBuild, release: release);
}

bool isAppUpdateForced({
  required int currentBuild,
  required AppReleaseInfo release,
}) {
  return isForcedAppUpdate(currentBuild: currentBuild, release: release);
}

/// HTTPS odkaz na APK — release build nepovoluje cleartext.
bool isApkDownloadUrlValid(String? url) {
  if (url == null || url.trim().isEmpty) return false;
  final uri = Uri.tryParse(url.trim());
  return uri != null &&
      uri.hasScheme &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty;
}
