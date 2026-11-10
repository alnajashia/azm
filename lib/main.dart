/// Dominanter — Flutter rebuild of DeChainer v1.12.0.
///
/// Startup routing (F31): no recovery code → setup wizard only; code set →
/// lock screen (pre-auth panic surface) → biometric gate → the three root
/// tabs of the original (Restrictions / Apps / Config) plus a Status tab
/// hosting the Setup flow (F30).
library;

import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'domain/entry_grace.dart';
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
        title: 'Azm',
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
              error:
                  _controller.startupError ?? context.l10n.unknownStartupError,
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

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  /// When the app last left the foreground during this unlock
  /// (Phase C relock decision input).
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cross-tab navigation requests (item 13): e.g. the Restrictions
    // not-owner card asks for the Config tab instead of opening a
    // pop-up page.
    widget.controller.addListener(_consumeTabRequest);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_consumeTabRequest);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _consumeTabRequest() {
    final requested = widget.controller.requestedTab;
    if (requested == null) return;
    widget.controller.clearTabRequest();
    if (requested != _index && mounted) {
      setState(() => _index = requested);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = widget.controller;
    if (controller.startup != StartupState.unlocked) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final backgroundedAt = _backgroundedAt;
        _backgroundedAt = null;
        if (backgroundedAt == null) return;
        final now = DateTime.now();
        // App-lock timing (Phase C): relock on return when the grace
        // has run out. Brief absences (biometric prompt, permission
        // dialogs, pickers) are debounced inside the decision.
        if (entryShouldRelock(
          now: now,
          lastUnlockAt: controller.entryLastUnlockAt,
          period: controller.entryGracePeriod,
          backgroundedFor: now.difference(backgroundedAt),
        )) {
          controller.relock();
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

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
      // v1.0.6 (user item 11): the header is a minimal brand row ONLY
      // — small logo + app name, generous whitespace, no action
      // buttons. Everything session-related lives in the dedicated
      // "Recovery session" card directly below it (SessionSection).
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/branding/dominanter_logo.png',
                width: 28,
                height: 28,
              ),
            ),
            const SizedBox(width: 12),
            Text(l10n.appTitle),
          ],
        ),
      ),
      // The floating pill bar lives in the bottomNavigationBar slot, so
      // the Scaffold reserves its full height (bar + margins) and tab
      // bodies are never covered by it.
      body: Column(
        children: [
          SessionSection(controller: widget.controller),
          Expanded(child: IndexedStack(index: _index, children: tabs)),
        ],
      ),
      bottomNavigationBar: DominanterNavBar(
        selectedIndex: _index,
        onSelected: (i) => setState(() => _index = i),
        destinations: [
          PillNavDestination(
            icon: Icons.admin_panel_settings_outlined,
            selectedIcon: Icons.admin_panel_settings_outlined,
            label: l10n.tabStatus,
          ),
          PillNavDestination(
            icon: Icons.shield_outlined,
            selectedIcon: Icons.shield_outlined,
            label: l10n.tabRestrictions,
          ),
          PillNavDestination(
            icon: Icons.apps_outlined,
            selectedIcon: Icons.apps_outlined,
            label: l10n.tabApps,
          ),
          PillNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_outlined,
            label: l10n.tabConfig,
          ),
        ],
      ),
    );
  }
}

/// The "Recovery session" section directly below the header
/// (v1.0.6, user item 11): a titled card that appears only while a
/// recovery session is active, carrying the remaining time and the
/// Renew / End actions. This is a RELOCATION of the old header chip
/// — the actions are the very same `session.renew` / `session.end`
/// calls with the same behaviour and gates; nothing about the
/// session itself changed.
class SessionSection extends StatelessWidget {
  const SessionSection({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller.session,
      builder: (context, _) {
        if (!controller.session.isActive) return const SizedBox.shrink();
        final l10n = context.l10n;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SectionCard(
            title: l10n.sessionRemaining,
            children: [
              ListTile(
                leading: const Icon(Icons.lock_open_outlined),
                title: Text(
                  formatDuration(controller.session.remaining, l10n),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: controller.session.renew,
                      child: Text(l10n.renewSession),
                    ),
                    TextButton(
                      onPressed: controller.session.end,
                      child: Text(l10n.endSession),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
