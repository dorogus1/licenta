import 'dart:io';
import 'package:flutter/foundation.dart';
import '../windows_process_monitor.dart';
import 'package:device_apps/device_apps.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_service.dart';
import '../auth_service.dart';
import 'package:usage_stats/usage_stats.dart';

class AppInfo {
  final String id;
  final String name;
  final dynamic icon; // Uint8List for Android, String (Base64) for Windows
  final bool isSystemApp;
  double? averageUsageMs;
  
  AppInfo({
    required this.id, 
    required this.name, 
    this.icon,
    this.isSystemApp = false,
    this.averageUsageMs,
  });
}

class AppBlockerService {
  static Future<void> init() async {
    if (Platform.isWindows) {
      WindowsProcessMonitor.init();
    } else if (Platform.isAndroid) {
       await initializeBackgroundService();
    }
  }

  static Future<List<AppInfo>> getInstalledApps() async {
    if (Platform.isWindows) {
      final apps = await WindowsProcessMonitor.getInstalledApps();
      return apps.map((a) => AppInfo(
        id: a['exe'] ?? a['name'],
        name: a['name'],
        icon: a['iconData'], // Base64 string
      )).toList();
    } else if (Platform.isAndroid) {
      try {
        List<Application> apps = await DeviceApps.getInstalledApplications(
          includeAppIcons: true,
          includeSystemApps: true,
          onlyAppsWithLaunchIntent: true
        );
        
        // Get usage stats to populate suggestions
        Map<String, double> usageAverages = await getWeeklyUsageAverages();

        return apps.map((a) => AppInfo(
          id: a.packageName,
          name: a.appName,
          icon: a is ApplicationWithIcon ? a.icon : null, // Uint8List
          isSystemApp: a.systemApp,
          averageUsageMs: usageAverages[a.packageName],
        )).toList();
      } catch (e) {
        debugPrint("Error getting apps: $e");
        return [];
      }
    }
    return [];
  }

  static Future<Map<String, double>> getWeeklyUsageAverages() async {
    if (!Platform.isAndroid) return {};
    
    try {
      DateTime now = DateTime.now();
      DateTime start = now.subtract(const Duration(days: 3));
      
      List<UsageInfo> stats = await UsageStats.queryUsageStats(start, now);
      Map<String, int> totalUsage = {};
      
      for (var info in stats) {
        if (info.packageName == null) continue;
        int time = int.parse(info.totalTimeInForeground ?? '0');
        totalUsage[info.packageName!] = (totalUsage[info.packageName] ?? 0) + time;
      }
      
      Map<String, double> averages = {};
      totalUsage.forEach((pkg, total) {
        averages[pkg] = total / 3.0; // Daily average in ms (last 3 days)
      });
      
      return averages;
    } catch (e) {
      debugPrint("Error querying usage stats: $e");
      return {};
    }
  }

  static Future<void> setBlockList(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_apps', ids);
    
    // Sync to Firebase for extension/web
    try {
      final authService = AuthService();
      await authService.updateBlockedApps(ids);
    } catch (e) {
      debugPrint("Firebase sync error: $e");
    }
    
    if (Platform.isWindows) {
      await WindowsProcessMonitor.setBlockList(ids);
    } else if (Platform.isAndroid) {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke("setBlockList", {"list": ids});
      }
    }
  }

  static Future<void> startFocus() async {
    if (Platform.isWindows) {
      await WindowsProcessMonitor.startMonitor();
    } else if (Platform.isAndroid) {
      final service = FlutterBackgroundService();
      if (!(await service.isRunning())) {
        await service.startService();
      }
      service.invoke("startFocus");
    }
  }

  static Future<void> stopFocus() async {
    if (Platform.isWindows) {
      await WindowsProcessMonitor.stopMonitor();
    } else if (Platform.isAndroid) {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) {
        service.invoke("stopFocus");
      }
    }
  }
}
