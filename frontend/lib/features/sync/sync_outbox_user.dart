import '../../database/database.dart';

/// Outbox row belongs to the logged-in user (T6). Legacy rows with null [userId] are excluded.
bool outboxBelongsToUser(LocalOutboxData row, String? userId) {
  if (userId == null || userId.isEmpty) return false;
  return row.userId == userId;
}

List<LocalOutboxData> filterOutboxForUser(
  List<LocalOutboxData> rows,
  String? userId,
) {
  return rows.where((r) => outboxBelongsToUser(r, userId)).toList();
}
