/// Dominanter — Flutter rebuild of DeChainer v1.12.0.
///
/// Startup routing (F31): no recovery code → setup wizard only; code set →
/// lock screen (pre-auth panic surface) → biometric gate → the three root
/// tabs of the original (Restrictions / Apps / Config) plus a Status tab
/// hosting the Setup flow (F30).
library;

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'l10n/l10n.dart';
import 'theme.dart';
import 'ui/apps_tab.dart';
import 'ui/common.dart';
import 'ui/config_tab.dart';
import 'ui/lock_screen.dart';
import 'ui/pill_nav.dart';
import 'ui/recovery_ui.dart';
import 'ui/restrictions_tab.dart';
import 'ui/setup_screen.dart';

void main() {
  runApp(const DominanterApp());
}

class DominanterApp extends StatefulWidget {
  const DominanterApp({super.key});

  @override
  State<DominanterApp> createState() => _DominanterAppState();
}

class _DominanterAppState extends State<DominanterApp> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _controller.initialise();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => MaterialApp(
        title: 'Dominanter',
        debugShowCheckedModeBanner: false,
        themeMode: _controller.themeMode,
        // Bilingual UI (v1.0.4): Arabic + English. The locale follows
        // the controller's language (saved choice, else device locale);
        // Flutter's directionality makes Arabic render RTL.
        locale: Locale(_controller.language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Redesign v2 2026-11-09: RED & BLACK ONLY identity, inspired by
        // the user's reference images (see theme.dart for the palette,
        // the fusion pill bar and the contrast rules).
        theme: dominanterLightTheme(),
        darkTheme: dominanterDarkTheme(),
        home: switch (_controller.startup) {
          StartupState.loading => Scaffold(
            body: LoadingView(message: context.l10n.startingDominanter),
          ),
          StartupState.error => Scaffold(
            body: ErrorView(
              error: _controller.startupError ??
                  context.l10n.unknownStartupError,
              onRetry: _controller.initialise,
            ),
          ),
          StartupState.needsRecoverySetup => SetupRecoveryScreen(
            controller: _controller,
          ),
          StartupState.locked => LockScreen(controller: _controller),
          StartupState.unlocked => AppShell(controller: _controller),
        },
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabs = <Widget>[
      SetupScreen(controller: widget.controller),
      RestrictionsTab(controller: widget.controller),
      AppsTab(controller: widget.controller),
      ConfigTab(controller: widget.controller),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [SessionChip(controller: widget.controller)],
      ),
      // The floating pill bar lives in the bottomNavigationBar slot, so
      // the Scaffold reserves its full height (bar + margins) and tab
      // bodies are never covered by it.
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: DominanterNavBar(
        selectedIndex: _index,
        onSelected: (i) => setState(() => _index = i),
        destinations: [
          PillNavDestination(
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings,
            label: l10n.tabStatus,
          ),
          PillNavDestination(
            icon: Icons.shield_outlined,
            selectedIcon: Icons.shield,
            label: l10n.tabRestrictions,
          ),
          PillNavDestination(
            icon: Icons.apps_outlined,
            selectedIcon: Icons.apps,
            label: l10n.tabApps,
          ),
          PillNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: l10n.tabConfig,
          ),
        ],
      ),
    );
  }
}
