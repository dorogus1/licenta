import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:device_apps/device_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'focus_app_service', // id
    'Focus App Service', // title
    description: 'Monitoring running apps...',
    importance: Importance.low, 
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'focus_app_service',
      initialNotificationTitle: 'Focus App',
      initialNotificationContent: 'Ready to focus',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  List<String> blockedApps = prefs.getStringList('blocked_apps') ?? [];
  bool isFocusing = false;

  // Listen to UI
  service.on('setBlockList').listen((event) {
    if (event != null && event['list'] != null) {
      final list = event['list'];
      if (list is List) {
        blockedApps = List<String>.from(list);
        prefs.setStringList('blocked_apps', blockedApps);
        debugPrint("Background Service: Block list updated: $blockedApps");
      }
    }
  });

  service.on('startFocus').listen((event) {
    isFocusing = true;
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Focus Mode On",
        content: "Blocking apps is active",
      );
    }
    debugPrint("Background Service: Focus Started");
  });

  service.on('stopFocus').listen((event) {
    isFocusing = false;
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: "Focus App",
        content: "Monitoring idle",
      );
    }
    debugPrint("Background Service: Focus Stopped");
  });
  
  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Monitoring Loop
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (!isFocusing) return;
    if (blockedApps.isEmpty) return;

    try {
      final DateTime endTime = DateTime.now();
      final DateTime startTime = DateTime.now().subtract(const Duration(seconds: 5)); // Check last 5 seconds
      
      // Need usage access permission for this
      List<UsageInfo> events = await UsageStats.queryUsageStats(startTime, endTime);
      
      // Sort by last time used to get the most recent one
      events.sort((a, b) => int.parse(b.lastTimeUsed ?? "0").compareTo(int.parse(a.lastTimeUsed ?? "0")));
      
      if (events.isNotEmpty) {
        String currentPkg = events.first.packageName ?? "";
        
        // If current app is in blocked list
        // Note: currentPkg might be our own app 'com.example.focus_app', check that to avoid loop
        if (currentPkg.isNotEmpty && currentPkg != "com.example.focus_app" && blockedApps.contains(currentPkg)) {
             
             debugPrint("Blocking $currentPkg");
             
             // Launch ourselves to block
             await DeviceApps.openApp("com.example.focus_app");
             
             // Alternative: Show System Alert Window (Overlay)
             // For now, bringing to front is simpler and effective.
        }
      }
    } catch (e) {
      debugPrint("Error in monitor: $e");
    }
  });
}
