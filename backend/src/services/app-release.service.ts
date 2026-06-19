/** Env názvy pro jednu platformu. Android drží zpětně kompatibilní názvy
 *  (`APP_RELEASE_*`), Windows má vlastní prefix (`APP_RELEASE_WIN_*`). */
interface ReleaseEnvKeys {
  build: string;
  minBuild: string;
  url: string;
  versionName: string;
  notes: string;
}

const RELEASE_ENV: Record<'android' | 'windows', ReleaseEnvKeys> = {
  android: {
    build: 'APP_RELEASE_BUILD',
    minBuild: 'APP_RELEASE_MIN_BUILD',
    url: 'APP_RELEASE_APK_URL',
    versionName: 'APP_RELEASE_VERSION_NAME',
    notes: 'APP_RELEASE_NOTES',
  },
  windows: {
    build: 'APP_RELEASE_WIN_BUILD',
    minBuild: 'APP_RELEASE_WIN_MIN_BUILD',
    url: 'APP_RELEASE_WIN_URL',
    versionName: 'APP_RELEASE_WIN_VERSION_NAME',
    notes: 'APP_RELEASE_WIN_NOTES',
  },
};

function buildReleasePayload(platform: 'android' | 'windows', keys: ReleaseEnvKeys) {
  const latestBuild = parseInt(process.env[keys.build] || '', 10);
  const apkUrl = (process.env[keys.url] || '').trim();
  if (!Number.isFinite(latestBuild) || latestBuild <= 0 || !apkUrl) {
    return { platform, updateAvailable: false as const };
  }

  const minBuild = parseInt(process.env[keys.minBuild] || '0', 10) || 0;
  const versionName =
    (process.env[keys.versionName] || '').trim() || String(latestBuild);

  return {
    platform,
    updateAvailable: true as const,
    versionName,
    latestBuild,
    minBuild,
    apkUrl,
    releaseNotes: process.env[keys.notes] || '',
  };
}

/** Čte env při každém požadavku — testy mohou měnit process.env bez restartu modulu. */
export function getAppReleasePayload(platform: string) {
  if (platform !== 'android' && platform !== 'windows') {
    return { error: 'unsupported_platform' as const };
  }
  return buildReleasePayload(platform, RELEASE_ENV[platform]);
}
