/// v1.0.1 regression pins (device findings, 2026-11-13):
///
///  Content inspection silently never fired in v1.0.0: the code and
///  the attribution notice were bundled, but the NSFW model file
///  itself was never in the app. The detector's load fails inside a
///  runCatching, so the feature just never fires — no crash, no
///  error. This test pins the model asset so a release can never
///  ship without it again.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v1.0.1 — content model bundled', () {
    test('nsfw_model.tflite is bundled and matches the GantMan 1.2.0 release', () {
      final model = File(
        'android/app/src/main/assets/models/nsfw_model.tflite',
      );
      expect(
        model.existsSync(),
        isTrue,
        reason: 'v1.0.0 shipped the notice but no model, so content '
            'inspection silently never fired',
      );
      // GantMan nsfw_model 1.2.0, mobilenet_v2_140_224/saved_model.tflite.
      expect(model.lengthSync(), 17355548);
      expect(
        File(
          'android/app/src/main/assets/models/NSFW_MODEL_NOTICE.txt',
        ).existsSync(),
        isTrue,
      );
    });
  });
}
