/// Dominanter — Flutter rebuild of DeChainer v1.12.0.
///
/// Startup routing (F31): no recovery code → setup wizard only; code set →
/// lock screen (pre-auth panic surface) → biometric gate → the three root
/// tabs of the original (Restrictions / Apps / Config) plus a Status tab
/// hosting the Setup flow (F30).
library;

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui/apps_tab.dart';
import 'ui/common.dart';
import 'ui/config_tab.dart';
import 'ui/lock_screen.dart';
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
    const seed = Color(0xFF3E6B48); // calm green — a self-control tool, not an alarm
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => MaterialApp(
        title: 'Dominanter',
        debugShowCheckedModeBanner: false,
        themeMode: _controller.themeMode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: seed),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme:
              ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        ),
        home: switch (_controller.startup) {
          StartupState.loading => const Scaffold(body: LoadingView(message: 'Starting Dominanter…')),
          StartupState.error => Scaffold(
              body: ErrorView(
                error: _controller.startupError ?? 'Unknown startup error',
                onRetry: _controller.initialise,
              ),
            ),
          StartupState.needsRecoverySetup => SetupRecoveryScreen(controller: _controller),
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
    final strings = AppStrings(widget.controller.language);
    final tabs = <Widget>[
      SetupScreen(controller: widget.controller),
      RestrictionsTab(controller: widget.controller),
      AppsTab(controller: widget.controller),
      ConfigTab(controller: widget.controller),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [SessionChip(controller: widget.controller)],
      ),
      body: IndexedStack(index: _index, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: const Icon(Icons.admin_panel_settings),
            label: strings.tabStatus,
          ),
          NavigationDestination(
            icon: const Icon(Icons.shield_outlined),
            selectedIcon: const Icon(Icons.shield),
            label: strings.tabRestrictions,
          ),
          NavigationDestination(
            icon: const Icon(Icons.apps_outlined),
            selectedIcon: const Icon(Icons.apps),
            label: strings.tabApps,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: strings.tabConfig,
          ),
        ],
      ),
    );
  }
}
