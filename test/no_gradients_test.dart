// v1.0.5 flat-colour rule (user directive): no colour gradients
// anywhere in the app — every surface is a single flat colour from
// the red/black/white palette. This source scan pins the rule the
// same way the palette guard pins the colours: the gradient widget
// APIs and the retired gradient helpers must not reappear in lib/.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No gradient APIs or retired gradient helpers anywhere in lib/', () {
    const banned = <String>[
      'LinearGradient',
      'RadialGradient',
      'SweepGradient',
      'GradientCard',
      'heroGradient',
      // v1.0.5 audit B-hunt-4 strengthening: the bare token also covers
      // dart:ui's Gradient.linear/radial/sweep factories and any custom
      // Gradient subclass, which the class names above would miss; the
      // shader tokens cover Paint.shader-based gradients. (No file in
      // lib/ — comments included — currently contains any of these.)
      'Gradient',
      'createShader',
      '.shader',
    ];
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final content = entity.readAsStringSync();
      for (final token in banned) {
        if (content.contains(token)) {
          offenders.add('${entity.path} references $token');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Gradients are banned (v1.0.5 flat-colour rule):\n'
          '${offenders.join('\n')}',
    );
  });
}
