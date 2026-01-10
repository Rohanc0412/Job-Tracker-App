import 'package:flutter/material.dart';

import '../../data/models/application.dart';
import '../../data/seed/demo_data.dart';
import '../../domain/status/status_types.dart';
import '../widgets/activity_tabs.dart';
import '../widgets/app_table.dart';
import '../widgets/details_panel.dart';
import '../widgets/kpi_card.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final List<Application> _applications;
  Application? _selected;

  @override
  void initState() {
    super.initState();
    _applications = DemoData.applications;
    if (_applications.isNotEmpty) {
      _selected = _applications.first;
    }
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

                        return Scrollbar(
                          child: SingleChildScrollView(
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
                                        accentColor:
                                            Theme.of(context).colorScheme.primary,
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
                                        accentColor:
                                            Theme.of(context).colorScheme.tertiary,
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
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            ActivityTabs(
                                              updates: DemoData.updates,
                                              upcoming: DemoData.upcomingInterviews,
                                            ),
                                            const SizedBox(height: 16),
                                            AppTable(
                                              applications: _applications,
                                              selectedId: _selected?.id,
                                              onSelected: (app) {
                                                setState(() => _selected = app);
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      SizedBox(
                                        width: 320,
                                        child: DetailsPanel(application: _selected),
                                      ),
                                    ],
                                  )
                                else
                                  Column(
                                    children: [
                                      ActivityTabs(
                                        updates: DemoData.updates,
                                        upcoming: DemoData.upcomingInterviews,
                                      ),
                                      const SizedBox(height: 16),
                                      AppTable(
                                        applications: _applications,
                                        selectedId: _selected?.id,
                                        onSelected: (app) {
                                          setState(() => _selected = app);
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                      DetailsPanel(application: _selected),
                                    ],
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
