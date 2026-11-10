/// Plain-language explanations for EVERY system restriction in
/// the catalog (user item 12, v1.0.6): one shared source, keyed
/// by restriction id, used by the Restrictions tab (and reusable
/// by any editor over the same catalog). Viewing an explanation
/// is free help — no gate; toggling keeps its existing gates.
///
/// The presentation is the Phase E centered Card: high-contrast,
/// explicit OK button, never auto-dismissed.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Every restriction key the native catalog can return
/// (UserManager DISALLOW_/ALLOW_/ENSURE_ values on API 36, the
/// recommended set, and the Samsung/Knox extras). The coverage
/// test pins that each of these has an explanation in BOTH
/// locales; any future key still gets [restrictionInfoGeneric].
const restrictionCatalogKeys = <String>{
  'disallow_biometric',
  'disallow_camera_toggle',
  'disallow_config_default_apps',
  'disallow_config_private_dns',
  'disallow_microphone_toggle',
  'ensure_verify_apps',
  'no_add_clone_profile',
  'no_add_managed_profile',
  'no_add_private_profile',
  'no_add_user',
  'no_add_wifi_config',
  'no_adjust_volume',
  'no_airplane_mode',
  'no_ambient_display',
  'no_assist_content',
  'no_autofill',
  'no_bluetooth',
  'no_bluetooth_sharing',
  'no_camera',
  'no_change_wifi_state',
  'no_config_bluetooth',
  'no_config_brightness',
  'no_config_cell_broadcasts',
  'no_config_credentials',
  'no_config_date_time',
  'no_config_locale',
  'no_config_location',
  'no_config_mobile_networks',
  'no_config_screen_timeout',
  'no_config_tethering',
  'no_config_vpn',
  'no_config_wifi',
  'no_config_wifi_private',
  'no_config_wifi_shared',
  'no_content_capture',
  'no_content_suggestions',
  'no_control_apps',
  'no_create_windows',
  'no_cross_profile_copy_paste',
  'no_data_roaming',
  'no_debugging_features',
  'no_factory_reset',
  'no_fun',
  'no_grant_admin',
  'no_install_apps',
  'no_install_unknown_sources',
  'no_install_unknown_sources_globally',
  'no_modify_accounts',
  'no_network_reset',
  'no_non_market_app_by_knox',
  'no_outgoing_beam',
  'no_outgoing_calls',
  'no_physical_media',
  'no_printing',
  'no_remove_managed_profile',
  'no_remove_user',
  'no_safe_boot',
  'no_set_user_icon',
  'no_set_wallpaper',
  'no_share_location',
  'no_sharing_into_profile',
  'no_sim_globally',
  'no_sms',
  'no_system_error_dialogs',
  'no_thread_network',
  'no_ultra_wideband_radio',
  'no_unified_password',
  'no_uninstall_apps',
  'no_unmute_microphone',
  'no_usb_file_transfer',
  'no_user_switch',
  'no_wallpaper',
  'no_wifi_direct',
  'no_wifi_tethering',
};

