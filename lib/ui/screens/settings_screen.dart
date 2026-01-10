import 'package:flutter/material.dart';

import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            const Sidebar(selectedIndex: 3),
            Expanded(
              child: Column(
                children: [
                  const Topbar(
                    title: 'Settings',
                    subtitle: 'Preferences and app data',
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Settings view coming soon',
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
