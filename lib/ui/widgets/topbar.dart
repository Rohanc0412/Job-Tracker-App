import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class Topbar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showSearch;
  final VoidCallback? onSync;
  final bool syncInProgress;
  final String? syncLabel;
  final int reviewCount;
  final VoidCallback? onReview;
  final bool showSettings;
  final bool showSync;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;

  const Topbar({
    super.key,
    required this.title,
    this.subtitle,
    this.showSearch = false,
    this.onSync,
    this.syncInProgress = false,
    this.syncLabel,
    this.reviewCount = 0,
    this.onReview,
    this.showSettings = true,
    this.showSync = true,
    this.searchController,
    this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: colorScheme.background,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
            ],
          ),
          const Spacer(),
          if (showSearch)
            SizedBox(
              width: 280,
              child: TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  hintText: 'Search company or role...',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: onSearchChanged,
              ),
            ),
          if (showSearch && showSettings) const SizedBox(width: 12),
          if (showSearch && showSettings)
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: () => context.go('/settings'),
                icon: const Icon(Icons.settings_outlined),
                color: colorScheme.onSurface,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              ),
            ),
          if (showSearch && showSync) const SizedBox(width: 12),
          if (showSearch && showSync)
            FilledButton.icon(
              onPressed: syncInProgress ? null : (onSync ?? () {}),
              icon: syncInProgress
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
              label: Text(syncLabel ?? 'Sync Gmail'),
            ),
          if (reviewCount > 0) const SizedBox(width: 12),
          if (reviewCount > 0)
            OutlinedButton.icon(
              onPressed: onReview,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: Text('Review ($reviewCount)'),
            ),
        ],
      ),
    );
  }
}
