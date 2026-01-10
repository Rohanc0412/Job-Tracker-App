import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class Sidebar extends StatelessWidget {
  final int selectedIndex;

  const Sidebar({super.key, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final items = <_SidebarItem>[
      _SidebarItem(
        label: 'Dashboard',
        icon: Icons.dashboard_rounded,
        route: '/',
        enabled: true,
      ),
      _SidebarItem(
        label: 'Applications',
        icon: Icons.work_rounded,
        route: '/applications',
        enabled: true,
      ),
      _SidebarItem(
        label: 'Analytics',
        icon: Icons.insights_rounded,
        route: '/analytics',
        enabled: false,
      ),
      _SidebarItem(
        label: 'Settings',
        icon: Icons.settings_rounded,
        route: '/settings',
        enabled: true,
      ),
    ];

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.inbox_rounded, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Job Tracker',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'Pro Version',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            for (var i = 0; i < items.length; i++)
              _SidebarTile(
                item: items[i],
                selected: selectedIndex == i,
                onTap: items[i].enabled
                    ? () => context.go(items[i].route)
                    : null,
              ),
            const Spacer(),
            Text(
              'Local only',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem {
  final String label;
  final IconData icon;
  final String route;
  final bool enabled;

  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.route,
    required this.enabled,
  });
}

class _SidebarTile extends StatelessWidget {
  final _SidebarItem item;
  final bool selected;
  final VoidCallback? onTap;

  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = selected
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;
    final iconColor = selected ? colorScheme.primary : textColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.surfaceVariant.withOpacity(0.9)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? colorScheme.primary.withOpacity(0.3)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(item.icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
              if (!item.enabled)
                Icon(Icons.lock_outline,
                    size: 14, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
