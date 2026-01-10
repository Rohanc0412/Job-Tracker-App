import 'package:flutter/material.dart';

import '../../data/db/db.dart';
import '../../data/models/activity_item.dart';
import '../../data/models/application.dart';
import '../../data/repo/application_repo.dart';
import '../../data/repo/sqlite_application_repo.dart';
import '../../domain/status/status_types.dart';
import '../widgets/activity_tabs.dart';
import '../widgets/app_table.dart';
import '../widgets/details_panel.dart';
import '../widgets/kpi_card.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

class DashboardScreen extends StatefulWidget {
  final ApplicationRepo repo;

  DashboardScreen({
    super.key,
    ApplicationRepo? repo,
  }) : repo = repo ?? SqliteApplicationRepo(AppDatabase.instance);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  late final Future<void> _loadFuture;
  List<Application> _applications = [];
  List<ActivityItem> _updates = [];
  List<ActivityItem> _upcoming = [];
  List<ActivityItem> _timeline = [];
  Application? _selected;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadDashboard();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboard() async {
    try {
      final apps = await widget.repo.listApplications();
      final updates = await widget.repo.listRecentUpdates();
      final upcoming = await widget.repo.listUpcomingInterviews();
      if (!mounted) {
        return;
      }
      setState(() {
        _applications = apps;
        _updates = updates;
        _upcoming = upcoming;
        _selected = apps.isNotEmpty ? apps.first : null;
      });
      await _loadTimeline();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorMessage = error.toString());
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

  @override
  Widget build(BuildContext context) {
    final total = _applications.length;
    final interviews = _applications
        .where((app) => app.status == ApplicationStatus.interview)
        .length;
    final offers = _applications
        .where((app) => app.status == ApplicationStatus.offer)
        .length;
    final rejected = _applications
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
                  const Topbar(
                    title: 'Dashboard',
                    subtitle: 'Track your job applications',
                    showSearch: true,
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
                            if (_applications.isEmpty &&
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
                                                  updates: _updates,
                                                  upcoming: _upcoming,
                                                ),
                                                const SizedBox(height: 16),
                                                AppTable(
                                                  applications: _applications,
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
                                            updates: _updates,
                                            upcoming: _upcoming,
                                          ),
                                          const SizedBox(height: 16),
                                          AppTable(
                                            applications: _applications,
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
