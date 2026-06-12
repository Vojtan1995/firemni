import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const floorDrawingsSubdir = 'floor_drawings';

String floorDrawingExtensionForMime(String mimeType) {
  final mime = mimeType.toLowerCase();
  if (mime.contains('pdf')) return 'pdf';
  if (mime.contains('png')) return 'png';
  if (mime.contains('jpeg') || mime.contains('jpg')) return 'jpg';
  if (mime.contains('webp')) return 'webp';
  return 'bin';
}

Future<Directory> floorDrawingsDirectory({String? basePath}) async {
  final root = basePath ?? (await getApplicationDocumentsDirectory()).path;
  final dir = Directory(p.join(root, floorDrawingsSubdir));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<String> persistFloorDrawingBytes(
  String floorId,
  Uint8List bytes, {
  String? basePath,
  String extension = 'webp',
}) async {
  final dir = await floorDrawingsDirectory(basePath: basePath);
  final dest = p.join(dir.path, '$floorId.$extension');
  await File(dest).writeAsBytes(bytes, flush: true);
  return dest;
}
