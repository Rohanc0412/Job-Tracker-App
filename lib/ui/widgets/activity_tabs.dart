import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/activity_item.dart';
import '../../services/body_retrieval_service.dart';
import '../../services/logger.dart';

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
        return _ActivityListItem(
          item: item,
          displayTime: displayTime,
          dotColor: _dotColor(item.kind, colorScheme),
          onItemSelected: onItemSelected,
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

class _ActivityListItem extends StatefulWidget {
  final ActivityItem item;
  final String displayTime;
  final Color dotColor;
  final ValueChanged<ActivityItem>? onItemSelected;

  const _ActivityListItem({
    required this.item,
    required this.displayTime,
    required this.dotColor,
    this.onItemSelected,
  });

  @override
  State<_ActivityListItem> createState() => _ActivityListItemState();
}

class _ActivityListItemState extends State<_ActivityListItem> {
  bool _isExpanded = false;
  String? _fullBody;
  bool _isLoadingBody = false;
  final _bodyService = BodyRetrievalService();

  bool get _hasBodyContent {
    return widget.item.rawBodyText != null || widget.item.rawBodyPath != null;
  }

  Future<void> _toggleExpanded() async {
    if (!_hasBodyContent) {
      AppLogger.log.info('[ActivityTab] No body content for item: ${widget.item.title}');
      return;
    }

    if (!_isExpanded) {
      // Expanding - load body if not already loaded
      if (_fullBody == null && !_isLoadingBody) {
        setState(() => _isLoadingBody = true);
        try {
          AppLogger.log.info('[ActivityTab] Loading body - hasText: ${widget.item.rawBodyText != null}, hasPath: ${widget.item.rawBodyPath != null}');

          final body = await _bodyService.getFullBody(
            rawBodyText: widget.item.rawBodyText,
            rawBodyPath: widget.item.rawBodyPath,
          );

          AppLogger.log.info('[ActivityTab] Loaded body length: ${body?.length ?? 0}');

          if (mounted) {
            setState(() {
              _fullBody = body;
              _isLoadingBody = false;
              _isExpanded = true;
            });
          }
        } catch (e, stack) {
          AppLogger.log.severe('[ActivityTab] Error loading body: $e\n$stack');
          if (mounted) {
            setState(() => _isLoadingBody = false);
          }
        }
      } else {
        setState(() => _isExpanded = true);
      }
    } else {
      // Collapsing
      setState(() => _isExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final detail = widget.item.detail.trim();
    final showDetail =
        detail.isNotEmpty && detail != widget.item.title.trim();

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: widget.dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (showDetail) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.displayTime,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (_hasBodyContent) ...[
                    const SizedBox(height: 4),
                    Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (_isExpanded) ...[
            const SizedBox(height: 12),
            Divider(color: colorScheme.outlineVariant, height: 1),
            const SizedBox(height: 12),
            if (_isLoadingBody)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              )
            else if (_fullBody != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _fullBody!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: colorScheme.onSurface,
                          ),
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  'Body content unavailable',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.error,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
          ],
        ],
      ),
    );

    if (widget.onItemSelected == null && !_hasBodyContent) {
      return content;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _hasBodyContent
          ? _toggleExpanded
          : (widget.onItemSelected != null
              ? () => widget.onItemSelected!(widget.item)
              : null),
      child: content,
    );
  }
}
