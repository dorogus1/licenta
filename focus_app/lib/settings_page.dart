import 'package:flutter/material.dart';
import 'dart:async';
import 'auth_service.dart';

class SettingsPage extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLogout;
  final VoidCallback toggleTheme;
  final bool isDark;

  const SettingsPage({
    super.key,
    required this.authService,
    required this.onLogout,
    required this.toggleTheme,
    required this.isDark,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? email;
  String? currentDeviceId;
  Map<String, dynamic> devices = {};
  Timer? _refreshTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchDevices());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    email = await widget.authService.getUserEmail();
    currentDeviceId = await widget.authService.getDeviceId();
    await _fetchDevices();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchDevices() async {
    final devs = await widget.authService.getDevices();
    if (mounted) {
      setState(() => devices = devs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader('Profile'),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(email ?? 'Not logged in'),
              subtitle: Text('Device ID: ${currentDeviceId ?? 'Unknown'}'),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Appearance'),
          Card(
            child: SwitchListTile(
              secondary: Icon(widget.isDark ? Icons.dark_mode : Icons.light_mode),
              title: const Text('Dark Mode'),
              value: widget.isDark,
              onChanged: (_) => widget.toggleTheme(),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('Active Devices'),
          _loading 
            ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            : devices.isEmpty 
              ? const Card(child: ListTile(title: Text('No other active devices')))
              : Column(
                  children: devices.entries.map((entry) {
                    final id = entry.key;
                    final data = entry.value;
                    final isMe = id == currentDeviceId;

                    final type = data['type'] as String? ?? 'unknown';
                    final name = data['name'] as String? ?? 'Unknown Device';
                    final platform = data['platform'] as String? ?? '';
                    final state = data['state'] as String? ?? 'offline';
                    final lastSeen = data['last_seen'] as int? ?? 0;

                    final now = DateTime.now().millisecondsSinceEpoch;
                    final isOnline = (state != 'offline') && ((now - lastSeen) < 90000);

                    IconData icon;
                    if (type == 'extension') icon = Icons.language;
                    else if (type == 'windows') icon = Icons.laptop_windows;
                    else if (type == 'mobile') icon = Icons.smartphone;
                    else icon = Icons.devices;

                    return Card(
                      child: ListTile(
                        leading: Icon(icon, color: isMe ? Theme.of(context).colorScheme.primary : null),
                        title: Text('$name ${isMe ? '(You)' : ''}'),
                        subtitle: Text(platform),
                        trailing: Icon(
                          Icons.circle,
                          size: 12,
                          color: isOnline ? Colors.green : Colors.grey,
                        ),
                      ),
                    );
                  }).toList(),
                ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.withOpacity(0.1),
              foregroundColor: Colors.red,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
