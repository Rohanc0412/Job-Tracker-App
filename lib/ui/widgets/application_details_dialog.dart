import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/application.dart';
import '../../data/models/email_event.dart';
import '../../domain/status/status_types.dart';
import '../../services/body_retrieval_service.dart';

class ApplicationDetailsDialog extends StatefulWidget {
  final Application application;
  final List<EmailEvent> emailEvents;
  final Future<void> Function(Application updated) onSave;
  final Future<bool> Function(EmailEvent event) onUnlink;

  const ApplicationDetailsDialog({
    super.key,
    required this.application,
    required this.emailEvents,
    required this.onSave,
    required this.onUnlink,
  });

  @override
  State<ApplicationDetailsDialog> createState() =>
      _ApplicationDetailsDialogState();
}

class _ApplicationDetailsDialogState extends State<ApplicationDetailsDialog> {
  final _companyController = TextEditingController();
  final _roleController = TextEditingController();
  final _idController = TextEditingController();
  final _jobIdController = TextEditingController();
  final _portalUrlController = TextEditingController();
  final _contactController = TextEditingController();
  final _accountController = TextEditingController();
  final _sourceController = TextEditingController();
  final _confidenceController = TextEditingController();
  final _appliedOnController = TextEditingController();
  final _lastUpdatedController = TextEditingController();
  final _nextStepController = TextEditingController();
  final _nextStepAtController = TextEditingController();
  final _bodyService = BodyRetrievalService();

  late ApplicationStatus _status;
  late List<EmailEvent> _emails;
  bool _saving = false;
  final Map<String, String?> _emailBodies = {};
  final Set<String> _expandedEmails = {};
  final Set<String> _loadingEmails = {};

  @override
  void initState() {
    super.initState();
    final app = widget.application;
    _idController.text = app.id;
    _companyController.text = app.company;
    _roleController.text = app.role;
    _jobIdController.text = app.jobId ?? '';
    _portalUrlController.text = app.portalUrl ?? '';
    _contactController.text = app.contact ?? '';
    _accountController.text = app.account;
    _sourceController.text = app.source;
    _confidenceController.text = app.confidence.toString();
    _appliedOnController.text = app.appliedOn.toIso8601String();
    _lastUpdatedController.text = app.lastUpdated.toIso8601String();
    _nextStepController.text = app.nextStep ?? '';
    _nextStepAtController.text =
        app.nextStepAt?.toIso8601String() ?? '';
    _status = app.status;
    _emails = List<EmailEvent>.from(widget.emailEvents);
  }

