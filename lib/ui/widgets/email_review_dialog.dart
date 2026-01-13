import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/application.dart';
import '../../data/models/email_review_item.dart';

class ReviewDialogState {
  final EmailReviewItem? item;
  final int queueCount;
  final bool syncInProgress;
  final bool syncComplete;

  const ReviewDialogState({
    required this.item,
    required this.queueCount,
    required this.syncInProgress,
    required this.syncComplete,
  });

  factory ReviewDialogState.empty() {
    return const ReviewDialogState(
      item: null,
      queueCount: 0,
      syncInProgress: false,
      syncComplete: false,
    );
  }

  bool get waitingForNext => item == null && syncInProgress;
}

class ReviewDraft {
  ReviewDraft({
    required this.relevant,
    required this.subject,
    required this.summary,
    required this.company,
    required this.role,
    required this.jobId,
    required this.portalUrl,
    required this.status,
    required this.source,
    required this.actionRequired,
    required this.actionItemsText,
    required this.interviewStart,
    required this.interviewEnd,
    required this.interviewTimezone,
    required this.interviewLocation,
    required this.interviewMeetingUrl,
    required this.selectedApplicationId,
    required this.forceNewApplication,
  });

  final bool relevant;
  final String subject;
  final String summary;
  final String company;
  final String role;
  final String jobId;
  final String portalUrl;
  final String status;
  final String source;
  final bool actionRequired;
  final String actionItemsText;
  final String interviewStart;
  final String interviewEnd;
  final String interviewTimezone;
  final String interviewLocation;
  final String interviewMeetingUrl;
  final String? selectedApplicationId;
  final bool forceNewApplication;

  Map<String, dynamic> toOverridesMap() {
    final overrides = <String, dynamic>{
      'relevant': relevant,
    };
    final subjectValue = subject.trim();
    if (subjectValue.isNotEmpty) {
      overrides['subject'] = subjectValue;
    }
    final summaryValue = summary.trim();
    if (summaryValue.isNotEmpty) {
      overrides['summary'] = summaryValue;
    }
    final companyValue = company.trim();
    if (companyValue.isNotEmpty) {
      overrides['company'] = companyValue;
    }
    final roleValue = role.trim();
    if (roleValue.isNotEmpty) {
      overrides['role'] = roleValue;
    }
    final jobIdValue = jobId.trim();
    if (jobIdValue.isNotEmpty) {
      overrides['jobId'] = jobIdValue;
    }
    final portalValue = portalUrl.trim();
    if (portalValue.isNotEmpty) {
      overrides['portalUrl'] = portalValue;
    }
    final statusValue = status.trim();
    if (statusValue.isNotEmpty) {
      overrides['status'] = statusValue;
    }
    final sourceValue = source.trim();
    if (sourceValue.isNotEmpty) {
      overrides['source'] = sourceValue;
    }

    overrides['actionRequired'] = actionRequired;
    final actionItems = _parseLines(actionItemsText);
    if (actionItems.isNotEmpty) {
      overrides['actionItems'] = actionItems;
    }

    final interview = <String, dynamic>{};
    final startValue = interviewStart.trim();
    if (startValue.isNotEmpty) {
      interview['start'] = startValue;
    }
    final endValue = interviewEnd.trim();
    if (endValue.isNotEmpty) {
      interview['end'] = endValue;
    }
    final tzValue = interviewTimezone.trim();
    if (tzValue.isNotEmpty) {
      interview['timezone'] = tzValue;
    }
    final locationValue = interviewLocation.trim();
    if (locationValue.isNotEmpty) {
      interview['location'] = locationValue;
    }
    final meetingValue = interviewMeetingUrl.trim();
    if (meetingValue.isNotEmpty) {
      interview['meetingUrl'] = meetingValue;
    }
    if (interview.isNotEmpty) {
      overrides['interview'] = interview;
    }

    return overrides;
  }
}

class EmailReviewDialog extends StatefulWidget {
  const EmailReviewDialog({
    super.key,
    required this.state,
    required this.applications,
    required this.onSave,
    required this.onDiscard,
    required this.onPersistDraft,
  });

