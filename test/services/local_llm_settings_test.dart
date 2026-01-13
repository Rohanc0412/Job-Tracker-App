import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:job_tracker/services/local_llm_settings.dart';
import 'package:job_tracker/services/settings_store.dart';

void main() {
  test('model selection persists in settings store', () async {
    final tempDir = await Directory.systemTemp.createTemp('settings');
    final settingsFile = File('${tempDir.path}/settings.json');
    final store = SettingsStore.forTesting(
      fileResolver: () async => settingsFile,
    );
    await store.load();
    await store.set(LocalLlmSettingsKeys.modelId, 'qwen2.5:7b-instruct');

    final reloaded = SettingsStore.forTesting(
      fileResolver: () async => settingsFile,
    );
    await reloaded.load();
    expect(
      reloaded.get<String>(LocalLlmSettingsKeys.modelId),
      'qwen2.5:7b-instruct',
    );

    await tempDir.delete(recursive: true);
  });
}
