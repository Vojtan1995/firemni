/** Čte env při každém požadavku — testy mohou měnit process.env bez restartu modulu. */
export function getAppReleasePayload(platform: string) {
  if (platform !== 'android') {
    return { error: 'unsupported_platform' as const };
  }

  const latestBuild = parseInt(process.env.APP_RELEASE_BUILD || '', 10);
  const apkUrl = (process.env.APP_RELEASE_APK_URL || '').trim();
  if (!Number.isFinite(latestBuild) || latestBuild <= 0 || !apkUrl) {
    return {
      platform: 'android' as const,
      updateAvailable: false as const,
    };
  }

  const minBuild = parseInt(process.env.APP_RELEASE_MIN_BUILD || '0', 10) || 0;
  const versionName =
    (process.env.APP_RELEASE_VERSION_NAME || '').trim() || String(latestBuild);

  return {
    platform: 'android' as const,
    updateAvailable: true as const,
    versionName,
    latestBuild,
    minBuild,
    apkUrl,
    releaseNotes: process.env.APP_RELEASE_NOTES || '',
  };
}