/// The explanation for [key] in the user's language — never
/// empty: unknown keys fall back to the generic explanation.
String restrictionExplanation(AppLocalizations l10n, String key) =>
    switch (key) {
      'disallow_biometric' => l10n.info_disallow_biometric,
      'disallow_camera_toggle' => l10n.info_disallow_camera_toggle,
      'disallow_config_default_apps' => l10n.info_disallow_config_default_apps,
      'disallow_config_private_dns' => l10n.info_disallow_config_private_dns,
      'disallow_microphone_toggle' => l10n.info_disallow_microphone_toggle,
      'ensure_verify_apps' => l10n.info_ensure_verify_apps,
      'no_add_clone_profile' => l10n.info_no_add_clone_profile,
      'no_add_managed_profile' => l10n.info_no_add_managed_profile,
      'no_add_private_profile' => l10n.info_no_add_private_profile,
      'no_add_user' => l10n.info_no_add_user,
      'no_add_wifi_config' => l10n.info_no_add_wifi_config,
      'no_adjust_volume' => l10n.info_no_adjust_volume,
      'no_airplane_mode' => l10n.info_no_airplane_mode,
      'no_ambient_display' => l10n.info_no_ambient_display,
      'no_assist_content' => l10n.info_no_assist_content,
      'no_autofill' => l10n.info_no_autofill,
      'no_bluetooth' => l10n.info_no_bluetooth,
      'no_bluetooth_sharing' => l10n.info_no_bluetooth_sharing,
      'no_camera' => l10n.info_no_camera,
      'no_change_wifi_state' => l10n.info_no_change_wifi_state,
      'no_config_bluetooth' => l10n.info_no_config_bluetooth,
      'no_config_brightness' => l10n.info_no_config_brightness,
      'no_config_cell_broadcasts' => l10n.info_no_config_cell_broadcasts,
      'no_config_credentials' => l10n.info_no_config_credentials,
      'no_config_date_time' => l10n.info_no_config_date_time,
      'no_config_locale' => l10n.info_no_config_locale,
      'no_config_location' => l10n.info_no_config_location,
      'no_config_mobile_networks' => l10n.info_no_config_mobile_networks,
      'no_config_screen_timeout' => l10n.info_no_config_screen_timeout,
      'no_config_tethering' => l10n.info_no_config_tethering,
      'no_config_vpn' => l10n.info_no_config_vpn,
      'no_config_wifi' => l10n.info_no_config_wifi,
      'no_config_wifi_private' => l10n.info_no_config_wifi_private,
      'no_config_wifi_shared' => l10n.info_no_config_wifi_shared,
      'no_content_capture' => l10n.info_no_content_capture,
      'no_content_suggestions' => l10n.info_no_content_suggestions,
      'no_control_apps' => l10n.info_no_control_apps,
      'no_create_windows' => l10n.info_no_create_windows,
      'no_cross_profile_copy_paste' => l10n.info_no_cross_profile_copy_paste,
      'no_data_roaming' => l10n.info_no_data_roaming,
      'no_debugging_features' => l10n.info_no_debugging_features,
      'no_factory_reset' => l10n.info_no_factory_reset,
      'no_fun' => l10n.info_no_fun,
      'no_grant_admin' => l10n.info_no_grant_admin,
      'no_install_apps' => l10n.info_no_install_apps,
      'no_install_unknown_sources' => l10n.info_no_install_unknown_sources,
      'no_install_unknown_sources_globally' => l10n.info_no_install_unknown_sources_globally,
      'no_modify_accounts' => l10n.info_no_modify_accounts,
      'no_network_reset' => l10n.info_no_network_reset,
      'no_non_market_app_by_knox' => l10n.info_no_non_market_app_by_knox,
      'no_outgoing_beam' => l10n.info_no_outgoing_beam,
      'no_outgoing_calls' => l10n.info_no_outgoing_calls,
      'no_physical_media' => l10n.info_no_physical_media,
      'no_printing' => l10n.info_no_printing,
      'no_remove_managed_profile' => l10n.info_no_remove_managed_profile,
      'no_remove_user' => l10n.info_no_remove_user,
      'no_safe_boot' => l10n.info_no_safe_boot,
      'no_set_user_icon' => l10n.info_no_set_user_icon,
      'no_set_wallpaper' => l10n.info_no_set_wallpaper,
      'no_share_location' => l10n.info_no_share_location,
      'no_sharing_into_profile' => l10n.info_no_sharing_into_profile,
      'no_sim_globally' => l10n.info_no_sim_globally,
      'no_sms' => l10n.info_no_sms,
      'no_system_error_dialogs' => l10n.info_no_system_error_dialogs,
      'no_thread_network' => l10n.info_no_thread_network,
      'no_ultra_wideband_radio' => l10n.info_no_ultra_wideband_radio,
      'no_unified_password' => l10n.info_no_unified_password,
      'no_uninstall_apps' => l10n.info_no_uninstall_apps,
      'no_unmute_microphone' => l10n.info_no_unmute_microphone,
      'no_usb_file_transfer' => l10n.info_no_usb_file_transfer,
      'no_user_switch' => l10n.info_no_user_switch,
      'no_wallpaper' => l10n.info_no_wallpaper,
      'no_wifi_direct' => l10n.info_no_wifi_direct,
      'no_wifi_tethering' => l10n.info_no_wifi_tethering,
      _ => l10n.restrictionInfoGeneric,
    };

/// Shows [key]'s explanation in the centered Phase E card.
Future<void> showRestrictionInfo(
  BuildContext context, {
  required String label,
  required String key,
}) async {
  final l10n = context.l10n;
  final dark = Theme.of(context).brightness == Brightness.dark;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: dark ? const Color(0xFF17171A) : Colors.white,
      icon: const Icon(
        Icons.info_outlined,
        color: Color(0xFFD90429),
        size: 40,
      ),
      title: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: dark ? Colors.white : const Color(0xFF0B0B0C),
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Text(
          restrictionExplanation(l10n, key),
          style: TextStyle(
            color: dark ? Colors.white : const Color(0xFF0B0B0C),
            fontSize: 16,
            height: 1.45,
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.okButton),
        ),
      ],
    ),
  );
}
