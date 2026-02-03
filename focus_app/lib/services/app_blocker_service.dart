import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../windows_process_monitor.dart';
import 'package:device_apps/device_apps.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'background_service.dart';

class AppInfo {
  final String id;
  final String name;
  final dynamic icon; // Uint8List for Android, String (Base64) for Windows
  final bool isSystemApp;
  
  AppInfo({
    required this.id, 
    required this.name, 
    this.icon,
    this.isSystemApp = false,
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
        return apps.map((a) => AppInfo(
          id: a.packageName,
          name: a.appName,
          icon: a is ApplicationWithIcon ? a.icon : null, // Uint8List
          isSystemApp: a.systemApp,
        )).toList();
      } catch (e) {
        debugPrint("Error getting apps: $e");
        return [];
      }
    }
    return [];
  }

  static Future<void> setBlockList(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blocked_apps', ids);
    
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
