import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/db/db.dart';
import '../../data/models/activity_item.dart';
import '../../data/models/application.dart';
import '../../data/repo/application_repo.dart';
import '../../data/repo/sqlite_application_repo.dart';
import '../../domain/status/status_types.dart';
import '../../services/data_refresh_bus.dart';
import '../../services/gmail_settings.dart';
import '../../services/gmail_sync_service.dart';
import '../../services/secrets_store.dart';
import '../../services/settings_store.dart';
import '../../services/app_data_paths.dart';
import '../widgets/activity_tabs.dart';
import '../widgets/app_table.dart';
import '../widgets/details_panel.dart';
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
  String _searchQuery = '';
  late final VoidCallback _refreshListener;

  @override
  void initState() {
    super.initState();
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
    final storeRawBody =
        settings.get<bool>(GmailSettingsKeys.storeRawBody) ?? true;
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
    final skipSeed = SettingsStore.instance.get<bool>('skipSeed') ?? false;
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
    );

    setState(() {
      _syncing = true;
      _syncStatus = 'Syncing...';
    });

    final service = GmailSyncService();
    var syncFailed = false;
    final stream = service.startSync(config);
    stream.listen((progress) {
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
      });
      _showSyncSnack('Sync failed: $error');
    }, onDone: () async {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        _syncStatus = null;
      });
      if (!syncFailed) {
        DataRefreshBus.notify();
        await _loadDashboard();
      }
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
