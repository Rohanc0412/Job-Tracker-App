import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/db/db.dart';
import '../../data/models/activity_item.dart';
import '../../data/models/application.dart';
import '../../data/models/email_review_item.dart';
import '../../data/repo/application_repo.dart';
import '../../data/repo/email_review_repo.dart';
import '../../data/repo/sqlite_application_repo.dart';
import '../../domain/status/status_types.dart';
import '../../services/data_refresh_bus.dart';
import '../../services/email_review_save_service.dart';
import '../../services/gmail_settings.dart';
import '../../services/gmail_sync_service.dart';
import '../../services/local_llm_settings.dart';
import '../../services/secrets_store.dart';
import '../../services/settings_store.dart';
import '../../services/app_data_paths.dart';
import '../widgets/activity_tabs.dart';
import '../widgets/app_table.dart';
import '../widgets/details_panel.dart';
import '../widgets/email_review_dialog.dart';
import '../widgets/kpi_card.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

class DashboardScreen extends StatefulWidget {
  final ApplicationRepo repo;
  final ValueListenable<int> refreshListenable;

  DashboardScreen({
    super.key,
    ApplicationRepo? repo,
    ValueListenable<int>? refreshListenable,
  })  : repo = repo ?? SqliteApplicationRepo(AppDatabase.instance),
        refreshListenable = refreshListenable ?? DataRefreshBus.notifier;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  late Future<void> _loadFuture;
  List<Application> _applications = [];
  List<Application> _visibleApplications = [];
  List<ActivityItem> _updates = [];
  List<ActivityItem> _visibleUpdates = [];
  List<ActivityItem> _upcoming = [];
  List<ActivityItem> _visibleUpcoming = [];
  List<ActivityItem> _timeline = [];
  Application? _selected;
  String? _errorMessage;
  int _upcomingDays = 14;
  bool _syncing = false;
  String? _syncStatus;
  bool _syncComplete = false;
  bool _syncCompleteNotified = false;
  String _searchQuery = '';
  late final VoidCallback _refreshListener;
  late final EmailReviewRepo _reviewRepo;
  late final EmailReviewSaveService _reviewSaveService;
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
    _loadFuture = _loadDashboard();
    _refreshListener = () {
      setState(() {
        _loadFuture = _loadDashboard();
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

  Future<void> _loadDashboard() async {
    try {
      _errorMessage = null;
      final apps = await widget.repo.listApplications();
      final updates = await widget.repo.listRecentUpdates();
      final upcoming =
          await widget.repo.listUpcomingInterviews(days: _upcomingDays);
      if (!mounted) {
        return;
      }
      setState(() {
        _applications = apps;
        _updates = updates;
        _upcoming = upcoming;
      });
      _applicationsNotifier.value = List<Application>.from(apps);
      await _applySearch(forceTimeline: true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
    }
  }

  Future<void> _applySearch({bool forceTimeline = false}) async {
    final tokens = _tokenizeQuery(_searchQuery);
    final appById = {for (final app in _applications) app.id: app};
    final filteredApps = _filterApplications(_applications, tokens);
    final filteredUpdates = _filterActivities(_updates, tokens, appById);
    final filteredUpcoming = _filterActivities(_upcoming, tokens, appById);

    Application? nextSelected = _selected;
    if (nextSelected == null ||
        !filteredApps.any((app) => app.id == nextSelected!.id)) {
      nextSelected = filteredApps.isNotEmpty ? filteredApps.first : null;
    }
    final selectionChanged = nextSelected?.id != _selected?.id;

    if (!mounted) {
      return;
    }
    setState(() {
      _visibleApplications = filteredApps;
      _visibleUpdates = filteredUpdates;
      _visibleUpcoming = filteredUpcoming;
      _selected = nextSelected;
      if (selectionChanged || nextSelected == null) {
        _timeline = [];
      }
    });

    if ((selectionChanged || forceTimeline) && nextSelected != null) {
      await _loadTimeline();
    }
  }

  Future<void> _loadTimeline() async {
    final selected = _selected;
    if (selected == null) {
      if (mounted) {
        setState(() => _timeline = []);
      }
      return;
    }
    final selectedId = selected.id;
    final timeline = await widget.repo.listTimeline(selectedId);
    if (!mounted || _selected?.id != selectedId) {
      return;
    }
    setState(() => _timeline = timeline);
  }

  Future<void> _startGmailSync() async {
    if (_syncing) {
      return;
    }
    final settings = SettingsStore.instance;
    final emailValue = settings.get<String>(GmailSettingsKeys.email);
    final folder =
        settings.get<String>(GmailSettingsKeys.folder) ?? 'INBOX';
    final storeRawBody = true;
    final startDateValue = settings.get<String>(GmailSettingsKeys.startDate);
    final startDate =
        startDateValue == null ? null : DateTime.tryParse(startDateValue);

    if (emailValue == null || emailValue.trim().isEmpty) {
      _showSyncSnack('Set a Gmail address in Settings.');
      return;
    }
    final email = emailValue.trim();

    final creds = await SecretsStore().readGmailCredentials();
    if (creds == null || creds.appPassword.trim().isEmpty) {
      _showSyncSnack('Add a Gmail app password in Settings.');
      return;
    }

    if (startDate == null) {
      final db = AppDatabase.instance;
      await db.open();
      final rows = db.rawDb.select(
        'SELECT COUNT(*) AS count FROM sync_state '
        'WHERE provider = ? AND accountLabel = ? AND folder = ?;',
        ['gmail', email, folder],
      );
      final count = (rows.first['count'] as num).toInt();
      if (count == 0) {
        _showSyncSnack('Pick a start date in Settings for the first sync.');
        return;
      }
    }

    final dbPath = await AppDataPaths.databasePath();
    final rawBodiesDir = (await AppDataPaths.rawBodiesDir()).path;
    final logFilePath = await AppDataPaths.logFilePath();
    final skipSeed = SettingsStore.instance.get<bool>('skipSeed') ?? false;
    final llmModelId =
        settings.get<String>(LocalLlmSettingsKeys.modelId) ??
            LocalLlmDefaults.modelId;
    final isOpenAiModel = llmModelId == kOpenAiModelId;
    var llmBaseUrl =
        settings.get<String>(LocalLlmSettingsKeys.baseUrl) ??
            (isOpenAiModel
                ? LocalLlmDefaults.openAiBaseUrl
                : LocalLlmDefaults.baseUrl);
    if (isOpenAiModel &&
        llmBaseUrl.trim() == LocalLlmDefaults.baseUrl) {
      llmBaseUrl = LocalLlmDefaults.openAiBaseUrl;
    }
    String? llmApiKey;
    if (isOpenAiModel) {
      llmApiKey = await SecretsStore().readOpenAiApiKey();
      if (llmApiKey == null || llmApiKey.trim().isEmpty) {
        _showSyncSnack('Add an OpenAI API key in Settings.');
        return;
      }
    }
    final llmTimeoutMs =
        settings.get<int>(LocalLlmSettingsKeys.requestTimeoutMs) ??
            LocalLlmDefaults.requestTimeoutMs;
    final llmMaxInputChars =
        settings.get<int>(LocalLlmSettingsKeys.maxInputChars) ??
            LocalLlmDefaults.maxInputChars;
    final config = GmailSyncConfig(
      email: email,
      appPassword: creds.appPassword,
      folder: folder,
      startDate: startDate,
      storeRawBody: storeRawBody,
      maxRawBodyBytes: 256 * 1024,
      hardCapBytes: 1024 * 1024,
      dbPath: dbPath,
      rawBodiesDir: rawBodiesDir,
      skipSeed: skipSeed,
      llmBaseUrl: llmBaseUrl,
      llmModelId: llmModelId,
      llmRequestTimeoutMs: llmTimeoutMs,
      llmMaxInputChars: llmMaxInputChars,
      llmApiKey: llmApiKey,
      logFilePath: logFilePath,
    );

    setState(() {
      _syncing = true;
      _syncStatus = 'Syncing...';
      _syncComplete = false;
      _syncCompleteNotified = false;
    });
    _updateReviewDialogState();

    final service = GmailSyncService();
    var syncFailed = false;
    final session = service.startSync(config);
    session.progress.listen((progress) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncStatus = progress.message;
      });
      if (progress.stage == 'done' &&
          progress.message.toLowerCase().startsWith('sync failed')) {
        syncFailed = true;
        _showSyncSnack(progress.message);
      }
    }, onError: (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _syncStatus = null;
        _syncComplete = false;
      });
      _updateReviewDialogState();
      _showSyncSnack('Sync failed: $error');
    }, onDone: () async {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _syncStatus = null;
        _syncComplete = !syncFailed;
      });
      _updateReviewDialogState();
      if (!syncFailed) {
        _maybeCloseReviewDialog();
      }
    });

    session.reviewEvents.listen((event) async {
      await _handleReviewEvent(event);
    });
  }

  void _showSyncSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
      syncInProgress: _syncing,
      syncComplete: _syncComplete,
    );
  }

  Future<void> _handleReviewEvent(GmailSyncReviewEvent event) async {
    final item = await _reviewRepo.findById(event.reviewId);
    if (item == null || item.reviewState != 'pending') {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      final index = _reviewQueue.indexWhere((entry) => entry.id == item.id);
      if (index == -1) {
        _reviewQueue.add(item);
      } else {
        _reviewQueue[index] = item;
      }
    });
    _updateReviewDialogState();
    if (!_reviewDialogOpen) {
      _openReviewDialog();
    }
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
      if (mounted && _reviewQueue.isNotEmpty) {
        _showReviewResumeSnack();
      }
    });
  }

  void _showReviewResumeSnack() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Review paused (${_reviewQueue.length} remaining).'),
        action: SnackBarAction(
          label: 'Resume',
          onPressed: _openReviewDialog,
        ),
      ),
    );
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
      await _refreshApplicationsQuick();
      _removeReviewItem(item.id);
      DataRefreshBus.notify();
      await _loadDashboard();
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSyncSnack('Save failed: $error');
    }
  }

  Future<void> _refreshApplicationsQuick() async {
    try {
      final apps = await widget.repo.listApplications();
      if (!mounted) {
        return;
      }
      setState(() => _applications = apps);
      _applicationsNotifier.value = List<Application>.from(apps);
      await _applySearch(forceTimeline: true);
    } catch (_) {
      // Ignore refresh errors; the full dashboard refresh will retry.
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
      _showSyncSnack('Discard failed: $error');
    }
  }

  void _removeReviewItem(String id) {
    setState(() {
      _reviewQueue.removeWhere((item) => item.id == id);
    });
    _updateReviewDialogState();
    _maybeCloseReviewDialog();
  }

  void _maybeCloseReviewDialog() {
    if (!_syncComplete || _reviewQueue.isNotEmpty) {
      return;
    }
    if (_reviewDialogOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!_syncCompleteNotified) {
      _syncCompleteNotified = true;
      _showSyncSnack('Sync completed');
    }
  }

  Future<void> _loadUpcoming(int days) async {
    final upcoming = await widget.repo.listUpcomingInterviews(days: days);
    if (!mounted) {
      return;
    }
    setState(() {
      _upcomingDays = days;
      _upcoming = upcoming;
    });
    await _applySearch();
  }

  Future<void> _selectApplicationById(String id) async {
    Application? selected;
    for (final app in _applications) {
      if (app.id == id) {
        selected = app;
        break;
      }
    }
    if (selected == null) {
      return;
    }
    setState(() {
      _selected = selected;
      _timeline = [];
    });
    await _loadTimeline();
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

  List<ActivityItem> _filterActivities(
    List<ActivityItem> items,
    List<String> tokens,
    Map<String, Application> appById,
  ) {
    if (tokens.isEmpty) {
      return items;
    }
    return items.where((item) {
      final app = item.applicationId == null
          ? null
          : appById[item.applicationId];
      final haystack = [
        item.title,
        item.detail,
        app?.company ?? '',
        app?.role ?? '',
      ].join(' ').toLowerCase();
      return _matchesTokens(haystack, tokens);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final total = _visibleApplications.length;
    final interviews = _visibleApplications
        .where((app) => app.status == ApplicationStatus.interview)
        .length;
    final offers = _visibleApplications
        .where((app) => app.status == ApplicationStatus.offer)
        .length;
    final rejected = _visibleApplications
        .where((app) => app.status == ApplicationStatus.rejected)
        .length;

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            const Sidebar(selectedIndex: 0),
            Expanded(
              child: Column(
                children: [
                  Topbar(
                    title: 'Dashboard',
                    subtitle: 'Track your job applications',
                    showSearch: true,
                    onSync: _startGmailSync,
                    syncInProgress: _syncing,
                    syncLabel: _syncStatus,
                    reviewCount: _reviewQueue.length,
                    onReview: _openReviewDialog,
                    searchController: _searchController,
                    onSearchChanged: _onSearchChanged,
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 1200;

                        return FutureBuilder<void>(
                          future: _loadFuture,
                          builder: (context, snapshot) {
                            if (_errorMessage != null) {
                              return Center(
                                child: Text(
                                  'Failed to load dashboard data',
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
                                    Wrap(
                                      spacing: 16,
                                      runSpacing: 16,
                                      children: [
                                        SizedBox(
                                          width: 220,
                                          child: KpiCard(
                                            title: 'Total Applications',
                                            value: total.toString(),
                                            icon: Icons.inventory_2_outlined,
                                            accentColor: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 220,
                                          child: KpiCard(
                                            title: 'Interviews',
                                            value: interviews.toString(),
                                            icon: Icons.schedule,
                                            accentColor: Theme.of(context)
                                                .colorScheme
                                                .secondary,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 220,
                                          child: KpiCard(
                                            title: 'Offers',
                                            value: offers.toString(),
                                            icon: Icons.check_circle_outline,
                                            accentColor: Theme.of(context)
                                                .colorScheme
                                                .tertiary,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 220,
                                          child: KpiCard(
                                            title: 'Rejected',
                                            value: rejected.toString(),
                                            icon: Icons.cancel_outlined,
                                            accentColor:
                                                Theme.of(context).colorScheme.error,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                    if (isWide)
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              children: [
                                                ActivityTabs(
                                                  updates: _visibleUpdates,
                                                  upcoming: _visibleUpcoming,
                                                  selectedDays: _upcomingDays,
                                                  onWindowChanged: (value) {
                                                    _loadUpcoming(value);
                                                  },
                                                  onInterviewSelected: (item) {
                                                    final id = item.applicationId;
                                                    if (id == null) {
                                                      return;
                                                    }
                                                    _selectApplicationById(id);
                                                  },
                                                ),
                                                const SizedBox(height: 16),
                                                AppTable(
                                                  applications: _visibleApplications,
                                                  selectedId: _selected?.id,
                                                  onSelected: (app) async {
                                                    setState(() {
                                                      _selected = app;
                                                      _timeline = [];
                                                    });
                                                    await _loadTimeline();
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 20),
                                          SizedBox(
                                            width: 320,
                                            child: DetailsPanel(
                                              application: _selected,
                                              timeline: _timeline,
                                            ),
                                          ),
                                        ],
                                      )
                                    else
                                      Column(
                                        children: [
                                          ActivityTabs(
                                            updates: _visibleUpdates,
                                            upcoming: _visibleUpcoming,
                                            selectedDays: _upcomingDays,
                                            onWindowChanged: (value) {
                                              _loadUpcoming(value);
                                            },
                                            onInterviewSelected: (item) {
                                              final id = item.applicationId;
                                              if (id == null) {
                                                return;
                                              }
                                              _selectApplicationById(id);
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                          AppTable(
                                            applications: _visibleApplications,
                                            selectedId: _selected?.id,
                                            onSelected: (app) async {
                                              setState(() {
                                                _selected = app;
                                                _timeline = [];
                                              });
                                              await _loadTimeline();
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                          DetailsPanel(
                                            application: _selected,
                                            timeline: _timeline,
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
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
