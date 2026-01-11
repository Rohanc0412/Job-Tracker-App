import 'package:flutter/material.dart';

class Topbar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool showSearch;
  final VoidCallback? onSync;
  final bool syncInProgress;
  final String? syncLabel;
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
          if (showSearch) const SizedBox(width: 12),
          if (showSearch)
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: () {},
                icon: const Icon(Icons.settings_outlined),
                color: colorScheme.onSurface,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              ),
            ),
          if (showSearch) const SizedBox(width: 12),
          if (showSearch)
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
        ],
      ),
    );
  }
}
