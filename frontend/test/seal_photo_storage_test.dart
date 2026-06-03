import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ucpavky/features/seals/seal_photo_storage.dart';

void main() {
  test('persistLocalSealPhoto copies file into seal_photos directory',
      () async {
    final base = Directory.systemTemp.createTempSync('photo_storage_test_');
    addTearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });

    final source = File(p.join(base.path, 'source.webp'));
    await source.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

    final dest = await persistLocalSealPhoto(source.path, basePath: base.path);

    expect(dest, contains(sealPhotosSubdir));
    expect(File(dest).existsSync(), isTrue);
    expect(await File(dest).length(), greaterThan(0));
    expect(dest, isNot(source.path));
  });

  test('sealPhotosDirectory creates subdirectory under base', () async {
    final base = Directory.systemTemp.createTempSync('photo_dir_test_');
    addTearDown(() {
      if (base.existsSync()) base.deleteSync(recursive: true);
    });

    final dir = await sealPhotosDirectory(basePath: base.path);
    expect(dir.path, p.join(base.path, sealPhotosSubdir));
    expect(dir.existsSync(), isTrue);
  });
}
