/// Floating capsule bottom navigation (redesign v2 2026-11-09, after
/// the user's reference images — red & black only).
///
/// A floating pill that is ALWAYS black, in both brightness modes: the
/// fusion of the reference's red-bar and black-bar variants. Large
/// radius, soft black shadow plus a faint red glow, margined from the
/// screen edges. The active destination sits inside a filled red
/// indicator whose top edge sweeps up in a curve around the icon
/// (approximated with a custom clipper), white icon + label, and a
/// small white dot under the label. Inactive destinations are muted
/// light-grey (a tint of black) icon + label — never dark-on-black.
/// Behaviour is identical to the NavigationBar it replaces: same
/// destinations, same order, same tap-to-switch state.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class PillNavDestination {
  const PillNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class DominanterNavBar extends StatelessWidget {
  const DominanterNavBar({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<PillNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        // The bar floats; the Scaffold reserves this whole slot height,
        // and the outer 12dp is extra breathing room under content.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          height: 70,
          decoration: BoxDecoration(
            // Always black — light mode gets the reference's black pill
            // bar too, not a white one (red & black only identity).
            color: DominanterColors.blackBar,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.10 : 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.55 : 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              // Faint red under-glow, the reference bars' red halo.
              BoxShadow(
                color: DominanterColors.red.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _PillNavItem(
                    destination: destinations[i],
                    selected: i == selectedIndex,
                    // Muted light-grey in BOTH modes: the bar is always
                    // black, so the theme's onSurfaceVariant (near-black
                    // in light mode) would be unreadable here.
                    mutedColor: DominanterColors.onBlackMuted,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillNavItem extends StatelessWidget {
  const _PillNavItem({
    required this.destination,
    required this.selected,
    required this.mutedColor,
    required this.onTap,
  });

  final PillNavDestination destination;
  final bool selected;
  final Color mutedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(selected ? destination.selectedIcon : destination.icon, size: 22),
        const SizedBox(height: 1),
        Text(
          destination.label,
          style: const TextStyle(fontSize: 11, height: 1.1),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        // Small dot under the active item (reference detail); kept in the
        // layout for inactive items so nothing shifts when selection moves.
        Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? Colors.white : Colors.transparent,
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: ConstrainedBox(
              // Touch target >= 48dp tall (the pill itself is 70dp).
              constraints: const BoxConstraints(minHeight: 56),
              child: selected
                  ? ClipPath(
                      clipper: const _SweptIndicatorClipper(),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              DominanterColors.redGlow,
                              DominanterColors.red,
                              DominanterColors.redDark,
                            ],
                            stops: [0.0, 0.55, 1.0],
                          ),
                        ),
                        child: Center(
                          child: DefaultTextStyle.merge(
                            style: const TextStyle(color: Colors.white),
                            child: IconTheme.merge(
                              data: const IconThemeData(color: Colors.white),
                              child: content,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(color: mutedColor),
                        child: IconTheme.merge(
                          data: IconThemeData(color: mutedColor),
                          child: content,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The active indicator shape: a rounded pill whose top edge sweeps up
/// into a shallow hump in the centre, echoing the curved indicator in
/// the reference images. Purely a clip — the layout box never changes,
/// so nothing can overflow on narrow screens.
class _SweptIndicatorClipper extends CustomClipper<Path> {
  const _SweptIndicatorClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    const r = 26.0; // corner radius of the indicator body
    final path = Path()
      ..moveTo(r, h)
      ..lineTo(w - r, h)
      ..quadraticBezierTo(w, h, w, h - r)
      ..lineTo(w, r + 4)
      // Right shoulder sweeping up into the central hump.
      ..quadraticBezierTo(w, 2, w * 0.72, 2)
      ..quadraticBezierTo(w * 0.58, 2, w * 0.52, 0)
      ..quadraticBezierTo(w / 2, -1, w * 0.48, 0)
      ..quadraticBezierTo(w * 0.42, 2, w * 0.28, 2)
      // Left shoulder back down.
      ..quadraticBezierTo(0, 2, 0, r + 4)
      ..lineTo(0, h - r)
      ..quadraticBezierTo(0, h, r, h)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
