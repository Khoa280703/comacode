import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../qr_scanner/qr_scanner_page.dart';
import '../vibe/vibe_session_page.dart';
import 'connection_providers.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';

/// Home page for connection selection
///
/// Phase 06: Refactor to Riverpod
/// Shows saved hosts and options to connect
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);

    // Auto-navigate to Vibe Session if already connected
    if (connectionState.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VibeSessionPage()),
        );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Comacode'),
        backgroundColor: CatppuccinMocha.mantle,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Show settings
            },
          ),
        ],
      ),
      body: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return FutureBuilder<bool>(
      future: ref.read(connectionStateProvider.notifier).hasSavedHosts(),
      builder: (context, snapshot) {
        final hasHosts = snapshot.data ?? false;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo/Icon
              Center(
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: CatppuccinMocha.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.qr_code_scanner,
                    size: 48,
                    color: CatppuccinMocha.mauve,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Vibe Coding',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: CatppuccinMocha.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Scan QR code to start Vibe Coding session',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: CatppuccinMocha.subtext0,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              // Primary action: Scan QR
              _buildPrimaryButton(
                context,
                icon: Icons.qr_code_scanner,
                label: 'Scan QR Code',
                description: 'Scan QR from host terminal',
                onTap: () => _navigateToScan(context),
              ),
              const SizedBox(height: 16),

              // Vibe Coding button (new!)
              _buildVibeButton(context),

              const SizedBox(height: 16),

              // Secondary action: Manual connect
              _buildSecondaryButton(
                context,
                icon: Icons.edit,
                label: 'Manual Connect',
                description: 'Enter connection details manually',
                onTap: () => _navigateToManual(context),
              ),

              // Saved hosts section
              if (hasHosts) ...[
                const SizedBox(height: 32),
                const Divider(color: CatppuccinMocha.surface0),
                const SizedBox(height: 16),
                _buildSavedHostsSection(context),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrimaryButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: CatppuccinMocha.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CatppuccinMocha.mauve.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: CatppuccinMocha.mauve,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: CatppuccinMocha.crust,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: CatppuccinMocha.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: CatppuccinMocha.subtext0,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: CatppuccinMocha.subtext0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVibeButton(BuildContext context) {
    return InkWell(
      onTap: () => _navigateToVibe(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              CatppuccinMocha.mauve.withValues(alpha: 0.2),
              CatppuccinMocha.blue.withValues(alpha: 0.2),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: CatppuccinMocha.mauve.withValues(alpha: 0.5),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [CatppuccinMocha.mauve, CatppuccinMocha.blue],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.smart_toy,
                color: CatppuccinMocha.crust,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vibe Coding',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: CatppuccinMocha.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Chat-style interface for Claude Code CLI',
                    style: TextStyle(
                      color: CatppuccinMocha.subtext0,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: CatppuccinMocha.subtext0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: CatppuccinMocha.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: CatppuccinMocha.subtext0,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: CatppuccinMocha.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: CatppuccinMocha.subtext0,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: CatppuccinMocha.subtext0,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedHostsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Saved Hosts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: CatppuccinMocha.text,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _clearAllHosts(context),
              child: Text(
                'Clear All',
                style: TextStyle(color: CatppuccinMocha.red),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSavedHostsList(context),
      ],
    );
  }

  Widget _buildSavedHostsList(BuildContext context) {
    return FutureBuilder<List<QrPayload>>(
      future: AppStorage.getAllHosts(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final hosts = snapshot.data!;
        if (hosts.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          children: hosts.map((host) {
            return _buildHostTile(context, host);
          }).toList(),
        );
      },
    );
  }

  Widget _buildHostTile(BuildContext context, QrPayload host) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: CatppuccinMocha.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: CatppuccinMocha.surface1,
          foregroundColor: CatppuccinMocha.mauve,
          child: const Icon(Icons.computer),
        ),
        title: Text(
          host.displayName,
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        subtitle: Text(
          'Saved host', // Don't display fingerprint for security (shoulder surfing)
          style: TextStyle(
            color: CatppuccinMocha.subtext0,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.connect_without_contact,
                color: CatppuccinMocha.green,
              ),
              onPressed: () => _connectToSaved(context, host),
              tooltip: 'Connect',
            ),
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: CatppuccinMocha.red,
              ),
              onPressed: () => _deleteHost(context, host),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToScan(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );
  }

  void _navigateToVibe(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const VibeSessionPage()),
    );
  }

  void _navigateToManual(BuildContext context) {
    // TODO: Implement manual connect page
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Manual connect coming soon')),
    );
  }

  void _connectToSaved(BuildContext context, QrPayload host) async {
    try {
      await ref.read(connectionStateProvider.notifier).connect(host.toJson());
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VibeSessionPage()),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: CatppuccinMocha.red,
          ),
        );
      }
    }
  }

  void _deleteHost(BuildContext context, QrPayload host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CatppuccinMocha.surface,
        title: Text(
          'Delete Host',
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        content: Text(
          'Remove this saved host?',
          style: TextStyle(color: CatppuccinMocha.subtext0),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: CatppuccinMocha.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Disconnect if deleting the currently connected host
      final connectionState = ref.read(connectionStateProvider);
      if (connectionState.isConnected &&
          connectionState.currentHost?.fingerprint == host.fingerprint) {
        await ref.read(connectionStateProvider.notifier).disconnect();
      }

      await AppStorage.deleteHost(host.fingerprint);
      // Trigger rebuild to refresh hosts list
      setState(() {});
    }
  }

  void _clearAllHosts(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: CatppuccinMocha.surface,
        title: Text(
          'Clear All Hosts',
          style: TextStyle(color: CatppuccinMocha.text),
        ),
        content: Text(
          'Remove all saved hosts?',
          style: TextStyle(color: CatppuccinMocha.subtext0),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear All',
              style: TextStyle(color: CatppuccinMocha.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AppStorage.clearAll();
      // Trigger rebuild to refresh hosts list
      setState(() {});
    }
  }
}
