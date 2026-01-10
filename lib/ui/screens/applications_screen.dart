import 'package:flutter/material.dart';

import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

class ApplicationsScreen extends StatelessWidget {
  const ApplicationsScreen({super.key});

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
                  const Topbar(
                    title: 'Applications',
                    subtitle: 'Manage your pipeline',
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Applications view coming soon',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                      ),
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
