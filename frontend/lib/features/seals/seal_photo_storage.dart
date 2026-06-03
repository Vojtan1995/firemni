import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const sealPhotosSubdir = 'seal_photos';

/// Persistent directory for seal photo files under app documents.
Future<Directory> sealPhotosDirectory({String? basePath}) async {
  final root = basePath ?? (await getApplicationDocumentsDirectory()).path;
  final dir = Directory(p.join(root, sealPhotosSubdir));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// Copies [sourcePath] into persistent storage; returns absolute destination path.
Future<String> persistLocalSealPhoto(
  String sourcePath, {
  String? basePath,
  String? fileName,
}) async {
  final dir = await sealPhotosDirectory(basePath: basePath);
  final name = fileName ?? '${const Uuid().v4()}.webp';
  final dest = p.join(dir.path, name);
  await File(sourcePath).copy(dest);
  return dest;
}

/// Compress picked image to WebP and persist under app documents.
Future<String?> compressAndPersistSealPhoto(String imagePath,
    {String? basePath}) async {
  final tempDir = await getTemporaryDirectory();
  final tempOut = p.join(tempDir.path, '${const Uuid().v4()}.webp');
  final compressed = await FlutterImageCompress.compressAndGetFile(
    imagePath,
    tempOut,
    quality: 85,
    format: CompressFormat.webp,
  );
  if (compressed == null) return null;
  return persistLocalSealPhoto(compressed.path, basePath: basePath);
}
