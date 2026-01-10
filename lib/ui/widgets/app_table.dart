import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/application.dart';
import '../../domain/status/status_types.dart';

const double _companyWidth = 180;
const double _roleWidth = 180;
const double _statusWidth = 140;
const double _confidenceWidth = 110;
const double _updatedWidth = 130;
const double _accountWidth = 120;
const double _sourceWidth = 120;
const double _tableMinWidth = _companyWidth +
    _roleWidth +
    _statusWidth +
    _confidenceWidth +
    _updatedWidth +
    _accountWidth +
    _sourceWidth;

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
  ApplicationStatus? _statusFilter;
  String? _accountFilter;

  List<String> get _accounts {
    final values = widget.applications.map((app) => app.account).toSet().toList()
      ..sort();
    return values;
  }

  List<Application> get _sorted {
    final sorted = _applyFilters(widget.applications);
    sorted.sort((a, b) => _ascending
        ? a.lastUpdated.compareTo(b.lastUpdated)
        : b.lastUpdated.compareTo(a.lastUpdated));
    return sorted;
  }

  List<Application> _applyFilters(List<Application> items) {
    return items.where((app) {
      final statusMatch = _statusFilter == null || app.status == _statusFilter;
      final accountMatch =
          _accountFilter == null || app.account == _accountFilter;
      return statusMatch && accountMatch;
    }).toList();
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
    final statusLabel = _statusFilter?.label ?? 'All';
    final accountLabel = _accountFilter ?? 'All';

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
                _FilterMenu<ApplicationStatus>(
                  label: 'Status',
                  valueLabel: statusLabel,
                  active: _statusFilter != null,
                  items: [
                    const PopupMenuItem<ApplicationStatus?>(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    ...ApplicationStatus.values.map(
                      (status) => PopupMenuItem<ApplicationStatus?>(
                        value: status,
                        child: Text(status.label),
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    setState(() => _statusFilter = value);
                  },
                ),
                const SizedBox(width: 10),
                _FilterMenu<String>(
                  label: 'Account',
                  valueLabel: accountLabel,
                  active: _accountFilter != null,
                  items: [
                    const PopupMenuItem<String?>(
                      value: null,
                      child: Text('All accounts'),
                    ),
                    ..._accounts.map(
                      (account) => PopupMenuItem<String?>(
                        value: account,
                        child: Text(account),
                      ),
                    ),
                  ],
                  onSelected: (value) {
                    setState(() => _accountFilter = value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: _tableMinWidth),
                child: Column(
                  children: [
                    _HeaderRow(
                      ascending: _ascending,
                      onSortToggle: () {
                        setState(() => _ascending = !_ascending);
                      },
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      SizedBox(
                        height: 160,
                        child: Center(
                          child: Text(
                            'No applications match the selected filters',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      )
                    else
                      Column(
                        children: [
                          for (var i = 0; i < rows.length; i++) ...[
                            Builder(builder: (context) {
                              final application = rows[i];
                              final selected =
                                  application.id == widget.selectedId;
                              final statusColor = _statusColor(
                                  application.status, colorScheme);

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
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _Cell(
                                        width: _companyWidth,
                                        child: Text(
                                          application.company,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      _Cell(
                                        width: _roleWidth,
                                        child: Text(application.role),
                                      ),
                                      _Cell(
                                        width: _statusWidth,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  statusColor.withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              application.status.label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                      color: statusColor),
                                            ),
                                          ),
                                        ),
                                      ),
                                      _Cell(
                                        width: _confidenceWidth,
                                        child: Text(
                                            '${application.confidence}%'),
                                      ),
                                      _Cell(
                                        width: _updatedWidth,
                                        child: Text(dateFormat
                                            .format(application.lastUpdated)),
                                      ),
                                      _Cell(
                                        width: _accountWidth,
                                        child: Text(application.account),
                                      ),
                                      _Cell(
                                        width: _sourceWidth,
                                        child: Text(application.source),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            if (i != rows.length - 1)
                              Divider(color: colorScheme.outlineVariant),
                          ],
                        ],
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
      mainAxisSize: MainAxisSize.min,
      children: [
        _HeaderCell(width: _companyWidth, label: 'Company', textStyle: textStyle),
        _HeaderCell(width: _roleWidth, label: 'Role', textStyle: textStyle),
        _HeaderCell(width: _statusWidth, label: 'Status', textStyle: textStyle),
        _HeaderCell(
          width: _confidenceWidth,
          label: 'Confidence',
          textStyle: textStyle,
        ),
        _HeaderCell(
          width: _updatedWidth,
          label: 'Last Updated',
          textStyle: textStyle,
          onTap: onSortToggle,
          trailing: Icon(
            ascending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        _HeaderCell(
          width: _accountWidth,
          label: 'Account',
          textStyle: textStyle,
        ),
        _HeaderCell(width: _sourceWidth, label: 'Source', textStyle: textStyle),
      ],
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final double width;
  final String label;
  final TextStyle? textStyle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _HeaderCell({
    required this.width,
    required this.label,
    required this.textStyle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 2),
          trailing!,
        ],
      ],
    );

    return _Cell(
      width: width,
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
  final double width;
  final Widget child;

  const _Cell({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: child,
      ),
    );
  }
}

class _FilterMenu<T> extends StatelessWidget {
  final String label;
  final String valueLabel;
  final bool active;
  final List<PopupMenuEntry<T?>> items;
  final ValueChanged<T?> onSelected;

  const _FilterMenu({
    required this.label,
    required this.valueLabel,
    required this.active,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopupMenuButton<T?>(
      onSelected: onSelected,
      itemBuilder: (context) => items,
      offset: const Offset(0, 36),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? colorScheme.primary.withOpacity(0.18)
              : colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? colorScheme.primary.withOpacity(0.5)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Text(
              '$label: $valueLabel',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: active
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more,
              size: 16,
              color: active
                  ? colorScheme.onSurface
                  : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
