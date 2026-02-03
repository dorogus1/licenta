import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ProcessInfo {
  final String name;
  final int pid;
  ProcessInfo({required this.name, required this.pid});

  factory ProcessInfo.fromMap(Map<dynamic, dynamic> m) {
    return ProcessInfo(name: m['name'] as String? ?? '', pid: m['pid'] as int? ?? 0);
  }
}

class WindowsProcessMonitor {
  static const MethodChannel _channel = MethodChannel('focus_app/process_monitor');

  static final StreamController<ProcessInfo> _blockedController = StreamController.broadcast();

  static Stream<ProcessInfo> get onBlocked => _blockedController.stream;

  static void _handleMethodCall(MethodCall call) {
    if (call.method == 'onBlocked') {
      final arg = call.arguments;
      if (arg is Map) {
        final p = ProcessInfo.fromMap(Map<dynamic, dynamic>.from(arg));
        _blockedController.add(p);
      }
    }
  }

  static Future<List<ProcessInfo>> getRunningProcesses() async {
    try {
      final res = await _channel.invokeMethod('getRunningProcesses');
      if (res is List) {
        return res.map((e) => ProcessInfo.fromMap(Map<dynamic, dynamic>.from(e))).toList();
      }
    } on PlatformException catch (e) {
      debugPrint('getRunningProcesses error: $e');
    }
    return [];
  }

  static Future<List<Map<String, dynamic>>> getInstalledApps() async {
    try {
      final res = await _channel.invokeMethod('getInstalledApps');
      if (res is List) {
        return res.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('getInstalledApps error: $e');
    }
    return [];
  }

  static Future<void> setBlockList(List<String> names) async {
    await _channel.invokeMethod('setBlockList', names);
  }

  static Future<void> startMonitor() async {
    await _channel.invokeMethod('startMonitor');
  }

  static Future<void> stopMonitor() async {
    await _channel.invokeMethod('stopMonitor');
  }

  static Future<bool> isRunning() async {
    try {
      final res = await _channel.invokeMethod('isRunning');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> getForegroundApp() async {
    try {
      final res = await _channel.invokeMethod('getForegroundApp');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
    } catch (e) {
      debugPrint('getForegroundApp error: $e');
    }
    return {};
  }

  // Initialize the handler. Call once at app start.
  static void init() {
    _channel.setMethodCallHandler((call) async {
      _handleMethodCall(call);
    });
  }
}
