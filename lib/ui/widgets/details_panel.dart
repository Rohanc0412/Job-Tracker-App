import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/activity_item.dart';
import '../../data/models/application.dart';
import '../../domain/status/status_types.dart';

class DetailsPanel extends StatelessWidget {
  final Application? application;
  final List<ActivityItem> timeline;

  const DetailsPanel({
    super.key,
    required this.application,
    required this.timeline,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('MMM d, h:mm a');
    final timelineFormat = DateFormat('MMM d, h:mm a');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: application == null
            ? Center(
                child: Text(
                  'Select an application',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Application Details',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    application!.company,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    application!.role,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      application!.status.label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Divider(color: colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  _DetailRow(
                    label: 'Account',
                    value: application!.account,
                  ),
                  _DetailRow(
                    label: 'Source',
                    value: application!.source,
                  ),
                  _DetailRow(
                    label: 'Confidence',
                    value: '${application!.confidence}%',
                  ),
                  _DetailRow(
                    label: 'Last Updated',
                    value: dateFormat.format(application!.lastUpdated),
                  ),
                  const SizedBox(height: 16),
                  if (application!.nextStep != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_available,
                              color: colorScheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  application!.nextStep!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                if (application!.nextStepAt != null)
                                  Text(
                                    timeFormat
                                        .format(application!.nextStepAt!),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color:
                                              colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed:
                        application!.portalUrl == null ? null : () {},
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open Portal'),
                  ),
                  if (application!.portalUrl != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      application!.portalUrl!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Divider(color: colorScheme.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Timeline',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  if (timeline.isEmpty)
                    Text(
                      'No activity yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    )
                  else
                    Column(
                      children: [
                        for (var i = 0; i < timeline.length; i++) ...[
                          _TimelineItem(
                            item: timeline[i],
                            timeFormat: timelineFormat,
                          ),
                          if (i != timeline.length - 1)
                            const SizedBox(height: 10),
                        ],
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final ActivityItem item;
  final DateFormat timeFormat;

  const _TimelineItem({
    required this.item,
    required this.timeFormat,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
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
            timeFormat.format(item.timestamp),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
