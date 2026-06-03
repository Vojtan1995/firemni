import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Whether [FilePicker.platform.saveFile] must receive [bytes] (mobile + web).
bool saveFileRequiresBytes() {
  if (kIsWeb) return true;
  return Platform.isAndroid || Platform.isIOS;
}

/// Normalizes Dio `ResponseType.bytes` payload to a non-empty [Uint8List].
Uint8List normalizeExportBytes(Object? data, {required String exportLabel}) {
  if (data == null) {
    throw StateError('$exportLabel export vrátil prázdná data (null)');
  }
  final Uint8List bytes;
  if (data is Uint8List) {
    bytes = data;
  } else if (data is List<int>) {
    bytes = Uint8List.fromList(data);
  } else {
    throw StateError(
      '$exportLabel export vrátil neplatný typ dat: ${data.runtimeType}',
    );
  }
  if (bytes.isEmpty) {
    throw StateError('$exportLabel export vrátil prázdný soubor');
  }
  return bytes;
}

void logExport(String message) {
  debugPrint('[Export] $message');
}

/// Saves exported bytes via system save dialog.
///
/// On Android/iOS (and web) [bytes] must be passed into [FilePicker.saveFile].
/// On desktop the dialog returns a path and bytes are written separately.
Future<String> saveExportFile({
  required Uint8List bytes,
  required String fileName,
  required String extension,
  required String exportLabel,
}) async {
  logExport('Save file started ($exportLabel)');

  final needsBytes = saveFileRequiresBytes();
  final savedPath = await FilePicker.platform.saveFile(
    dialogTitle: 'Uložit $exportLabel',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: [extension],
    bytes: needsBytes ? bytes : null,
  );

  if (savedPath == null) {
    throw ExportSaveCancelled();
  }

  var filePath = savedPath;
  if (!filePath.toLowerCase().endsWith('.$extension')) {
    filePath = '$filePath.$extension';
  }

  if (!needsBytes) {
    await File(filePath).writeAsBytes(bytes, flush: true);
  }

  logExport('Save file success: $filePath');
  return filePath;
}

class ExportSaveCancelled implements Exception {}
