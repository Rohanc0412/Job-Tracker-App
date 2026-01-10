import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/seed/demo_data.dart';

class ActivityTabs extends StatefulWidget {
  final List<ActivityItem> updates;
  final List<ActivityItem> upcoming;

  const ActivityTabs({
    super.key,
    required this.updates,
    required this.upcoming,
  });

  @override
  State<ActivityTabs> createState() => _ActivityTabsState();
}

class _ActivityTabsState extends State<ActivityTabs> {
  static const List<int> _filterOptions = [7, 15, 30];
  int _selectedDays = 15;

  List<ActivityItem> _filteredUpcoming() {
    final now = DateTime.now();
    final end = now.add(Duration(days: _selectedDays));
    final filtered = widget.upcoming
        .where((item) => !item.timestamp.isBefore(now))
        .where((item) => !item.timestamp.isAfter(end))
        .toList();
    filtered.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tabTextStyle = Theme.of(context).textTheme.labelLarge;
    final upcoming = _filteredUpcoming();

    return DefaultTabController(
      length: 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TabBar(
                labelStyle: tabTextStyle,
                unselectedLabelStyle: tabTextStyle,
                labelColor: colorScheme.onSurface,
                unselectedLabelColor: colorScheme.onSurfaceVariant,
                indicatorColor: colorScheme.primary,
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(text: 'Updates'),
                  Tab(text: 'Upcoming Interviews'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: TabBarView(
                  children: [
                    _ActivityList(items: widget.updates),
                    _UpcomingContent(
                      items: upcoming,
                      selectedDays: _selectedDays,
                      onSelectedDays: (value) {
                        setState(() => _selectedDays = value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingContent extends StatelessWidget {
  final List<ActivityItem> items;
  final int selectedDays;
  final ValueChanged<int> onSelectedDays;

  const _UpcomingContent({
    required this.items,
    required this.selectedDays,
    required this.onSelectedDays,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final days in _ActivityTabsState._filterOptions)
              ChoiceChip(
                label: Text('$days days'),
                selected: days == selectedDays,
                onSelected: (_) => onSelectedDays(days),
                labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: days == selectedDays
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      fontWeight:
                          days == selectedDays ? FontWeight.w600 : FontWeight.w500,
                    ),
                selectedColor: colorScheme.primary.withOpacity(0.25),
                backgroundColor: colorScheme.surfaceVariant.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: days == selectedDays
                        ? colorScheme.primary.withOpacity(0.6)
                        : colorScheme.outlineVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _ActivityList(
            items: items,
            emptyMessage: 'No interviews in the next $selectedDays days',
          ),
        ),
      ],
    );
  }
}

class _ActivityList extends StatelessWidget {
  final List<ActivityItem> items;
  final String? emptyMessage;

  const _ActivityList({
    required this.items,
    this.emptyMessage,
  });

  Color _dotColor(ActivityKind kind, ColorScheme scheme) {
    switch (kind) {
      case ActivityKind.offer:
        return scheme.tertiary;
      case ActivityKind.rejection:
        return scheme.error;
      case ActivityKind.interview:
        return scheme.secondary;
      case ActivityKind.update:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d');

    if (items.isEmpty) {
      return Center(
        child: Text(
          emptyMessage ?? 'No recent activity',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant.withOpacity(0.7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _dotColor(item.kind, colorScheme),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.detail,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                dateFormat.format(item.timestamp),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
