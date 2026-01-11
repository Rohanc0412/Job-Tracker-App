import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/activity_item.dart';

class ActivityTabs extends StatefulWidget {
  final List<ActivityItem> updates;
  final List<ActivityItem> upcoming;
  final int selectedDays;
  final ValueChanged<int> onWindowChanged;
  final ValueChanged<ActivityItem>? onInterviewSelected;

  const ActivityTabs({
    super.key,
    required this.updates,
    required this.upcoming,
    required this.selectedDays,
    required this.onWindowChanged,
    this.onInterviewSelected,
  });

  @override
  State<ActivityTabs> createState() => _ActivityTabsState();
}

class _ActivityTabsState extends State<ActivityTabs> {
  static const List<int> _filterOptions = [7, 14, 30];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tabTextStyle = Theme.of(context).textTheme.labelLarge;

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
                      items: widget.upcoming,
                      selectedDays: widget.selectedDays,
                      onSelectedDays: widget.onWindowChanged,
                      onItemSelected: widget.onInterviewSelected,
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
  final ValueChanged<ActivityItem>? onItemSelected;

  const _UpcomingContent({
    required this.items,
    required this.selectedDays,
    required this.onSelectedDays,
    this.onItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Window',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(width: 10),
            DropdownButton<int>(
              value: selectedDays,
              items: [
                for (final days in _ActivityTabsState._filterOptions)
                  DropdownMenuItem(
                    value: days,
                    child: Text('$days days'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                onSelectedDays(value);
              },
              dropdownColor: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _ActivityList(
            items: items,
            emptyMessage: 'No interviews in the next $selectedDays days',
            onItemSelected: onItemSelected,
          ),
        ),
      ],
    );
  }
}

class _ActivityList extends StatelessWidget {
  final List<ActivityItem> items;
  final String? emptyMessage;
  final ValueChanged<ActivityItem>? onItemSelected;

  const _ActivityList({
    required this.items,
    this.emptyMessage,
    this.onItemSelected,
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
    final dateTimeFormat = DateFormat('MMM d, h:mm a');

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
        final displayTime = item.kind == ActivityKind.interview
            ? _formatInterviewTime(item, dateTimeFormat)
            : dateFormat.format(item.timestamp);
        final content = Container(
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
                displayTime,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
        if (onItemSelected == null) {
          return content;
        }
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onItemSelected!(item),
          child: content,
        );
      },
    );
  }

  String _formatInterviewTime(ActivityItem item, DateFormat dateTimeFormat) {
    final timeText = dateTimeFormat.format(item.timestamp);
    final tz = _formatTimezone(item.timezone);
    if (tz.isEmpty) {
      return timeText;
    }
    return '$tz $timeText';
  }

  String _formatTimezone(String? timezone) {
    if (timezone == null || timezone.trim().isEmpty) {
      return '';
    }
    switch (timezone) {
      case 'America/New_York':
        return 'ET';
      case 'America/Chicago':
        return 'CT';
      case 'America/Denver':
        return 'MT';
      case 'America/Los_Angeles':
        return 'PT';
    }
    if (timezone.length <= 4) {
      return timezone;
    }
    final parts = timezone.split('/');
    if (parts.isNotEmpty) {
      return parts.last.replaceAll('_', ' ');
    }
    return timezone;
  }
}
