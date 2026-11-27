// User rule 2026-11-22: activation NEVER asks for the recovery
// code; only deactivation (loosening) does. These source pins keep
// the old v1.0.4 "activations are code-gated" behaviour from
// creeping back in.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String src(String path) => File(path).readAsStringSync();

void main() {
  group('activation is free, deactivation is gated (2026-11-22)', () {
    test('apps_tab: no "|| activates" gate remains', () {
      final s = src('lib/ui/apps_tab.dart');
      expect(s.contains('|| activates'), isFalse);
      expect(s.contains('final activates'), isFalse);
    });

    test('apps_tab: _toggleProtection gates only the OFF direction', () {
      final s = src('lib/ui/apps_tab.dart');
      final start = s.indexOf('Future<void> _toggleProtection');
      final body = s.substring(start, start + 1400);
      expect(body.contains('if (newValue)'), isTrue);
      expect(body.contains('await doApply();'), isTrue);
      expect(
        body.contains('await runLoosening(context, widget.controller, doApply);'),
        isTrue,
      );
    });

    test('config_screens: blocklist save gates only on loosening', () {
      final s = src('lib/ui/config_screens.dart');
      final start = s.indexOf('Future<void> _saveLists');
      final body = s.substring(start, start + 1600);
      expect(body.contains('if (loosens)'), isTrue);
      expect(body.contains('EVERY save is recovery-gated'), isFalse);
    });

    test('config_screens: pushing blocklists to browsers is free', () {
      final s = src('lib/ui/config_screens.dart');
      final start = s.indexOf('Future<void> _applyToBrowsers');
      final body = s.substring(start, start + 700);
      expect(body.contains('runLoosening'), isFalse);
    });

    test('impulse pickers: adding targets is not a loosening', () {
      final s = src('lib/ui/impulse_focus_screens.dart');
      expect(s.contains('result.any((e) => !config.'), isFalse);
    });

    test('restrictions_tab: gate only when clearing', () {
      final s = src('lib/ui/restrictions_tab.dart');
      expect(s.contains('if (toClear.isNotEmpty &&'), isTrue);
      expect(s.contains('toApply.isNotEmpty || toClear.isNotEmpty'), isFalse);
    });

    test('entry password: first set free, change gated', () {
      final s = src('lib/ui/entry_password_ui.dart');
      final start = s.indexOf('Future<void> _setOrChange');
      final body = s.substring(start, start + 900);
      expect(body.contains('if (_isSet == true)'), isTrue);
    });

    test('lockdown windows: only deactivation/deletion of enabled gated', () {
      final s = src('lib/ui/lockdown_screen.dart');
      final start = s.indexOf('bool _lockdownsChangeNeedsCode');
      final body = s.substring(start, start + 900);
      // Adding and enabling are free; deleting a disabled window too.
      expect(body.contains('return true; // added'), isFalse);
      expect(body.contains('return true; // enabled'), isFalse);
      expect(body.contains('if (old.enabled) return true'), isTrue);
      expect(body.contains('old.enabled && !next.enabled'), isTrue);
    });

    test('focus schedules: only deactivation/deletion of enforcing gated', () {
      final s = src('lib/ui/impulse_focus_screens.dart');
      final start = s.indexOf('bool _schedulesChangeNeedsCode');
      final body = s.substring(start, start + 1100);
      // Adding an enforcing schedule is free now.
      expect(body.contains('!oldById.containsKey'), isFalse);
      expect(body.contains('if (wasEnforcing) return true'), isTrue);
      expect(
        body.contains('wasEnforcing && !(next.enabled && next.autoStart)'),
        isTrue,
      );
    });

    test('setup a11y toggle: enabling free, disabling gated', () {
      // User report 2026-11-28: the toggle had it backwards (the
      // old v1.0.4 directive gated enabling). It must gate only
      // the OFF direction, like every other protection toggle.
      final s = src('lib/ui/setup_screen.dart');
      final start = s.indexOf('SwitchListTile(');
      final body = s.substring(start, start + 1600);
      expect(body.contains('setAccessibilityEnabled(v)'), isTrue);
      expect(body.contains('if (!v &&'), isTrue);
      expect(body.contains('ENABLING the service grants a privilege'), isFalse);
    });
  });
}
