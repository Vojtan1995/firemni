class SealValidationIssue {
  const SealValidationIssue(this.field, this.message);
  final String field;
  final String message;
}

List<SealValidationIssue> validateSealForChecked(Map<String, dynamic> seal) {
  final issues = <SealValidationIssue>[];

  String? text(String key) {
    final v = seal[key];
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  if (text('system') == null) {
    issues.add(const SealValidationIssue('system', 'Chybí systém'));
  }
  if (text('construction') == null) {
    issues.add(const SealValidationIssue('construction', 'Chybí konstrukce'));
  }
  if (text('location') == null) {
    issues.add(const SealValidationIssue('location', 'Chybí umístění'));
  }
  if (text('fireRating') == null) {
    issues.add(const SealValidationIssue('fireRating', 'Chybí požární odolnost'));
  }

  final photos = seal['photos'] as List? ?? [];
  if (photos.isEmpty) {
    issues.add(const SealValidationIssue('photos', 'Chybí alespoň jedna fotka'));
  }

  final entries = seal['entries'] as List? ?? [];
  if (entries.isEmpty) {
    issues.add(const SealValidationIssue('entries', 'Chybí alespoň jeden prostup'));
    return issues;
  }

  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i] as Map<String, dynamic>;
    final label = 'Prostup ${i + 1}';
    if ((entry['entryType']?.toString().trim().isEmpty ?? true)) {
      issues.add(SealValidationIssue('entries.$i.entryType', '$label: chybí typ prostupu'));
    }
    if ((entry['dimension']?.toString().trim().isEmpty ?? true)) {
      issues.add(SealValidationIssue('entries.$i.dimension', '$label: chybí rozměr'));
    }
    final qty = num.tryParse(entry['quantity']?.toString() ?? '');
    if (qty == null || qty <= 0) {
      issues.add(SealValidationIssue('entries.$i.quantity', '$label: chybí počet kusů'));
    }
    final materials = entry['materials'] as List? ?? [];
    final hasMaterial = materials.any((m) {
      if (m is Map) {
        final name = m['material'] ?? m['name'];
        return name != null && name.toString().trim().isNotEmpty;
      }
      return m != null && m.toString().trim().isNotEmpty;
    });
    if (!hasMaterial) {
      issues.add(SealValidationIssue('entries.$i.materials', '$label: chybí materiál'));
    }
  }

  return issues;
}

String formatSealValidationIssues(List<SealValidationIssue> issues) =>
    issues.map((i) => i.message).join('\n');
