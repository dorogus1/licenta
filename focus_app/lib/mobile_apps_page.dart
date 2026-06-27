import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
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
  List<AppInfo> suggested = [];
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
    final l10n = AppLocalizations.of(context)!;
    // 1. Usage Stats
    bool usageGranted = await UsageStats.checkUsagePermission() ?? false;
    if (!usageGranted && mounted) {
      await showDialog(
        context: context, 
        builder: (ctx) => AlertDialog(
          title: Text(l10n.permissionRequired),
          content: Text(l10n.usageAccessContent),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () {
                UsageStats.grantUsagePermission();
                Navigator.pop(ctx);
              }, 
              child: Text(l10n.openSettings)
            ),
          ],
        )
      );
    }

    // 2. Draw Over Other Apps
    if (await Permission.systemAlertWindow.status.isDenied && mounted) {
       await showDialog(
        context: context, 
        builder: (ctx) => AlertDialog(
          title: Text(l10n.permissionRequired),
          content: Text(l10n.displayOverAppsContent),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            ElevatedButton(
              onPressed: () async {
                await Permission.systemAlertWindow.request();
                Navigator.pop(ctx);
              }, 
              child: Text(l10n.grant)
            ),
          ],
        )
      );
    }
    
    // 3. Notification
    if (await Permission.notification.status.isDenied) {
      await Permission.notification.request();
    }
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    blocked = prefs.getStringList('blocked_apps') ?? [];
    
    try {
      final apps = await AppBlockerService.getInstalledApps();
      
      // Remove ourselves
      apps.removeWhere((app) => app.id == 'com.example.focus_app'); 

      // 3 hours = 10,800,000 ms (for main suggestions)
      const suggestedThreshold = 3 * 60 * 60 * 1000;
      
      final suggestedApps = apps.where((app) => 
        (app.averageUsageMs ?? 0) >= suggestedThreshold && 
        !blocked.contains(app.id)
      ).toList();
      
      suggestedApps.sort((a, b) => (b.averageUsageMs ?? 0).compareTo(a.averageUsageMs ?? 0));

      // Custom Sort for All Apps:
      // Priority 1: Blocked apps
      // Priority 2: Unblocked apps
      // Within groups: Sort by usage (highest first), then name
      apps.sort((a, b) {
        bool aBlocked = blocked.contains(a.id);
        bool bBlocked = blocked.contains(b.id);

        if (aBlocked != bBlocked) {
          return aBlocked ? -1 : 1; // Blocked apps first
        }
        
        // Both same blocked status, sort by usage descending
        double aUsage = a.averageUsageMs ?? 0;
        double bUsage = b.averageUsageMs ?? 0;
        
        if (aUsage != bUsage) {
          return bUsage.compareTo(aUsage);
        }
        
        // If usage same, sort alphabetically
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (mounted) {
        setState(() {
          installed = apps;
          filtered = apps;
          suggested = suggestedApps;
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
      suggested.removeWhere((app) => blocked.contains(app.id));
    });
    await AppBlockerService.setBlockList(blocked);
  }

  String _formatDuration(double ms) {
    final l10n = AppLocalizations.of(context)!;
    int minutes = (ms / (1000 * 60)).round();
    int hours = minutes ~/ 60;
    int remainingMinutes = minutes % 60;
    if (hours > 0) {
      return '$hours${l10n.h} $remainingMinutes${l10n.mPerDay}';
    }
    return '$minutes${l10n.mPerDay}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.blockApps),
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: l10n.searchApps,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  children: [
                    if (suggested.isNotEmpty && searchQuery.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.lightbulb_outline, color: Colors.orangeAccent),
                            const SizedBox(width: 8),
                            Text(
                              l10n.suggestedToBlock,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                      ...suggested.map((app) => _buildAppTile(app, true)),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          l10n.allApps,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ],
                    ...filtered.map((app) => _buildAppTile(app, false)),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppTile(AppInfo app, bool isSuggested) {
    final l10n = AppLocalizations.of(context)!;
    final isBlocked = blocked.contains(app.id);
    
    // Highlight unblocked apps with > 2h usage
    const highlightThreshold = 2 * 60 * 60 * 1000;
    final shouldHighlight = !isBlocked && (app.averageUsageMs ?? 0) >= highlightThreshold && !isSuggested;

    return Container(
      color: shouldHighlight ? Colors.orangeAccent.withValues(alpha: 0.05) : null,
      child: ListTile(
        leading: app.icon != null && app.icon is Uint8List 
          ? Image.memory(app.icon as Uint8List, width: 40, height: 40)
          : const Icon(Icons.android),
        title: Text(app.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(app.id, style: const TextStyle(fontSize: 10)),
            if (app.averageUsageMs != null && app.averageUsageMs! > 0)
              Text(
                l10n.avgUsage(_formatDuration(app.averageUsageMs!)),
                style: TextStyle(
                  fontSize: 11, 
                  color: (isSuggested || shouldHighlight) ? Colors.redAccent : Colors.grey[600],
                  fontWeight: (isSuggested || shouldHighlight) ? FontWeight.bold : FontWeight.normal,
                ),
              ),
          ],
        ),
        trailing: Switch(
          value: isBlocked,
          onChanged: (_) => _toggleBlock(app.id),
          activeThumbColor: Colors.redAccent,
        ),
      ),
    );
  }
}
