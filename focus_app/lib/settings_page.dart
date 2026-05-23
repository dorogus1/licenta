import 'package:flutter/material.dart';
import 'dart:async';
import 'l10n/app_localizations.dart';
import 'auth_service.dart';

class SettingsPage extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLogout;
  final VoidCallback toggleTheme;
  final Function(Locale) setLocale;
  final Locale? currentLocale;
  final bool isDark;

  const SettingsPage({
    super.key,
    required this.authService,
    required this.onLogout,
    required this.toggleTheme,
    required this.isDark,
    required this.setLocale,
    required this.currentLocale,
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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionHeader(l10n.profile),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(email ?? l10n.notLoggedIn),
              subtitle: Text(l10n.deviceId(currentDeviceId ?? 'Unknown')),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.appearance),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(widget.isDark ? Icons.dark_mode : Icons.light_mode),
                  title: Text(l10n.darkMode),
                  value: widget.isDark,
                  onChanged: (_) => widget.toggleTheme(),
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(l10n.language),
                  trailing: DropdownButton<String>(
                    value: widget.currentLocale?.languageCode ?? 'en',
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'ro', child: Text('Română')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        widget.setLocale(Locale(val));
                      }
                    },
                    underline: Container(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.activeDevices),
          _loading 
            ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            : devices.isEmpty 
              ? Card(child: ListTile(title: Text(l10n.noOtherDevices)))
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
                        title: Text('$name ${isMe ? l10n.you : ''}'),
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
            label: Text(l10n.logout, style: const TextStyle(fontWeight: FontWeight.bold)),
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
