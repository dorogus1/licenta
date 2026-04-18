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
import 'package:system_alert_window/system_alert_window.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'focus_app_service',
    'Focus App Service',
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
      initialNotificationTitle: 'Focus Shield',
      initialNotificationContent: 'Monitoring...',
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
  String? lastActiveEventId;
  bool isOverlayShowing = false;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Listen for overlay button clicks
  SystemAlertWindow.registerOnClickListener((tag) {
    if (tag == "back_to_focus") {
      SystemAlertWindow.closeSystemWindow(prefMode: SystemWindowPrefMode.OVERLAY);
      isOverlayShowing = false;
      DeviceApps.openApp("com.example.focus_app");
    }
  });

  // Listen to UI
  service.on('setBlockList').listen((event) {
    if (event != null && event['list'] != null) {
      blockedApps = List<String>.from(event['list']);
      prefs.setStringList('blocked_apps', blockedApps);
    }
  });

  service.on('startFocus').listen((event) {
    isFocusing = true;
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(title: "Focus Mode On", content: "Blocking active apps");
    }
  });

  service.on('stopFocus').listen((event) {
    isFocusing = false;
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(title: "Focus Shield", content: "Idle");
    }
    if (isOverlayShowing) {
      SystemAlertWindow.closeSystemWindow(prefMode: SystemWindowPrefMode.OVERLAY);
      isOverlayShowing = false;
    }
  });

  // Calendar Check Loop (Optimized to 5 minutes)
  Timer.periodic(const Duration(minutes: 5), (timer) async {
    final token = prefs.getString('google_access_token');
    if (token == null) return;

    final now = DateTime.now();
    final timeMin = now.subtract(const Duration(minutes: 10)).toUtc().toIso8601String();
    final timeMax = now.add(const Duration(minutes: 10)).toUtc().toIso8601String();

    final url = 'https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=$timeMin&timeMax=$timeMax&singleEvents=true';

    try {
      final response = await http.get(Uri.parse(url), headers: {'Authorization': 'Bearer $token'});
      if (response.statusCode == 200) {
        final events = json.decode(response.body)['items'] ?? [];
        bool foundActive = false;
        String? currentEventId;
        String? currentEventTitle;

        for (var event in events) {
          final start = DateTime.parse(event['start']['dateTime'] ?? event['start']['date']);
          final end = DateTime.parse(event['end']['dateTime'] ?? event['end']['date']);

          if (now.isAfter(start) && now.isBefore(end)) {
            foundActive = true;
            currentEventId = event['id'];
            currentEventTitle = event['summary'];
            break;
          }
        }

        if (foundActive && !isFocusing) {
          isFocusing = true;
          lastActiveEventId = currentEventId;
          service.invoke('startFocus'); 
        } else if (!foundActive && isFocusing && lastActiveEventId != null) {
          isFocusing = false;
          lastActiveEventId = null;
          service.invoke('stopFocus');
          
          await flutterLocalNotificationsPlugin.show(
            999,
            'Sesiune Focus Finalizată',
            'Ai reușit să termini: $currentEventTitle? Apasă pentru feedback.',
            const NotificationDetails(
              android: AndroidNotificationDetails('focus_app_service', 'Focus Notifications', importance: Importance.high),
            ),
          );
        }
      }
    } catch (_) {}
  });

  // Monitoring Loop
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    if (!isFocusing || blockedApps.isEmpty) return;

    try {
      final DateTime now = DateTime.now();
      List<UsageInfo> stats = await UsageStats.queryUsageStats(now.subtract(const Duration(seconds: 5)), now);
      stats.sort((a, b) => int.parse(b.lastTimeUsed ?? "0").compareTo(int.parse(a.lastTimeUsed ?? "0")));
      
      if (stats.isNotEmpty) {
        String currentPkg = stats.first.packageName ?? "";
        if (currentPkg != "com.example.focus_app" && blockedApps.contains(currentPkg)) {
          if (!isOverlayShowing) {
            SystemWindowHeader header = SystemWindowHeader(
              title: SystemWindowText(text: "", fontSize: 0, textColor: Colors.transparent),
              decoration: SystemWindowDecoration(startColor: Colors.transparent),
            );
            SystemWindowBody body = SystemWindowBody(
              rows: [
                EachRow(
                  columns: [
                    EachColumn(
                      text: SystemWindowText(text: "APLICAȚIE BLOCATĂ", fontSize: 24, textColor: Colors.white),
                    ),
                  ],
                  gravity: ContentGravity.CENTER,
                ),
                EachRow(
                  columns: [
                    EachColumn(
                      text: SystemWindowText(
                        text: "\nTimpul tău este prețios! Rămâi concentrat pe ceea ce contează cu adevărat.", 
                        fontSize: 18, 
                        textColor: Colors.white.withOpacity(0.9)
                      ),
                    ),
                  ],
                  gravity: ContentGravity.CENTER,
                ),
              ],
              padding: SystemWindowPadding(left: 24, right: 24, bottom: 24, top: 24),
              decoration: SystemWindowDecoration(
                startColor: Colors.black.withOpacity(0.85),
                endColor: Colors.black.withOpacity(0.85),
              ),
            );
            SystemWindowFooter footer = SystemWindowFooter(
              buttons: [
                SystemWindowButton(
                  text: SystemWindowText(text: "ÎNAPOI LA FOCUS", fontSize: 14, textColor: Colors.white),
                  tag: "back_to_focus",
                  width: 0,
                  height: SystemWindowButton.WRAP_CONTENT,
                  decoration: SystemWindowDecoration(
                    startColor: const Color(0xFF6C63FF),
                    endColor: const Color(0xFF6C63FF),
                    borderRadius: 12,
                  ),
                )
              ],
              padding: SystemWindowPadding(left: 32, right: 32, bottom: 40, top: 0),
              decoration: SystemWindowDecoration(startColor: Colors.transparent),
            );

            await SystemAlertWindow.showSystemWindow(
              height: -1, // MATCH_PARENT
              width: -1,  // MATCH_PARENT
              header: header,
              body: body,
              footer: footer,
              margin: SystemWindowMargin(left: 0, right: 0, top: 0, bottom: 0),
              gravity: SystemWindowGravity.CENTER,
              prefMode: SystemWindowPrefMode.OVERLAY
            );
            isOverlayShowing = true;
          }
        } else {
          if (isOverlayShowing) {
            await SystemAlertWindow.closeSystemWindow(prefMode: SystemWindowPrefMode.OVERLAY);
            isOverlayShowing = false;
          }
        }
      }
    } catch (_) {}
  });
}
