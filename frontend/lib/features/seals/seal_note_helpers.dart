import 'dart:convert';

/// Role-based seal note payload and visibility helpers.
class SealNoteHelpers {
  static String? normalizeNote(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  /// Fields to persist in local_seals columns when saving.
  static ({String? note, String? internalNote}) localColumnsForRole({
    required String? role,
    required String? noteText,
    required String? internalNoteText,
    String? existingNote,
    String? existingInternalNote,
  }) {
    final note = normalizeNote(noteText);
    final internal = normalizeNote(internalNoteText);
    if (role == 'worker') {
      return (note: existingNote, internalNote: internal);
    }
    if (role == 'ucetni') {
      return (note: note, internalNote: existingInternalNote);
    }
    if (role == 'vedeni' || role == 'admin') {
      return (note: note, internalNote: internal);
    }
    return (note: existingNote, internalNote: existingInternalNote);
  }

  /// Merge note fields into outbox/sync payload by role.
  static void applyNotesToPayload(
    Map<String, dynamic> payload, {
    required String? role,
    required String? noteText,
    required String? internalNoteText,
    bool isUpdate = false,
  }) {
    final note = normalizeNote(noteText);
    final internal = normalizeNote(internalNoteText);

    if (role == 'worker') {
      payload.remove('note');
      payload['internalNote'] = internal;
      return;
    }

    if (role == 'ucetni') {
      payload.remove('internalNote');
      payload['note'] = note;
      return;
    }

    if (role == 'vedeni' || role == 'admin') {
      payload['note'] = note;
      payload['internalNote'] = internal;
    }
  }

  static bool canEditPublicNote(String? role) =>
      role == 'vedeni' || role == 'admin' || role == 'ucetni';

  static bool canEditInternalNote(String? role) =>
      role == 'worker' || role == 'vedeni' || role == 'admin';

  static bool canViewPublicNote(String? role) => role != 'worker';

  static bool canViewInternalNote(String? role) =>
      role == 'vedeni' || role == 'admin' || role == 'ucetni';

  static bool showInternalNoteInDetail(String? role) =>
      role == 'worker' || canViewInternalNote(role);

  static bool showPublicNoteInDetail(String? role) => canViewPublicNote(role);
}

/// Patch note fields inside jsonPayload after pull sync.
String? patchSealJsonPayloadNotes({
  required String? jsonPayload,
  required String? note,
  required String? internalNote,
}) {
  if (jsonPayload == null || jsonPayload.isEmpty) return jsonPayload;
  try {
    final map = Map<String, dynamic>.from(
      (jsonDecode(jsonPayload) as Map).cast<String, dynamic>(),
    );
    map['note'] = note;
    map['internalNote'] = internalNote;
    return jsonEncode(map);
  } catch (_) {
    return jsonPayload;
  }
}
