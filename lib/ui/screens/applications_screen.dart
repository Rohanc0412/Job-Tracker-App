import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/db/db.dart';
import '../../data/models/application.dart';
import '../../data/models/email_event.dart';
import '../../data/models/email_review_item.dart';
import '../../data/repo/application_repo.dart';
import '../../data/repo/email_event_repo.dart';
import '../../data/repo/email_review_repo.dart';
import '../../data/repo/sqlite_application_repo.dart';
import '../../domain/status/status_types.dart';
import '../../services/data_refresh_bus.dart';
import '../../services/email_review_save_service.dart';
import '../widgets/app_table.dart';
import '../widgets/application_details_dialog.dart';
import '../widgets/email_review_dialog.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

class ApplicationsScreen extends StatefulWidget {
  final ApplicationRepo repo;
  final ValueListenable<int> refreshListenable;

  ApplicationsScreen({
    super.key,
    ApplicationRepo? repo,
    ValueListenable<int>? refreshListenable,
  })  : repo = repo ?? SqliteApplicationRepo(AppDatabase.instance),
        refreshListenable = refreshListenable ?? DataRefreshBus.notifier;

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends State<ApplicationsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late Future<void> _loadFuture;
  List<Application> _applications = [];
  List<Application> _visibleApplications = [];
  Application? _selected;
  String _searchQuery = '';
  String? _errorMessage;
  late final VoidCallback _refreshListener;
  late final EmailReviewRepo _reviewRepo;
  late final EmailReviewSaveService _reviewSaveService;
  final EmailEventRepo _emailEventRepo = EmailEventRepo(AppDatabase.instance);
  final List<EmailReviewItem> _reviewQueue = [];
  final ValueNotifier<ReviewDialogState> _reviewDialogState =
      ValueNotifier(ReviewDialogState.empty());
  final ValueNotifier<List<Application>> _applicationsNotifier =
      ValueNotifier<List<Application>>([]);
  bool _reviewDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _reviewRepo = EmailReviewRepo(AppDatabase.instance);
    _reviewSaveService = EmailReviewSaveService(AppDatabase.instance);
    _loadFuture = _loadApplications();
    _refreshListener = () {
      setState(() {
        _loadFuture = _loadApplications();
      });
    };
    widget.refreshListenable.addListener(_refreshListener);
  }

  @override
  void dispose() {
    widget.refreshListenable.removeListener(_refreshListener);
    _scrollController.dispose();
    _searchController.dispose();
    _reviewDialogState.dispose();
    _applicationsNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadApplications() async {
    try {
      _errorMessage = null;
      final apps = await widget.repo.listApplications();
      final reviewQueue = await _reviewRepo.listPending();
      if (!mounted) {
        return;
      }
      setState(() {
        _applications = apps;
        _reviewQueue
          ..clear()
          ..addAll(reviewQueue);
      });
      _applicationsNotifier.value = List<Application>.from(apps);
      await _applySearch();
      _updateReviewDialogState();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    }
  }

  Future<void> _refreshReviewQueue() async {
    final reviewQueue = await _reviewRepo.listPending();
    if (!mounted) {
      return;
    }
    setState(() {
      _reviewQueue
        ..clear()
        ..addAll(reviewQueue);
    });
    _updateReviewDialogState();
  }

  Future<void> _applySearch() async {
    final tokens = _tokenizeQuery(_searchQuery);
    final filteredApps = _filterApplications(_applications, tokens);
    Application? nextSelected = _selected;
    if (nextSelected == null ||
        !filteredApps.any((app) => app.id == nextSelected!.id)) {
      nextSelected = filteredApps.isNotEmpty ? filteredApps.first : null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _visibleApplications = filteredApps;
      _selected = nextSelected;
    });
  }

  void _onSearchChanged(String value) {
    _searchQuery = value;
    _applySearch();
  }

  List<String> _tokenizeQuery(String value) {
    return value
        .toLowerCase()
        .trim()
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList();
  }

  bool _matchesTokens(String haystack, List<String> tokens) {
    if (tokens.isEmpty) {
      return true;
    }
    return tokens.every(haystack.contains);
  }

  List<Application> _filterApplications(
    List<Application> apps,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) {
      return apps;
    }
    return apps.where((app) {
      final haystack = [
        app.company,
        app.role,
        app.account,
        app.source,
        app.status.label,
        app.jobId ?? '',
        app.portalUrl ?? '',
      ].join(' ').toLowerCase();
      return _matchesTokens(haystack, tokens);
    }).toList();
  }

  Future<void> _openDetails(Application app) async {
    final emails = await _emailEventRepo.listForApplication(app.id);
    if (!mounted) {
      return;
    }
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return ApplicationDetailsDialog(
          application: app,
          emailEvents: emails,
          onSave: _handleApplicationSave,
          onUnlink: _handleUnlinkEmail,
        );
      },
    );
  }

  Future<void> _handleApplicationSave(Application updated) async {
    await widget.repo.upsert(updated);
    await _loadApplications();
    DataRefreshBus.notify();
  }

  Future<bool> _handleUnlinkEmail(EmailEvent event) async {
    await _emailEventRepo.unlinkToReview(event);
    await _refreshReviewQueue();
    DataRefreshBus.notify();
    return true;
  }

  void _updateReviewDialogState() {
    EmailReviewItem? readyItem;
    for (final item in _reviewQueue) {
      if (item.llmState == 'ready') {
        readyItem = item;
        break;
      }
    }
    if (readyItem == null) {
      for (final item in _reviewQueue) {
        if (item.llmState == 'failed') {
          readyItem = item;
          break;
        }
      }
    }
    _reviewDialogState.value = ReviewDialogState(
      item: readyItem,
      queueCount: _reviewQueue.length,
      syncInProgress: false,
      syncComplete: false,
    );
  }

  void _openReviewDialog() {
    if (!mounted || _reviewDialogOpen) {
      return;
    }
    _reviewDialogOpen = true;
    _updateReviewDialogState();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return EmailReviewDialog(
          state: _reviewDialogState,
          applications: _applicationsNotifier,
          onSave: _handleReviewSave,
          onDiscard: _handleReviewDiscard,
          onPersistDraft: _persistReviewDraft,
        );
      },
    ).whenComplete(() {
      _reviewDialogOpen = false;
    });
  }

  Future<void> _persistReviewDraft(
    EmailReviewItem item,
    ReviewDraft draft,
  ) async {
    final overrides = draft.toOverridesMap();
    final storedSelection =
        draft.forceNewApplication ? '__new__' : draft.selectedApplicationId;
    await _reviewRepo.updateUserOverrides(
      item.id,
      overrides,
      selectedApplicationId: storedSelection,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      final index = _reviewQueue.indexWhere((entry) => entry.id == item.id);
      if (index != -1) {
        _reviewQueue[index] = item.copyWith(
          userOverrides: overrides,
          selectedApplicationId: storedSelection,
          updatedAt: DateTime.now().toUtc(),
        );
      }
    });
    _updateReviewDialogState();
  }

  Future<void> _handleReviewSave(
    EmailReviewItem item,
    ReviewDraft draft,
  ) async {
    final overrides = draft.toOverridesMap();
    final selectedApplicationId = draft.selectedApplicationId;
    final storedSelection =
        draft.forceNewApplication ? '__new__' : selectedApplicationId;
    try {
      await _reviewRepo.updateUserOverrides(
        item.id,
        overrides,
        selectedApplicationId: storedSelection,
      );
      final updatedItem = item.copyWith(
        userOverrides: overrides,
        selectedApplicationId: storedSelection,
        updatedAt: DateTime.now().toUtc(),
      );
      await _reviewSaveService.saveReview(
        item: updatedItem,
        overrides: overrides,
        selectedApplicationId: selectedApplicationId,
        forceNewApplication: draft.forceNewApplication,
      );
      await _reviewRepo.markReviewState(item.id, 'saved');
      if (!mounted) {
        return;
      }
      _removeReviewItem(item.id);
      DataRefreshBus.notify();
      await _loadApplications();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Save failed: $error');
    }
  }

  Future<void> _handleReviewDiscard(
    EmailReviewItem item,
    ReviewDraft draft,
  ) async {
    final overrides = draft.toOverridesMap();
    final storedSelection =
        draft.forceNewApplication ? '__new__' : draft.selectedApplicationId;
    try {
      await _reviewRepo.updateUserOverrides(
        item.id,
        overrides,
        selectedApplicationId: storedSelection,
      );
      await _reviewRepo.markReviewState(item.id, 'discarded');
      if (!mounted) {
        return;
      }
      _removeReviewItem(item.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack('Discard failed: $error');
    }
  }

  void _removeReviewItem(String id) {
    setState(() {
      _reviewQueue.removeWhere((item) => item.id == id);
    });
    _updateReviewDialogState();
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            const Sidebar(selectedIndex: 1),
            Expanded(
              child: Column(
                children: [
                  Topbar(
                    title: 'Applications',
                    subtitle: 'Manage your pipeline',
                    showSearch: true,
                    showSync: false,
                    reviewCount: _reviewQueue.length,
                    onReview: _openReviewDialog,
                    searchController: _searchController,
                    onSearchChanged: _onSearchChanged,
                  ),
                  Expanded(
                    child: FutureBuilder<void>(
                      future: _loadFuture,
                      builder: (context, snapshot) {
                        if (_errorMessage != null) {
                          return Center(
                            child: Text(
                              'Failed to load applications',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.error,
                                  ),
                            ),
                          );
                        }
                        if (_visibleApplications.isEmpty &&
                            snapshot.connectionState !=
                                ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return Scrollbar(
                          controller: _scrollController,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Double-click an application to edit details '
                                  'and unlink emails.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                AppTable(
                                  applications: _visibleApplications,
                                  selectedId: _selected?.id,
                                  onSelected: (app) {
                                    setState(() => _selected = app);
                                  },
                                  onOpenDetails: _openDetails,
                                  maxBodyHeight: 520,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