  @override
  void dispose() {
    _companyController.dispose();
    _roleController.dispose();
    _idController.dispose();
    _jobIdController.dispose();
    _portalUrlController.dispose();
    _contactController.dispose();
    _accountController.dispose();
    _sourceController.dispose();
    _confidenceController.dispose();
    _appliedOnController.dispose();
    _lastUpdatedController.dispose();
    _nextStepController.dispose();
    _nextStepAtController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(TextEditingController controller) async {
    final initial = DateTime.tryParse(controller.text.trim());
    final baseDate = initial ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: baseDate,
      firstDate: DateTime(2000),
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
    });
  }

  DateTime? _parseDate(String value, {required bool required}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return required ? null : null;
    }
    return DateTime.tryParse(trimmed);
  }

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  Future<void> _toggleEmailBody(EmailEvent email) async {
    final id = email.id;
    if (_expandedEmails.contains(id)) {
      setState(() => _expandedEmails.remove(id));
      return;
    }
    setState(() => _expandedEmails.add(id));
    if (_emailBodies.containsKey(id) || _loadingEmails.contains(id)) {
      return;
    }
    setState(() => _loadingEmails.add(id));
    try {
      final body = await _bodyService.getFullBody(
        rawBodyText: email.rawBodyText,
        rawBodyPath: email.rawBodyPath,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _emailBodies[id] = body;
        _loadingEmails.remove(id);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingEmails.remove(id));
    }
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

  InputDecoration _fieldDecoration(
    BuildContext context,
    String label, {
    String? helperText,
    Widget? suffixIcon,
    String? suffixText,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      isDense: true,
      filled: true,
      fillColor: colorScheme.surfaceVariant.withOpacity(0.35),
      suffixIcon: suffixIcon,
      suffixText: suffixText,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _statusColor(_status, colorScheme);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _companyController,
        _roleController,
      ]),
      builder: (context, _) {
        final company = _companyController.text.trim();
        final role = _roleController.text.trim();
        final subtitle = [
          if (company.isNotEmpty) company,
          if (role.isNotEmpty) role,
        ].join(' - ');
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Application details',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.16),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: statusColor.withOpacity(0.35)),
              ),
              child: Text(
                _status.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSave() async {
    if (_saving) {
      return;
    }
    final company = _companyController.text.trim();
    final role = _roleController.text.trim();
    final account = _accountController.text.trim();
    final source = _sourceController.text.trim();
    if (company.isEmpty || role.isEmpty || account.isEmpty || source.isEmpty) {
      _showError('Company, role, account, and source are required.');
      return;
    }
    final confidence = int.tryParse(_confidenceController.text.trim());
    if (confidence == null || confidence < 0 || confidence > 100) {
      _showError('Confidence must be a number between 0 and 100.');
      return;
    }
    final appliedOn = _parseDate(_appliedOnController.text, required: true);
    final lastUpdated = _parseDate(_lastUpdatedController.text, required: true);
    if (appliedOn == null || lastUpdated == null) {
      _showError('Applied on and last updated must be valid dates.');
      return;
    }
    final nextStepAt =
        _parseDate(_nextStepAtController.text, required: false);
    if (_nextStepAtController.text.trim().isNotEmpty && nextStepAt == null) {
      _showError('Next step date must be a valid date.');
      return;
    }

    final updated = widget.application.copyWith(
      company: company,
      role: role,
      jobId: _optionalText(_jobIdController),
      portalUrl: _optionalText(_portalUrlController),
      contact: _optionalText(_contactController),
      account: account,
      source: source,
      confidence: confidence,
      appliedOn: appliedOn,
      lastUpdated: lastUpdated,
      status: _status,
      nextStep: _optionalText(_nextStepController),
      nextStepAt: nextStepAt,
    );

    setState(() => _saving = true);
    try {
      await widget.onSave(updated);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      _showError('Save failed: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _handleUnlink(EmailEvent event) async {
    final confirmed = await _confirmUnlink(event);
    if (!confirmed) {
      return;
    }
    try {
      final unlinked = await widget.onUnlink(event);
      if (!mounted) {
        return;
      }
      if (unlinked) {
        setState(() {
          _emails.removeWhere((email) => email.id == event.id);
        });
        _showMessage('Email moved to review queue.');
      }
    } catch (error) {
      _showError('Unlink failed: $error');
    }
  }

  Future<bool> _confirmUnlink(EmailEvent event) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Unlink email'),
              content: Text(
                'Move this email to the review queue?\n\n${event.subject}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Unlink'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 980, maxHeight: maxHeight),
        child: SizedBox(
          height: maxHeight,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildHeader(context),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _sectionCard(
                          context,
                          title: 'Details',
                          subtitle: 'Update application fields',
                          child: _buildDetailsForm(context),
                        ),
                        const SizedBox(height: 16),
                        _sectionCard(
                          context,
                          title: 'Linked emails',
                          subtitle: '${_emails.length} messages',
                          child: _buildEmailList(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _handleSave,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsForm(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 760;
          final full = constraints.maxWidth;
          final half = isWide ? (constraints.maxWidth - 12) / 2 : full;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: full,
                child: TextField(
                  controller: _idController,
                  readOnly: true,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  decoration: _fieldDecoration(
                    context,
                    'Application ID',
                  ),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _companyController,
                  decoration: _fieldDecoration(context, 'Company'),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _roleController,
                  decoration: _fieldDecoration(context, 'Role'),
                ),
              ),
              SizedBox(
                width: half,
                child: DropdownButtonFormField<ApplicationStatus>(
                  value: _status,
                  items: [
                    for (final status in ApplicationStatus.values)
                      DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() => _status = value);
                  },
                  decoration: _fieldDecoration(context, 'Status'),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _confidenceController,
                  keyboardType: TextInputType.number,
                  decoration: _fieldDecoration(
                    context,
                    'Confidence',
                    suffixText: '%',
                  ),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _accountController,
                  decoration: _fieldDecoration(context, 'Account'),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _sourceController,
                  decoration: _fieldDecoration(context, 'Source'),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _jobIdController,
                  decoration: _fieldDecoration(context, 'Job ID'),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _portalUrlController,
                  keyboardType: TextInputType.url,
                  decoration: _fieldDecoration(context, 'Portal URL'),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _contactController,
                  decoration: _fieldDecoration(context, 'Contact'),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _nextStepController,
                  decoration: _fieldDecoration(context, 'Next step'),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _nextStepAtController,
                  readOnly: true,
                  onTap: () => _pickDateTime(_nextStepAtController),
                  decoration: _fieldDecoration(
                    context,
                    'Next step at',
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: half,
                child: TextField(
                  controller: _appliedOnController,
                  readOnly: true,
                  onTap: () => _pickDateTime(_appliedOnController),
                  decoration: _fieldDecoration(
                    context,
                    'Applied on',
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
              ),
              SizedBox(
                width: full,
                child: TextField(
                  controller: _lastUpdatedController,
                  readOnly: true,
                  onTap: () => _pickDateTime(_lastUpdatedController),
                  decoration: _fieldDecoration(
                    context,
                    'Last updated',
                    suffixIcon: const Icon(Icons.calendar_today_outlined),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildEmailList(BuildContext context) {
    if (_emails.isEmpty) {
      return Text(
        'No linked emails',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final dateFormat = DateFormat('MMM d, yyyy h:mm a');
    return Column(
      children: [
        for (final email in _emails) ...[
          _EmailCard(
            email: email,
            dateFormat: dateFormat,
            isExpanded: _expandedEmails.contains(email.id),
            isLoading: _loadingEmails.contains(email.id),
            bodyText: _emailBodies[email.id],
            onToggleBody: () => _toggleEmailBody(email),
            onUnlink: () => _handleUnlink(email),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _EmailCard extends StatelessWidget {
  final EmailEvent email;
  final DateFormat dateFormat;
  final bool isExpanded;
  final bool isLoading;
  final String? bodyText;
  final VoidCallback onToggleBody;
  final VoidCallback onUnlink;

  const _EmailCard({
    required this.email,
    required this.dateFormat,
    required this.isExpanded,
    required this.isLoading,
    required this.bodyText,
    required this.onToggleBody,
    required this.onUnlink,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bodyAvailable = (bodyText ?? '').trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  email.subject,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: onUnlink,
                icon: const Icon(Icons.link_off, size: 16),
                label: const Text('Unlink'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.alternate_email,
                size: 14,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  email.fromAddr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            dateFormat.format(email.date),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
          if (email.llmSummary != null &&
              email.llmSummary!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              email.llmSummary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          InkWell(
            onTap: onToggleBody,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isExpanded ? 'Hide body' : 'View body',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: isLoading
                  ? Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                    )
                  : SelectableText(
                      bodyAvailable ? bodyText! : 'Body content unavailable.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _sectionCard(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget child,
}) {
  final theme = Theme.of(context);
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
