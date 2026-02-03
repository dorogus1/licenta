import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/app_blocker_service.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:permission_handler/permission_handler.dart';

class MobileAppsPage extends StatefulWidget {
  const MobileAppsPage({super.key});

  @override
  State<MobileAppsPage> createState() => _MobileAppsPageState();
}

class _MobileAppsPageState extends State<MobileAppsPage> {
  List<AppInfo> installed = [];
  List<AppInfo> filtered = [];
  List<String> blocked = [];
  bool _isLoading = true;
  String searchQuery = '';
  
  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadData();
  }

  Future<void> _checkPermissions() async {
    // 1. Usage Stats
    bool usageGranted = await UsageStats.checkUsagePermission() ?? false;
    if (!usageGranted && mounted) {
      await showDialog(
        context: context, 
        builder: (ctx) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text('To detect running apps, Focus App needs "Usage Access" permission.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                UsageStats.grantUsagePermission();
                Navigator.pop(ctx);
              }, 
              child: const Text('Open Settings')
            ),
          ],
        )
      );
    }

    // 2. Draw Over Other Apps (Required to bring app to front from background on Android 10+)
    if (await Permission.systemAlertWindow.status.isDenied && mounted) {
       await showDialog(
        context: context, 
        builder: (ctx) => AlertDialog(
          title: const Text('Permission Required'),
          content: const Text('To block apps effectively, Focus App needs "Display over other apps" permission.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await Permission.systemAlertWindow.request();
                Navigator.pop(ctx);
              }, 
              child: const Text('Grant')
            ),
          ],
        )
      );
    }
    
    // 3. Notification (Android 13+)
    if (await Permission.notification.status.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    blocked = prefs.getStringList('blocked_apps') ?? [];
    
    try {
      final apps = await AppBlockerService.getInstalledApps();
      
      // Remove ourselves from the list to prevent blocking ourselves
      apps.removeWhere((app) => app.id == 'com.example.focus_app'); 

      if (mounted) {
        setState(() {
          installed = apps;
          filtered = apps;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading apps: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _filter(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filtered = installed;
      } else {
        filtered = installed.where((app) => 
          app.name.toLowerCase().contains(query.toLowerCase())
        ).toList();
      }
    });
  }

  void _toggleBlock(String id) async {
    setState(() {
      if (blocked.contains(id)) {
        blocked.remove(id);
      } else {
        blocked.add(id);
      }
    });
    await AppBlockerService.setBlockList(blocked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Block Apps'),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final app = filtered[index];
                    final isBlocked = blocked.contains(app.id);
                    
                    return ListTile(
                      leading: app.icon != null && app.icon is Uint8List 
                        ? Image.memory(app.icon as Uint8List, width: 40, height: 40)
                        : const Icon(Icons.android),
                      title: Text(app.name),
                      subtitle: Text(app.id, style: const TextStyle(fontSize: 10)),
                      trailing: Switch(
                        value: isBlocked,
                        onChanged: (_) => _toggleBlock(app.id),
                        activeColor: Colors.redAccent,
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
