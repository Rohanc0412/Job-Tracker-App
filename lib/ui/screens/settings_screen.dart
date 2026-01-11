import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/db/db.dart';
import '../../services/data_refresh_bus.dart';
import '../../services/fixture_loader.dart';
import '../../services/fixture_ingestion_pipeline.dart';
import '../../services/gmail_imap_test_service.dart';
import '../../services/gmail_settings.dart';
import '../../services/secrets_store.dart';
import '../../services/settings_store.dart';
import '../../services/app_data_paths.dart';
import '../widgets/sidebar.dart';
import '../widgets/topbar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _testMode = false;
  bool _clearBeforeLoad = true;
  bool _loading = false;
  bool _savingGmail = false;
  bool _storeRawBody = true;
  bool _seedDemoData = true;
  bool _wiping = false;
  bool _testingImap = false;
  DateTime? _gmailStartDate;
  DateTime? _lastSyncTime;
  String _gmailFolder = 'INBOX';
  final TextEditingController _gmailEmailController =
      TextEditingController();
  final TextEditingController _gmailPasswordController =
      TextEditingController();

  late final VoidCallback _refreshListener;

  @override
  void initState() {
    super.initState();
    final settings = SettingsStore.instance;
    _testMode = settings.get<bool>('testMode') ?? false;
    final skipSeed = settings.get<bool>('skipSeed') ?? false;
    print('[Settings] initState: skipSeed=$skipSeed, seedDemoData=${!skipSeed}');
    _seedDemoData = !skipSeed;
    _gmailFolder = settings.get<String>(GmailSettingsKeys.folder) ?? 'INBOX';
    _storeRawBody =
        settings.get<bool>(GmailSettingsKeys.storeRawBody) ?? true;
    final startDateValue = settings.get<String>(GmailSettingsKeys.startDate);
    _gmailStartDate =
        startDateValue == null ? null : DateTime.tryParse(startDateValue);
    _gmailEmailController.text =
        settings.get<String>(GmailSettingsKeys.email) ?? '';
    _loadGmailCredentials();
    _loadLastSyncTime();
    _refreshListener = _loadLastSyncTime;
    DataRefreshBus.notifier.addListener(_refreshListener);
  }

  @override
  void dispose() {
    DataRefreshBus.notifier.removeListener(_refreshListener);
    _gmailEmailController.dispose();
    _gmailPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadGmailCredentials() async {
    final creds = await SecretsStore().readGmailCredentials();
    if (creds == null || !mounted) {
      return;
    }
    if (_gmailEmailController.text.isEmpty) {
      _gmailEmailController.text = creds.email;
    }
    _gmailPasswordController.text = creds.appPassword;
  }

  Future<void> _loadLastSyncTime() async {
    final email = _gmailEmailController.text.trim();
    final db = AppDatabase.instance;
    await db.open();
    final rows = email.isEmpty
        ? db.rawDb.select(
            "SELECT MAX(lastSyncTime) AS lastSyncTime FROM sync_state WHERE provider = 'gmail';",
          )
        : db.rawDb.select(
            "SELECT MAX(lastSyncTime) AS lastSyncTime FROM sync_state WHERE provider = 'gmail' AND accountLabel = ?;",
            [email],
          );
    DateTime? lastSync;
    if (rows.isNotEmpty) {
      final value = rows.first['lastSyncTime'] as String?;
      if (value != null) {
        lastSync = DateTime.tryParse(value);
      }
    }
    if (!mounted) {
      return;
    }
    setState(() => _lastSyncTime = lastSync);
  }

  Future<void> _saveGmailSettings() async {
    setState(() => _savingGmail = true);
    try {
      final email = _gmailEmailController.text.trim();
      final folder = _gmailFolder;
      await SettingsStore.instance.set(GmailSettingsKeys.email, email);
      await SettingsStore.instance.set(GmailSettingsKeys.folder, folder);
      await SettingsStore.instance
          .set(GmailSettingsKeys.storeRawBody, _storeRawBody);
      if (_gmailStartDate != null) {
        await SettingsStore.instance.set(
          GmailSettingsKeys.startDate,
          _gmailStartDate!.toIso8601String(),
        );
      }
      final password = _gmailPasswordController.text.trim();
      if (email.isNotEmpty && password.isNotEmpty) {
        await SecretsStore().saveGmailCredentials(
          email: email,
          appPassword: password,
        );
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gmail settings saved.')),
      );
    } finally {
      if (mounted) {
        setState(() => _savingGmail = false);
      }
    }
  }

  Future<void> _pickStartDate() async {
    final initialDate = _gmailStartDate ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (selected == null) {
      return;
    }
    setState(() => _gmailStartDate = selected);
    await SettingsStore.instance.set(
      GmailSettingsKeys.startDate,
      selected.toIso8601String(),
    );
  }

  Future<void> _wipeLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wipe local data?'),
        content: const Text(
          'This removes the local database, raw body files, and stored Gmail credentials.\n\nYou will need to restart the app after wiping.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Wipe & Restart'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    setState(() => _wiping = true);
    try {
      // Force close database connection and wait for locks to release
      await AppDatabase.instance.forceClose();

      final dbPath = await AppDataPaths.databaseFilePath();
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final deleted = await _deleteFileWithRetry(dbFile);
        if (!deleted) {
          _showWipeError(
            'Database is in use. Please completely close and restart the app, then try again.',
          );
          return;
        }
      }
      final rawDir = await AppDataPaths.rawBodiesDir(ensure: false);
      if (await rawDir.exists()) {
        final deleted = await _deleteDirWithRetry(rawDir);
        if (!deleted) {
          _showWipeError(
            'Raw body files are in use. Please completely close and restart the app, then try again.',
          );
          return;
        }
      }
      await SecretsStore().clearGmailCredentials();
      await SettingsStore.instance.remove(GmailSettingsKeys.email);
      await SettingsStore.instance.remove(GmailSettingsKeys.folder);
      await SettingsStore.instance.remove(GmailSettingsKeys.startDate);
      await SettingsStore.instance.remove(GmailSettingsKeys.storeRawBody);

      if (!mounted) {
        return;
      }

      // Show success dialog and inform user to restart
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Data Wiped Successfully'),
          content: const Text(
            'All local data has been removed.\n\nPlease close and restart the app now.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Force exit the app
                exit(0);
              },
              child: const Text('Close App'),
            ),
          ],
        ),
      );
    } catch (error) {
      _showWipeError('Failed to wipe local data: $error');
    } finally {
      if (mounted) {
        setState(() => _wiping = false);
      }
    }
  }

  Future<bool> _deleteFileWithRetry(File file) async {
    const attempts = 10;
    for (var i = 0; i < attempts; i++) {
      try {
        if (!await file.exists()) {
          return true;
        }
        await file.delete();
        return true;
      } catch (_) {
        if (i == attempts - 1) {
          return false;
        }
        await Future.delayed(Duration(milliseconds: 300 + (i * 100)));
      }
    }
    return false;
  }

  Future<bool> _deleteDirWithRetry(Directory dir) async {
    const attempts = 10;
    for (var i = 0; i < attempts; i++) {
      try {
        if (!await dir.exists()) {
          return true;
        }
        await dir.delete(recursive: true);
        return true;
      } catch (_) {
        if (i == attempts - 1) {
          return false;
        }
        await Future.delayed(Duration(milliseconds: 300 + (i * 100)));
      }
    }
    return false;
  }

  void _showWipeError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadFixtures() async {
    setState(() => _loading = true);
    try {
      final loader = FixtureLoader(AppDatabase.instance);
      final count =
          await loader.loadFixtures(clearExisting: _clearBeforeLoad);
      final pipeline = FixtureIngestionPipeline(AppDatabase.instance);
      await pipeline.run();
      DataRefreshBus.notify();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded $count fixture emails.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load fixtures: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _testImapConnection() async {
    setState(() => _testingImap = true);
    try {
      final email = _gmailEmailController.text.trim();
      final password = _gmailPasswordController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email and password are required.')),
        );
        return;
      }

      print('[IMAP Test] Starting connection to Gmail...');
      print('[IMAP Test] Email: $email, Folder: $_gmailFolder');

      final testService = GmailImapTestService();
      final result = await testService.fetchRecentHeaders(
        email: email,
        appPassword: password,
        folder: _gmailFolder,
        limit: 10,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('[IMAP Test] TIMEOUT after 30 seconds');
          throw TimeoutException(
            'IMAP connection timed out after 30 seconds. Check your credentials and network.',
          );
        },
      );

      print('[IMAP Test] Successfully fetched ${result.messages.length} messages');

      if (!mounted) return;

      if (result.messages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('IMAP connected but no messages found in folder.')),
        );
        return;
      }

      final messageList = result.messages.map((msg) {
        return '• UID ${msg.uid}: ${msg.subject}\n  From: ${msg.from}\n  Date: ${msg.date}';
      }).join('\n\n');

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('IMAP Test Success (${result.messages.length} emails)'),
          content: SingleChildScrollView(
            child: SelectableText(
              'UIDValidity: ${result.uidValidity}\n\n$messageList',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('IMAP test failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _testingImap = false);
      }
    }
  }

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
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Gmail',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Sync Gmail via IMAP in read-only mode using an app password.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _gmailEmailController,
                                    decoration: const InputDecoration(
                                      labelText: 'Gmail address',
                                    ),
                                    onChanged: (value) {
                                      SettingsStore.instance.set(
                                        GmailSettingsKeys.email,
                                        value.trim(),
                                      );
                                      _loadLastSyncTime();
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _gmailPasswordController,
                                    decoration: const InputDecoration(
                                      labelText: 'App password',
                                    ),
                                    obscureText: true,
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText: 'Folder',
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: _gmailFolder,
                                              items: const [
                                                DropdownMenuItem(
                                                  value: 'INBOX',
                                                  child: Text('INBOX'),
                                                ),
                                              ],
                                              onChanged: (value) {
                                                if (value == null) {
                                                  return;
                                                }
                                                setState(() {
                                                  _gmailFolder = value;
                                                });
                                                SettingsStore.instance.set(
                                                  GmailSettingsKeys.folder,
                                                  value,
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: InputDecorator(
                                          decoration: const InputDecoration(
                                            labelText: 'Start date',
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  _gmailStartDate == null
                                                      ? 'Not set'
                                                      : DateFormat('yyyy-MM-dd')
                                                          .format(
                                                              _gmailStartDate!),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: _pickStartDate,
                                                child: const Text('Pick'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Store raw email body locally',
                                    ),
                                    subtitle: const Text(
                                      'Save the full body to SQLite or a local file when large.',
                                    ),
                                    value: _storeRawBody,
                                    onChanged: (value) {
                                      setState(() => _storeRawBody = value);
                                      SettingsStore.instance.set(
                                        GmailSettingsKeys.storeRawBody,
                                        value,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _lastSyncTime == null
                                              ? 'Last sync: Never'
                                              : 'Last sync: ${DateFormat('yyyy-MM-dd HH:mm').format(_lastSyncTime!.toLocal())}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed:
                                            _testingImap ? null : _testImapConnection,
                                        icon: _testingImap
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(Icons.bug_report),
                                        label: const Text('Test IMAP'),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton(
                                        onPressed:
                                            _savingGmail ? null : _saveGmailSettings,
                                        child: _savingGmail
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Text('Save'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Testing',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Load synthetic email fixtures to validate '
                                    'parsing and status detection without using '
                                    'real data.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 16),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Seed demo data'),
                                    subtitle: const Text(
                                      'Populate demo applications when the database is empty.',
                                    ),
                                    value: _seedDemoData,
                                    onChanged: (value) async {
                                      setState(() => _seedDemoData = value);
                                      final skipSeed = !value;
                                      print('[Settings] Setting skipSeed=$skipSeed (seedDemoData=$value)');
                                      await SettingsStore.instance
                                          .set('skipSeed', skipSeed);
                                      print('[Settings] skipSeed saved successfully');
                                      if (!mounted) {
                                        return;
                                      }
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            value
                                                ? 'Demo data will load when the database is empty.'
                                                : 'Demo data disabled. Wipe local data to clear.',
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                  const Divider(height: 32),
                                  SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Test Mode'),
                                    subtitle: const Text(
                                      'Use synthetic email fixtures for validation',
                                    ),
                                    value: _testMode,
                                    onChanged: (value) {
                                      setState(() => _testMode = value);
                                      SettingsStore.instance
                                          .set('testMode', value);
                                    },
                                  ),
                                  const Divider(height: 32),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text(
                                      'Clear existing data before loading',
                                    ),
                                    subtitle: const Text(
                                      'Removes current applications and activity.',
                                    ),
                                    value: _clearBeforeLoad,
                                    onChanged: _testMode
                                        ? (value) {
                                            setState(() {
                                              _clearBeforeLoad = value ?? false;
                                            });
                                          }
                                        : null,
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                      onPressed: _testMode && !_loading
                                          ? _loadFixtures
                                          : null,
                                      icon: _loading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.play_arrow),
                                      label: const Text('Load Fixtures'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Security',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Remove local database files and stored credentials.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FilledButton.icon(
                                      onPressed:
                                          _wiping ? null : _wipeLocalData,
                                      icon: _wiping
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child:
                                                  CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.delete_outline),
                                      label: const Text('Wipe Local Data'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
