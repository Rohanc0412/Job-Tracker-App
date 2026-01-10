import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/application.dart';
import '../../domain/status/status_types.dart';

class AppTable extends StatefulWidget {
  final List<Application> applications;
  final String? selectedId;
  final ValueChanged<Application> onSelected;

  const AppTable({
    super.key,
    required this.applications,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  State<AppTable> createState() => _AppTableState();
}

class _AppTableState extends State<AppTable> {
  bool _ascending = false;

  List<Application> get _sorted {
    final sorted = [...widget.applications];
    sorted.sort((a, b) => _ascending
        ? a.lastUpdated.compareTo(b.lastUpdated)
        : b.lastUpdated.compareTo(a.lastUpdated));
    return sorted;
  }

  Color _statusColor(ApplicationStatus status, ColorScheme scheme) {
    switch (status) {
      case ApplicationStatus.applied:
        return scheme.secondary;
      case ApplicationStatus.assessment:
        return const Color(0xFF9B7BFF);
      case ApplicationStatus.interview:
        return scheme.primary;
      case ApplicationStatus.offer:
        return scheme.tertiary;
      case ApplicationStatus.underReview:
        return const Color(0xFFF2B04C);
      case ApplicationStatus.received:
        return const Color(0xFF58D1C9);
      case ApplicationStatus.rejected:
        return scheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final rows = _sorted;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Applications',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'All',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more,
                          size: 16, color: colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 860),
                child: Column(
                  children: [
                    _HeaderRow(
                      ascending: _ascending,
                      onSortToggle: () {
                        setState(() => _ascending = !_ascending);
                      },
                    ),
                    const SizedBox(height: 8),
                    ListView.separated(
                      itemCount: rows.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      separatorBuilder: (_, __) =>
                          Divider(color: colorScheme.outlineVariant),
                      itemBuilder: (context, index) {
                        final application = rows[index];
                        final selected = application.id == widget.selectedId;
                        final statusColor =
                            _statusColor(application.status, colorScheme);

                        return InkWell(
                          onTap: () => widget.onSelected(application),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? colorScheme.primary.withOpacity(0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                _Cell(
                                  flex: 2,
                                  child: Text(
                                    application.company,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                _Cell(
                                  flex: 2,
                                  child: Text(application.role),
                                ),
                                _Cell(
                                  flex: 2,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        application.status.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(color: statusColor),
                                      ),
                                    ),
                                  ),
                                ),
                                _Cell(
                                  flex: 1,
                                  child: Text('${application.confidence}%'),
                                ),
                                _Cell(
                                  flex: 1,
                                  child:
                                      Text(dateFormat.format(application.lastUpdated)),
                                ),
                                _Cell(
                                  flex: 1,
                                  child: Text(application.account),
                                ),
                                _Cell(
                                  flex: 1,
                                  child: Text(application.source),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  final bool ascending;
  final VoidCallback onSortToggle;

  const _HeaderRow({
    required this.ascending,
    required this.onSortToggle,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );

    return Row(
      children: [
        _HeaderCell(flex: 2, label: 'Company', textStyle: textStyle),
        _HeaderCell(flex: 2, label: 'Role', textStyle: textStyle),
        _HeaderCell(flex: 2, label: 'Status', textStyle: textStyle),
        _HeaderCell(flex: 1, label: 'Confidence', textStyle: textStyle),
        _HeaderCell(
          flex: 1,
          label: 'Last Updated',
          textStyle: textStyle,
          onTap: onSortToggle,
          trailing: Icon(
            ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        _HeaderCell(flex: 1, label: 'Account', textStyle: textStyle),
        _HeaderCell(flex: 1, label: 'Source', textStyle: textStyle),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final int flex;
  final String label;
  final TextStyle? textStyle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _HeaderCell({
    required this.flex,
    required this.label,
    required this.textStyle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Text(label, style: textStyle),
        if (trailing != null) ...[
          const SizedBox(width: 2),
          trailing!,
        ],
      ],
    );

    return _Cell(
      flex: flex,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: content,
              ),
            ),
    );
  }
}

class _Cell extends StatelessWidget {
  final int flex;
  final Widget child;

  const _Cell({required this.flex, required this.child});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: child,
      ),
    );
  }
}
