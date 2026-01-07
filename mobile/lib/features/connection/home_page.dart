import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'scan_qr_page.dart';
import 'manual_connect_page.dart';
import '../terminal/terminal_page.dart';
import 'connection_provider.dart';
import '../../core/storage.dart';

/// Home page for connection selection
///
/// Phase 04: Mobile App
/// Shows saved hosts and options to connect
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comacode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // TODO: Show settings
            },
          ),
        ],
      ),
      body: Consumer<ConnectionProvider>(
        builder: (context, connection, _) {
          if (connection.isConnected) {
            // Already connected - show terminal
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const TerminalPage()),
              );
            });
          }

          return _buildContent(context, connection);
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, ConnectionProvider connection) {
    return FutureBuilder<bool>(
      future: connection.hasSavedHosts(),
      builder: (context, snapshot) {
        final hasHosts = snapshot.data ?? false;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              const Text(
                'Connect to Host',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Scan a QR code or enter connection details to pair with a host.',
                style: TextStyle(
                  color: Color(0xFF6C7086),
                ),
              ),
              const SizedBox(height: 32),

              // Connection options
              _buildPrimaryButton(
                context,
                icon: Icons.qr_code_scanner,
                label: 'Scan QR Code',
                description: 'Scan QR from host terminal',
                onTap: () => _navigateToScan(context),
              ),
              const SizedBox(height: 16),
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
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Saved Hosts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _clearAllHosts(context),
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSavedHostsList(context),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF313244),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFCBA6F7).withValues(alpha: 0.3),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFCBA6F7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: const Color(0xFF1E1E2E),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF6C7086),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF6C7086),
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
          color: const Color(0xFF313244),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFF6C7086),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF6C7086),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: const Color(0xFF6C7086),
              size: 20,
            ),
          ],
        ),
      ),
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
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFF45475A),
        foregroundColor: Color(0xFFCBA6F7),
        child: Icon(Icons.computer),
      ),
      title: Text(host.displayName),
      subtitle: Text(
        'Fingerprint: ${host.fingerprint.substring(0, 16)}...',
        style: const TextStyle(
          color: Color(0xFF6C7086),
          fontSize: 12,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.connect_without_contact),
            onPressed: () => _connectToSaved(context, host),
            tooltip: 'Connect',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _deleteHost(context, host),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }

  void _navigateToScan(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanQrPage()),
    );
  }

  void _navigateToManual(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ManualConnectPage()),
    );
  }

  void _connectToSaved(BuildContext context, QrPayload host) async {
    final connection = context.read<ConnectionProvider>();
    try {
      await connection.connectWithQrString(host.toJson());
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const TerminalPage()),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    }
  }

  void _deleteHost(BuildContext context, QrPayload host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Host'),
        content: const Text('Remove this saved host?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AppStorage.deleteHost(host.fingerprint);
      // Refresh
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    }
  }

  void _clearAllHosts(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Hosts'),
        content: const Text('Remove all saved hosts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFF38BA8),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AppStorage.clearAll();
      // Refresh
      if (context.mounted) {
        (context as Element).markNeedsBuild();
      }
    }
  }
}
