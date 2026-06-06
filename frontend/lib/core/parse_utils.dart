/// Parses API values that may arrive as [num] or decimal strings from Prisma JSON.
double parseNum(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// Nullable variant — returns null when value is absent or unparseable.
double? parseNumOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
