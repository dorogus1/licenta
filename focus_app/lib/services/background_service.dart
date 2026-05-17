import "dart:async";
import "dart:io";
import "dart:ui";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_background_service/flutter_background_service.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:usage_stats/usage_stats.dart";
import "package:device_apps/device_apps.dart";
import "package:shared_preferences/shared_preferences.dart";

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    "focus_app_service",
    "Focus App Service",
    description: "Monitoring running apps...",
    importance: Importance.low,
  );
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: "focus_app_service",
      initialNotificationTitle: "Focus Shield",
      initialNotificationContent: "Monitoring...",
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma("vm:entry-point")
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma("vm:entry-point")
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  List<String> blockedApps = prefs.getStringList("blocked_apps") ?? [];
  bool isFocusing = false;
  service.on("setBlockList").listen((event) {
    if (event != null && event["list"] != null) {
      blockedApps = List<String>.from(event["list"]);
      prefs.setStringList("blocked_apps", blockedApps);
    }
  });
  service.on("startFocus").listen((event) {
    isFocusing = true;
  });
  service.on("stopFocus").listen((event) {
    isFocusing = false;
  });
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (!isFocusing || blockedApps.isEmpty) return;
    try {
      final DateTime now = DateTime.now();
      List<UsageInfo> stats = await UsageStats.queryUsageStats(
        now.subtract(const Duration(seconds: 5)),
        now,
      );
      stats.sort(
        (a, b) => int.parse(
          b.lastTimeUsed ?? "0",
        ).compareTo(int.parse(a.lastTimeUsed ?? "0")),
      );
      if (stats.isNotEmpty) {
        String currentPkg = stats.first.packageName ?? "";
        if (currentPkg != "com.example.focus_app" &&
            blockedApps.contains(currentPkg)) {
          service.invoke("blockedAppDetected", {"packageName": currentPkg});
          DeviceApps.openApp("com.example.focus_app");
        }
      }
    } catch (_) {}
  });
}