  final ValueListenable<ReviewDialogState> state;
  final ValueListenable<List<Application>> applications;
  final Future<void> Function(EmailReviewItem item, ReviewDraft draft) onSave;
  final Future<void> Function(EmailReviewItem item, ReviewDraft draft) onDiscard;
  final Future<void> Function(EmailReviewItem item, ReviewDraft draft)
      onPersistDraft;

  @override
  State<EmailReviewDialog> createState() => _EmailReviewDialogState();
}

class _EmailReviewDialogState extends State<EmailReviewDialog> {
  final _subjectController = TextEditingController();
  final _summaryController = TextEditingController();
  final _companyController = TextEditingController();
  final _roleController = TextEditingController();
  final _jobIdController = TextEditingController();
  final _portalUrlController = TextEditingController();
  final _sourceController = TextEditingController();
  final _actionItemsController = TextEditingController();
  final _interviewStartController = TextEditingController();
  final _interviewEndController = TextEditingController();
  final _interviewTimezoneController = TextEditingController();
  final _interviewLocationController = TextEditingController();
  final _interviewMeetingController = TextEditingController();
  final _applicationLinkController = TextEditingController();
  final _applicationLinkFocusNode = FocusNode();
  final _applicationLinkFieldKey = GlobalKey();
  late final VoidCallback _applicationsListener;

