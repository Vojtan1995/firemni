class BackupStatusSummary {
  const BackupStatusSummary({
    required this.ok,
    required this.checkedAt,
    required this.checks,
  });

  final bool ok;
  final DateTime? checkedAt;
  final List<BackupHealthCheck> checks;

  factory BackupStatusSummary.fromJson(Map<String, dynamic> json) {
    return BackupStatusSummary(
      ok: json['ok'] == true,
      checkedAt: _parseDate(json['checkedAt']),
      checks: ((json['checks'] as List?) ?? const [])
          .whereType<Map>()
          .map((row) => BackupHealthCheck.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }
}

class BackupHealthCheck {
  const BackupHealthCheck({
    required this.type,
    required this.label,
    required this.ok,
    required this.status,
    required this.maxAgeHours,
    this.latestSuccessAgeHours,
    this.latestRunAt,
    this.latestSuccessAt,
    this.githubRunUrl,
    this.r2Prefix,
    this.manifestKey,
    this.bytes,
    this.objectCount,
    this.errorMessage,
    this.message,
  });

  final String type;
  final String label;
  final bool ok;
  final String status;
  final int maxAgeHours;
  final double? latestSuccessAgeHours;
  final DateTime? latestRunAt;
  final DateTime? latestSuccessAt;
  final String? githubRunUrl;
  final String? r2Prefix;
  final String? manifestKey;
  final String? bytes;
  final int? objectCount;
  final String? errorMessage;
  final String? message;

  factory BackupHealthCheck.fromJson(Map<String, dynamic> json) {
    final latestRun = _mapOrNull(json['latestRun']);
    final latestSuccess = _mapOrNull(json['latestSuccess']);
    return BackupHealthCheck(
      type: json['type'] as String? ?? '',
      label: json['label'] as String? ?? 'Zaloha',
      ok: json['ok'] == true,
      status: json['status'] as String? ?? 'missing',
      maxAgeHours: _intOrZero(json['maxAgeHours']),
      latestSuccessAgeHours: _doubleOrNull(json['latestSuccessAgeHours']),
      latestRunAt: _parseDate(latestRun?['finishedAt']) ?? _parseDate(latestRun?['createdAt']),
      latestSuccessAt:
          _parseDate(latestSuccess?['finishedAt']) ?? _parseDate(latestSuccess?['createdAt']),
      githubRunUrl: json['githubRunUrl'] as String?,
      r2Prefix: json['r2Prefix'] as String?,
      manifestKey: json['manifestKey'] as String?,
      bytes: json['bytes']?.toString(),
      objectCount: _intOrNull(json['objectCount']),
      errorMessage: json['errorMessage'] as String?,
      message: json['message'] as String?,
    );
  }

  String get title {
    switch (type) {
      case 'db':
        return 'DB záloha';
      case 'object':
        return 'Fotky/výkresy';
      case 'restore_test':
        return 'Restore test';
      default:
        return label;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'ok':
        return 'OK';
      case 'failed':
        return 'Selhalo';
      case 'stale':
        return 'Zastaralé';
      case 'missing':
      default:
        return 'Chybí';
    }
  }

  String get ageLabel {
    final hours = latestSuccessAgeHours;
    if (hours == null) return 'bez úspěšného běhu';
    if (hours < 1) return '<1 h';
    if (hours < 48) return '${hours.round()} h';
    return '${(hours / 24).round()} d';
  }

  String get sizeLabel {
    final raw = bytes;
    if (raw == null) return '';
    final value = int.tryParse(raw);
    if (value == null) return raw;
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

Map<String, dynamic>? _mapOrNull(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

DateTime? _parseDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toLocal();
}

int _intOrZero(Object? value) => _intOrNull(value) ?? 0;

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _doubleOrNull(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
