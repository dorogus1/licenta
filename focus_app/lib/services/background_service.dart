import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:device_apps/device_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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

  // Calendar Check Loop
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    final token = prefs.getString('google_access_token');
    if (token == null) return;

    final now = DateTime.now().toUtc();
    // Check events that are around current time
    final timeMin = now.subtract(const Duration(hours: 1)).toIso8601String();
    final timeMax = now.add(const Duration(hours: 1)).toIso8601String();

    final url = 'https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=$timeMin&timeMax=$timeMax&singleEvents=true&orderBy=startTime';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final events = data['items'] ?? [];
        bool anyActive = false;
        String? activeTitle;

        for (var event in events) {
          final startStr = event['start']['dateTime'] ?? event['start']['date'];
          final endStr = event['end']['dateTime'] ?? event['end']['date'];
          final start = DateTime.parse(startStr).toUtc();
          final end = DateTime.parse(endStr).toUtc();

          if (now.isAfter(start) && now.isBefore(end)) {
            anyActive = true;
            activeTitle = event['summary'];
            break;
          }
        }

        if (anyActive && !isFocusing) {
          isFocusing = true;
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Focus Mode On (Calendar)",
              content: "Active event: $activeTitle",
            );
          }
          debugPrint("Background Service: Focus started by Calendar event: $activeTitle");

          // Sync to Firebase
          final userId = prefs.getString('auth_user_id');
          final authToken = prefs.getString('auth_token');
          if (userId != null && authToken != null) {
            final url = 'https://focus-shild-default-rtdb.europe-west1.firebasedatabase.app/users/$userId/focus_session.json?auth=$authToken';
            http.put(
              Uri.parse(url),
              body: json.encode({
                'isActive': true,
                'updatedBy': 'mobile_calendar',
                'lastUpdatedAt': DateTime.now().millisecondsSinceEpoch,
                'eventTitle': activeTitle
              }),
            ).catchError((e) => debugPrint("Firebase sync error: $e"));
          }
        } else if (!anyActive && isFocusing) {
            // Optional: Auto-stop focus when event ends? 
            // User might want to keep it on, but if they want "crazy" sync, let's auto-start at least.
            // For now, let's only auto-start.
        }
      }
    } catch (e) {
      debugPrint("Calendar background check error: $e");
    }
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
