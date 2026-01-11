import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class FixtureTestBundle extends CachingAssetBundle {
  FixtureTestBundle({
    String? assetRoot,
  }) : _assetRoot = assetRoot ?? p.join(Directory.current.path, 'assets') {
    _assetFiles = _discoverFixtures();
    _manifestJson = _buildManifest();
    _manifestBinary = _buildManifestBinary();
  }

  final String _assetRoot;
  late final Map<String, String> _assetFiles;
  late final String _manifestJson;
  late final ByteData _manifestBinary;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.json') {
      return _stringToBytes(_manifestJson);
    }
    if (key == 'AssetManifest.bin') {
      return _manifestBinary;
    }
    if (key == 'AssetManifest.bin.json') {
      final encoded = jsonEncode(base64.encode(_manifestBinary.buffer.asUint8List()));
      return _stringToBytes(encoded);
    }

    final path = _assetFiles[key];
    if (path == null) {
      throw Exception('Missing asset: $key');
    }
    final bytes = await File(path).readAsBytes();
    return ByteData.view(Uint8List.fromList(bytes).buffer);
  }

  Map<String, String> _discoverFixtures() {
    final fixtureDir = Directory(p.join(_assetRoot, 'eml_fixtures'));
    if (!fixtureDir.existsSync()) {
      return {};
    }
    final files = fixtureDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.eml'));
    final assets = <String, String>{};
    for (final file in files) {
      final name = p.basename(file.path);
      final assetPath = 'assets/eml_fixtures/$name';
      assets[assetPath] = file.path;
    }
    return assets;
  }

  String _buildManifest() {
    final manifest = <String, List<String>>{};
    for (final assetPath in _assetFiles.keys) {
      manifest[assetPath] = [assetPath];
    }
    return jsonEncode(manifest);
  }

  ByteData _stringToBytes(String value) {
    final bytes = Uint8List.fromList(utf8.encode(value));
    return ByteData.view(bytes.buffer);
  }

  ByteData _buildManifestBinary() {
    final manifest = <String, List<Map<String, Object?>>>{};
    for (final assetPath in _assetFiles.keys) {
      manifest[assetPath] = [
        <String, Object?>{'asset': assetPath, 'dpr': null},
      ];
    }
    return const StandardMessageCodec().encodeMessage(manifest)!;
  }
}
