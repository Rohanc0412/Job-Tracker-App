import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/activity_item.dart';
import '../../data/models/application.dart';
import '../../domain/status/status_types.dart';
import '../../services/body_retrieval_service.dart';
import '../../services/logger.dart';

class DetailsPanel extends StatelessWidget {
  final Application? application;
  final List<ActivityItem> timeline;

  const DetailsPanel({
    super.key,
    required this.application,
    required this.timeline,
  });

  String? _resolveInterviewTimezone(
    DateTime? target,
    List<ActivityItem> timeline,
  ) {
    String? fallback;
    for (final item in timeline) {
      if (item.kind != ActivityKind.interview) {
        continue;
      }
      final tz = item.timezone;
      if (tz == null || tz.trim().isEmpty) {
        continue;
      }
      fallback ??= tz;
      if (target != null && _sameMinute(item.timestamp, target)) {
        return tz;
      }
    }
    return fallback;
  }

  Future<void> _openPortal(BuildContext context, String url) async {
    final uri = _normalizePortalUrl(url);
    if (uri == null) {
      _showPortalError(context, 'Invalid portal URL.');
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      _showPortalError(context, 'Unable to open portal.');
    }
  }

  void _showPortalError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('MMM d, h:mm a');
    final timelineFormat = DateFormat('MMM d, h:mm a');
    final nextStepTimezone =
        _resolveInterviewTimezone(application?.nextStepAt, timeline);

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
                                    _formatTimeWithTimezone(
                                      application!.nextStepAt!,
                                      nextStepTimezone,
                                      timeFormat,
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: colorScheme.onSurfaceVariant,
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
                    onPressed: application!.portalUrl == null
                        ? null
                        : () async {
                            await _openPortal(
                              context,
                              application!.portalUrl!,
                            );
                          },
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

class _TimelineItem extends StatefulWidget {
  final ActivityItem item;
  final DateFormat timeFormat;

  const _TimelineItem({
    required this.item,
    required this.timeFormat,
  });

  @override
  State<_TimelineItem> createState() => _TimelineItemState();
}

class _TimelineItemState extends State<_TimelineItem> {
  bool _isExpanded = false;
  String? _fullBody;
  bool _isLoadingBody = false;
  final _bodyService = BodyRetrievalService();

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

  bool get _hasBodyContent {
    return (widget.item.rawBodyText?.isNotEmpty ?? false) ||
        (widget.item.rawBodyPath?.isNotEmpty ?? false);
  }

  Future<void> _toggleExpanded() async {
    if (!_hasBodyContent) {
      AppLogger.log
          .info('[Timeline] No body content for item: ${widget.item.title}');
      return;
    }

    if (!_isExpanded) {
      // Expanding - load body if not already loaded
      if (_fullBody == null && !_isLoadingBody) {
        setState(() => _isLoadingBody = true);
        try {
          AppLogger.log.info(
              '[Timeline] Loading body - hasText: ${widget.item.rawBodyText != null}, hasPath: ${widget.item.rawBodyPath != null}');
          AppLogger.log.info(
              '[Timeline] rawBodyText length: ${widget.item.rawBodyText?.length ?? 0}');
          AppLogger.log
              .info('[Timeline] rawBodyPath: ${widget.item.rawBodyPath}');

          final body = await _bodyService.getFullBody(
            rawBodyText: widget.item.rawBodyText,
            rawBodyPath: widget.item.rawBodyPath,
          );

          AppLogger.log
              .info('[Timeline] Loaded body length: ${body?.length ?? 0}');

          if (mounted) {
            setState(() {
              _fullBody = body;
              _isLoadingBody = false;
              _isExpanded = true;
            });
          }
        } catch (e, stack) {
          AppLogger.log.severe('[Timeline] Error loading body: $e\n$stack');
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

    return InkWell(
      onTap: _hasBodyContent ? _toggleExpanded : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
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
                    color: _dotColor(widget.item.kind, colorScheme),
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
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTimeWithTimezone(
                        widget.item.timestamp,
                        widget.item.timezone,
                        widget.timeFormat,
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
      ),
    );
  }
}

String _formatTimeWithTimezone(
  DateTime time,
  String? timezone,
  DateFormat format,
) {
  final tzLabel = _formatTimezone(timezone);
  final timeText = format.format(time);
  if (tzLabel.isEmpty) {
    return timeText;
  }
  return '$tzLabel $timeText';
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

bool _sameMinute(DateTime a, DateTime b) {
  return (a.difference(b).abs()) < const Duration(minutes: 1);
}

Uri? _normalizePortalUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }
  return Uri.tryParse('https://$trimmed');
}
