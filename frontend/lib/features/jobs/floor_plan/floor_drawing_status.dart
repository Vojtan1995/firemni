/// Stav stažení výkresu patra v lokální cache.
enum FloorDrawingDownloadStatus {
  missing,
  downloading,
  downloaded,
  error,
}

extension FloorDrawingDownloadStatusX on FloorDrawingDownloadStatus {
  String get label => switch (this) {
        FloorDrawingDownloadStatus.missing => 'Chybí',
        FloorDrawingDownloadStatus.downloading => 'Stahuje se',
        FloorDrawingDownloadStatus.downloaded => 'Staženo',
        FloorDrawingDownloadStatus.error => 'Chyba stažení',
      };

  static FloorDrawingDownloadStatus fromDb(String? value) {
    switch (value) {
      case 'downloaded':
        return FloorDrawingDownloadStatus.downloaded;
      case 'downloading':
        return FloorDrawingDownloadStatus.downloading;
      case 'error':
        return FloorDrawingDownloadStatus.error;
      case 'missing':
      default:
        return FloorDrawingDownloadStatus.missing;
    }
  }

  String toDb() => name;
}