  bool _relevant = true;
  bool _actionRequired = false;
  String? _statusValue;
  String? _selectedApplicationId;
  bool _forceNewApplication = false;
  String? _currentItemId;
  String? _lastLlmState;
  bool _dirty = false;
  bool _saving = false;
  bool _isHydrating = false;
  bool _showInterviewFields = false;
  bool _showLlmDetails = false;

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_markDirty);
    }
    _applicationsListener = _handleApplicationsChanged;
    widget.applications.addListener(_applicationsListener);
  }

  @override
  void dispose() {
    widget.applications.removeListener(_applicationsListener);
    for (final controller in _controllers) {
      controller.removeListener(_markDirty);
      controller.dispose();
    }
    _applicationLinkController.dispose();
    _applicationLinkFocusNode.dispose();
    super.dispose();
  }

  List<TextEditingController> get _controllers => [
        _subjectController,
        _summaryController,
        _companyController,
        _roleController,
        _jobIdController,
        _portalUrlController,
        _sourceController,
        _actionItemsController,
        _interviewStartController,
        _interviewEndController,
        _interviewTimezoneController,
        _interviewLocationController,
        _interviewMeetingController,
      ];

  void _markDirty() {
    if (_isHydrating || _dirty) {
      return;
    }
    if (!_dirty) {
      setState(() => _dirty = true);
    }
  }

  void _loadFromItem(EmailReviewItem item) {
    _isHydrating = true;
    _relevant = item.effectiveRelevant;
    _subjectController.text = item.effectiveSubject;
    _summaryController.text = item.effectiveSummary;
    _companyController.text = item.effectiveCompany ?? '';
    _roleController.text = item.effectiveRole ?? '';
    _jobIdController.text = item.effectiveJobId ?? '';
    _portalUrlController.text = item.effectivePortalUrl ?? '';
    _sourceController.text = item.effectiveSource;
    _actionRequired = item.effectiveActionRequired;
    _actionItemsController.text = item.effectiveActionItems.join('\n');
    _statusValue = item.effectiveStatus;

    final interview = item.effectiveInterview;
    _interviewStartController.text = _stringOrEmpty(interview['start']);
    _interviewEndController.text = _stringOrEmpty(interview['end']);
    _interviewTimezoneController.text = _stringOrEmpty(interview['timezone']);
    _interviewLocationController.text = _stringOrEmpty(interview['location']);
    _interviewMeetingController.text = _stringOrEmpty(interview['meetingUrl']);
    _showInterviewFields = _hasInterviewValues(interview);

    if (item.selectedApplicationId == '__new__') {
      _forceNewApplication = true;
      _selectedApplicationId = null;
    } else {
      _forceNewApplication = false;
      _selectedApplicationId = _resolveSelectedApplicationId(
        item,
        widget.applications.value,
      );
    }
    final selectedLabel = _applicationLabelForId(
      _selectedApplicationId,
      widget.applications.value,
    );
    if (_forceNewApplication) {
      _applicationLinkController.text = _createNewApplicationLabel;
    } else {
      _applicationLinkController.text = selectedLabel ?? '';
    }
    _dirty = false;
    _lastLlmState = item.llmState;
    _showLlmDetails = false;
    _isHydrating = false;
  }

  void _applyLlmDefaults(EmailReviewItem item) {
    if (item.llmState != 'ready') {
      return;
    }
    _isHydrating = true;
    if (_summaryController.text.trim().isEmpty) {
      _summaryController.text = item.effectiveSummary;
    }
    if (_companyController.text.trim().isEmpty &&
        (item.effectiveCompany ?? '').trim().isNotEmpty) {
      _companyController.text = item.effectiveCompany!;
    }
    if (_roleController.text.trim().isEmpty &&
        (item.effectiveRole ?? '').trim().isNotEmpty) {
      _roleController.text = item.effectiveRole!;
    }
    if (_jobIdController.text.trim().isEmpty &&
        (item.effectiveJobId ?? '').trim().isNotEmpty) {
      _jobIdController.text = item.effectiveJobId!;
    }
    if (_portalUrlController.text.trim().isEmpty &&
        (item.effectivePortalUrl ?? '').trim().isNotEmpty) {
      _portalUrlController.text = item.effectivePortalUrl!;
    }
    if ((_statusValue ?? '').trim().isEmpty &&
        (item.effectiveStatus ?? '').trim().isNotEmpty) {
      _statusValue = item.effectiveStatus;
    }
    if (_actionItemsController.text.trim().isEmpty &&
        item.effectiveActionItems.isNotEmpty) {
      _actionItemsController.text = item.effectiveActionItems.join('\n');
    }
    final interview = item.effectiveInterview;
    if (_interviewStartController.text.trim().isEmpty &&
        _stringOrEmpty(interview['start']).isNotEmpty) {
      _interviewStartController.text = _stringOrEmpty(interview['start']);
    }
    if (_interviewEndController.text.trim().isEmpty &&
        _stringOrEmpty(interview['end']).isNotEmpty) {
      _interviewEndController.text = _stringOrEmpty(interview['end']);
    }
    if (_interviewTimezoneController.text.trim().isEmpty &&
        _stringOrEmpty(interview['timezone']).isNotEmpty) {
      _interviewTimezoneController.text = _stringOrEmpty(interview['timezone']);
    }
    if (_interviewLocationController.text.trim().isEmpty &&
        _stringOrEmpty(interview['location']).isNotEmpty) {
      _interviewLocationController.text = _stringOrEmpty(interview['location']);
    }
    if (_interviewMeetingController.text.trim().isEmpty &&
        _stringOrEmpty(interview['meetingUrl']).isNotEmpty) {
      _interviewMeetingController.text =
          _stringOrEmpty(interview['meetingUrl']);
    }
    if (!_showInterviewFields && _hasInterviewValues(interview)) {
      _showInterviewFields = true;
    }
    _lastLlmState = item.llmState;
    _isHydrating = false;
  }

  void _handleApplicationsChanged() {
    if (!mounted) {
      return;
    }
    _syncApplicationLinkText(widget.applications.value);
    _bumpApplicationAutocomplete();
  }

  void _syncApplicationLinkText(List<Application> apps) {
    if (_applicationLinkFocusNode.hasFocus) {
      return;
    }
    if (_forceNewApplication) {
      if (_applicationLinkController.text != _createNewApplicationLabel) {
        _applicationLinkController.text = _createNewApplicationLabel;
      }
      return;
    }
    if (_selectedApplicationId == null) {
      return;
    }
    final label = _applicationLabelForId(_selectedApplicationId, apps);
    if (label != null && label.isNotEmpty) {
      if (_applicationLinkController.text != label) {
        _applicationLinkController.text = label;
      }
    }
  }

  void _bumpApplicationAutocomplete() {
    final value = _applicationLinkController.value;
    _applicationLinkController.value = value.copyWith(
      text: value.text,
      selection: value.selection,
      composing: TextRange.empty,
    );
  }

  Future<void> _pickInterviewDateTime(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text.trim());
    final baseDate = initial ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: baseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (pickedDate == null || !mounted) {
      return;
    }
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(baseDate),
    );
    if (pickedTime == null || !mounted) {
      return;
    }
    final combined = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    setState(() {
      controller.text = combined.toIso8601String();
      _dirty = true;
    });
  }

  ReviewDraft _buildDraft() {
    return ReviewDraft(
      relevant: _relevant,
      subject: _subjectController.text,
      summary: _summaryController.text,
      company: _companyController.text,
      role: _roleController.text,
      jobId: _jobIdController.text,
      portalUrl: _portalUrlController.text,
      status: _statusValue ?? '',
      source: _sourceController.text,
      actionRequired: _actionRequired,
      actionItemsText: _actionItemsController.text,
      interviewStart: _interviewStartController.text,
      interviewEnd: _interviewEndController.text,
      interviewTimezone: _interviewTimezoneController.text,
      interviewLocation: _interviewLocationController.text,
      interviewMeetingUrl: _interviewMeetingController.text,
      selectedApplicationId: _selectedApplicationId,
      forceNewApplication: _forceNewApplication,
    );
  }

  Future<void> _persistDraft(EmailReviewItem item) async {
    if (!_dirty) {
      return;
    }
    final draft = _buildDraft();
    await widget.onPersistDraft(item, draft);
    if (mounted) {
      setState(() => _dirty = false);
    }
  }

  Future<void> _handleSave(EmailReviewItem item) async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final draft = _buildDraft();
    await widget.onSave(item, draft);
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _handleDiscard(EmailReviewItem item) async {
    if (_saving) {
      return;
    }
    setState(() => _saving = true);
    final draft = _buildDraft();
    await widget.onDiscard(item, draft);
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<bool> _onWillPop(EmailReviewItem? item) async {
    if (item != null) {
      await _persistDraft(item);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReviewDialogState>(
      valueListenable: widget.state,
      builder: (context, state, _) {
        final maxHeight = MediaQuery.of(context).size.height * 0.85;
        final item = state.item;
        if (item != null) {
          final isNewItem = _currentItemId != item.id;
          if (isNewItem || !_dirty) {
            _currentItemId = item.id;
            _loadFromItem(item);
          } else if (_dirty &&
              item.llmState == 'ready' &&
              _lastLlmState != 'ready') {
            _applyLlmDefaults(item);
          } else {
            _lastLlmState = item.llmState;
          }
        }

        return WillPopScope(
          onWillPop: () => _onWillPop(item),
          child: Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 1040, maxHeight: maxHeight),
              child: SizedBox(
                height: maxHeight,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: item == null
                      ? _buildWaitingState(context, state)
                      : _buildContent(context, state, item),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaitingState(BuildContext context, ReviewDialogState state) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        Text('Review queue', style: textTheme.titleLarge),
        const SizedBox(height: 16),
        if (state.queueCount > 0) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            state.syncInProgress
                ? 'Emails are syncing and LLM is extracting...'
                : 'LLM is extracting details...',
            style: textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            '${state.queueCount} waiting in queue',
            style: textTheme.bodySmall,
          ),
        ] else if (state.waitingForNext) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text('Waiting for new emails...', style: textTheme.bodyMedium),
        ] else
          Text('No pending emails.', style: textTheme.bodyMedium),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    ReviewDialogState state,
    EmailReviewItem item,
  ) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final bodyText = item.cleanBodyText?.trim().isNotEmpty ?? false
        ? item.cleanBodyText!.trim()
        : (item.cleanBodyPreview ?? '');
    final bodyPreview = item.cleanBodyPreview ?? bodyText;
    final displayBody =
        bodyText.trim().isNotEmpty ? bodyText : bodyPreview.trim();
    final hasBody = displayBody.trim().isNotEmpty;

    final emailCard = _sectionCard(
      context,
      title: 'Email',
      icon: Icons.mail_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _subjectController,
            decoration: const InputDecoration(labelText: 'Subject'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _summaryController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Summary'),
          ),
          const SizedBox(height: 12),
          _metaLine(
            context,
            label: 'From',
            value: item.fromAddr,
            icon: Icons.alternate_email,
          ),
          const SizedBox(height: 6),
          _metaLine(
            context,
            label: 'To',
            value: item.toAddr,
            icon: Icons.forward_to_inbox,
          ),
          const SizedBox(height: 6),
          _metaLine(
            context,
            label: 'Received',
            value: dateFormat.format(item.date.toLocal()),
            icon: Icons.schedule,
          ),
        ],
      ),
    );

    final bodyCard = _sectionCard(
      context,
      title: 'Body (cleaned)',
      icon: Icons.article_outlined,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: 140,
            maxHeight: 420,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              hasBody ? displayBody : 'Body not available yet.',
              style: textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
        ),
      ),
    );

    final leftColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        emailCard,
        const SizedBox(height: 12),
        bodyCard,
      ],
    );

    final rightColumn = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildApplicationSection(context),
        const SizedBox(height: 12),
        _buildNextStepsSection(context),
        const SizedBox(height: 12),
        _buildInterviewSection(context),
        const SizedBox(height: 12),
        _buildLlmSection(context, item),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 860;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Review email',
                    style: textTheme.titleLarge,
                  ),
                ),
                if (state.queueCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text('${state.queueCount} in queue'),
                    ),
                  ),
                if (item.llmState.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text('LLM: ${item.llmState}'),
                    ),
                  ),
                IconButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 5, child: leftColumn),
                          const SizedBox(width: 12),
                          Expanded(flex: 4, child: rightColumn),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          leftColumn,
                          const SizedBox(height: 12),
                          rightColumn,
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text('Relevant', style: textTheme.labelMedium),
                      const SizedBox(width: 8),
                      Switch(
                        value: _relevant,
                        onChanged: (value) {
                          setState(() {
                            _relevant = value;
                            _dirty = true;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : () => _handleDiscard(item),
                  icon: const Icon(Icons.close),
                  label: const Text('Discard'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving || !_relevant
                      ? null
                      : () => _handleSave(item),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildLlmSection(BuildContext context, EmailReviewItem item) {
    final textTheme = Theme.of(context).textTheme;
    final hasDetails = (item.llmReason?.isNotEmpty ?? false) ||
        item.llmEvidence.isNotEmpty;
    return _sectionCard(
      context,
      title: 'LLM insights',
      icon: Icons.auto_awesome_outlined,
      trailing: hasDetails
          ? TextButton(
              onPressed: () {
                setState(() {
                  _showLlmDetails = !_showLlmDetails;
                });
              },
              child: Text(_showLlmDetails ? 'Hide details' : 'View details'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('State: ${item.llmState}', style: textTheme.bodySmall),
          if (item.llmCategory != null)
            Text('Category: ${item.llmCategory}',
                style: textTheme.bodySmall),
          if (item.llmConfidence != null)
            Text(
              'Confidence: ${(item.llmConfidence! * 100).toStringAsFixed(0)}%',
              style: textTheme.bodySmall,
            ),
          if (_showLlmDetails && hasDetails) ...[
            if (item.llmReason != null && item.llmReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Reason: ${item.llmReason}', style: textTheme.bodySmall),
            ],
            if (item.llmEvidence.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Evidence', style: textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final ev in item.llmEvidence)
                Text(
                  '- ${ev['field']} (${ev['source']}): ${ev['quote']}',
                  style: textTheme.bodySmall,
                ),
            ],
          ],
        ],
      ),
    );
  }
}

Widget _sectionCard(
  BuildContext context, {
  required String title,
  required Widget child,
  Widget? trailing,
  IconData? icon,
}) {
  final theme = Theme.of(context);
  final textTheme = theme.textTheme;
  final colorScheme = theme.colorScheme;
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(title, style: textTheme.titleMedium),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

Widget _metaLine(
  BuildContext context, {
  required String label,
  required String value,
  required IconData icon,
}) {
  final theme = Theme.of(context);
  final textTheme = theme.textTheme;
  final colorScheme = theme.colorScheme;
  return Row(
    children: [
      Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
      const SizedBox(width: 6),
      Text(
        '$label:',
        style: textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          value,
          style: textTheme.bodySmall,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

Widget _buildApplicationSection(BuildContext context) {
  final state = context.findAncestorStateOfType<_EmailReviewDialogState>();
  if (state == null) {
    return const SizedBox.shrink();
  }
  return _sectionCard(
    context,
    title: 'Application',
    icon: Icons.work_outline,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<List<Application>>(
          valueListenable: state.widget.applications,
          builder: (context, apps, _) {
            final options = [
              const _ApplicationOption.createNew(),
              for (final app in apps) _ApplicationOption.app(app),
            ];
            final selectedLabel = state._forceNewApplication
                ? _createNewApplicationLabel
                : (_applicationLabelForId(state._selectedApplicationId, apps) ??
                    '');
            return RawAutocomplete<_ApplicationOption>(
              textEditingController: state._applicationLinkController,
              focusNode: state._applicationLinkFocusNode,
              displayStringForOption: (option) => option.label,
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                final normalizedSelected = selectedLabel.toLowerCase();
                if (query.isEmpty ||
                    query == normalizedSelected ||
                    query == _createNewApplicationLabelLower) {
                  return options;
                }
                final matches = options
                    .where((option) => option.labelLower.contains(query))
                    .toList();
                if (matches.isEmpty) {
                  return [const _ApplicationOption.createNew()];
                }
                if (matches.first.isCreateNew) {
                  return matches;
                }
                return [const _ApplicationOption.createNew(), ...matches];
              },
              onSelected: (option) {
                state.setState(() {
                  if (option.isCreateNew) {
                    state._selectedApplicationId = null;
                    state._forceNewApplication = true;
                    state._applicationLinkController.text =
                        _createNewApplicationLabel;
                  } else {
                    state._selectedApplicationId = option.id;
                    state._forceNewApplication = false;
                    state._applicationLinkController.text = option.label;
                  }
                  state._dirty = true;
                });
              },
              fieldViewBuilder: (
                context,
                controller,
                focusNode,
                onFieldSubmitted,
              ) {
                return TextField(
                  key: state._applicationLinkFieldKey,
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Link to application',
                    hintText: 'Search applications',
                    suffixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => onFieldSubmitted(),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final theme = Theme.of(context);
                final textTheme = theme.textTheme;
                final colorScheme = theme.colorScheme;
                final itemStyle = textTheme.bodySmall?.copyWith(fontSize: 12) ??
                    const TextStyle(fontSize: 12);
                final renderBox = state._applicationLinkFieldKey.currentContext
                    ?.findRenderObject() as RenderBox?;
                final fieldWidth = renderBox?.size.width ?? 320;
                const dropdownHeight = 240.0;
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: fieldWidth,
                      height: dropdownHeight,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: options.length,
                        separatorBuilder: (_, __) =>
                            Divider(color: colorScheme.outlineVariant),
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          final isCreateNew = option.isCreateNew;
                          return ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: Icon(
                              isCreateNew
                                  ? Icons.add_circle_outline
                                  : Icons.work_outline,
                              size: 16,
                              color: isCreateNew
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            title: Text(
                              option.label,
                              style: itemStyle.copyWith(
                                color: isCreateNew
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: state._companyController,
                decoration: const InputDecoration(labelText: 'Company'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: state._roleController,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: state._statusValue,
                items: _statusItems(),
                decoration: const InputDecoration(labelText: 'Status'),
                onChanged: (value) {
                  state.setState(() {
                    state._statusValue = value;
                    state._dirty = true;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: state._sourceController,
                decoration: const InputDecoration(labelText: 'Source'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: state._jobIdController,
                decoration: const InputDecoration(labelText: 'Job ID'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: state._portalUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Portal URL'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildNextStepsSection(BuildContext context) {
  final state = context.findAncestorStateOfType<_EmailReviewDialogState>();
  if (state == null) {
    return const SizedBox.shrink();
  }
  final showActionItems = state._actionRequired;
  return _sectionCard(
    context,
    title: 'Next steps',
    icon: Icons.task_alt,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Action required'),
          value: state._actionRequired,
          onChanged: (value) {
            state.setState(() {
              state._actionRequired = value;
              state._dirty = true;
            });
          },
        ),
        if (showActionItems) ...[
          const SizedBox(height: 8),
          TextField(
            controller: state._actionItemsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Action items (one per line)',
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _buildInterviewSection(BuildContext context) {
  final state = context.findAncestorStateOfType<_EmailReviewDialogState>();
  if (state == null) {
    return const SizedBox.shrink();
  }
  return _sectionCard(
    context,
    title: 'Interview',
    icon: Icons.event_available_outlined,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include interview details'),
          value: state._showInterviewFields,
          onChanged: (value) {
            state.setState(() {
              state._showInterviewFields = value;
              state._dirty = true;
            });
          },
        ),
        if (state._showInterviewFields) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: state._interviewStartController,
                  readOnly: true,
                  onTap: () =>
                      state._pickInterviewDateTime(state._interviewStartController),
                  decoration: const InputDecoration(
                    labelText: 'Start (ISO 8601)',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: state._interviewEndController,
                  readOnly: true,
                  onTap: () =>
                      state._pickInterviewDateTime(state._interviewEndController),
                  decoration: const InputDecoration(
                    labelText: 'End (ISO 8601)',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: state._interviewTimezoneController,
                  decoration: const InputDecoration(labelText: 'Timezone'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: state._interviewLocationController,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: state._interviewMeetingController,
            decoration: const InputDecoration(labelText: 'Meeting URL'),
          ),
        ],
      ],
    ),
  );
}

const _createNewApplicationLabel = 'Create new application';
const _createNewApplicationLabelLower = 'create new application';

class _ApplicationOption {
  final String? id;
  final String label;
  final bool isCreateNew;
  final String labelLower;

  const _ApplicationOption._({
    required this.id,
    required this.label,
    required this.isCreateNew,
    required this.labelLower,
  });

  const _ApplicationOption.createNew()
      : id = null,
        label = _createNewApplicationLabel,
        isCreateNew = true,
        labelLower = _createNewApplicationLabelLower;

  factory _ApplicationOption.app(Application app) {
    final label = '${app.company} - ${app.role}';
    return _ApplicationOption._(
      id: app.id,
      label: label,
      isCreateNew: false,
      labelLower: label.toLowerCase(),
    );
  }
}

String? _applicationLabelForId(
  String? id,
  List<Application> applications,
) {
  if (id == null || id.trim().isEmpty) {
    return null;
  }
  for (final app in applications) {
    if (app.id == id) {
      return '${app.company} - ${app.role}';
    }
  }
  return null;
}

List<DropdownMenuItem<String?>> _statusItems() {
  const statuses = [
    '',
    'applied',
    'under_review',
    'assessment',
    'interview',
    'offer',
    'rejected',
    'other',
  ];
  return [
    for (final status in statuses)
      DropdownMenuItem<String?>(
        value: status.isEmpty ? null : status,
        child: Text(status.isEmpty ? 'Use extracted' : status),
      ),
  ];
}

String? _resolveSelectedApplicationId(
  EmailReviewItem item,
  List<Application> applications,
) {
  final candidate = item.selectedApplicationId ?? item.suggestedApplicationId;
  if (candidate == null || candidate.trim().isEmpty) {
    return null;
  }
  if (candidate == '__new__') {
    return null;
  }
  final exists = applications.any((app) => app.id == candidate);
  if (exists) {
    return candidate;
  }
  return null;
}

String _stringOrEmpty(Object? value) {
  if (value is String) {
    return value;
  }
  return '';
}

bool _hasInterviewValues(Map<String, dynamic> interview) {
  return _stringOrEmpty(interview['start']).trim().isNotEmpty ||
      _stringOrEmpty(interview['end']).trim().isNotEmpty ||
      _stringOrEmpty(interview['timezone']).trim().isNotEmpty ||
      _stringOrEmpty(interview['location']).trim().isNotEmpty ||
      _stringOrEmpty(interview['meetingUrl']).trim().isNotEmpty;
}

List<String> _parseLines(String value) {
  return value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}
