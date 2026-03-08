import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'windows_process_monitor.dart';

class WindowsAppsPage extends StatefulWidget {
  const WindowsAppsPage({super.key});

  @override
  State<WindowsAppsPage> createState() => _WindowsAppsPageState();
}

class _WindowsAppsPageState extends State<WindowsAppsPage> {
  List<Map<String, dynamic>> installed = [];
  List<String> blocked = [];
  List<String> blockedDisplay = []; 
  static const String _kBlockedKey = 'blocked_apps';
  String searchQuery = '';
  StreamSubscription? _blockedSubscription;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _blockedSubscription = WindowsProcessMonitor.onBlocked.listen((p) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Blocked ${p.name}', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
    _loadBlockedFromPrefs().then((_) => _loadInstalled());
  }

  @override
  void dispose() {
    _blockedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadInstalled() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    
    try {
      final res = await WindowsProcessMonitor.getInstalledApps();
      if (!mounted) return;
      
      setState(() {
        installed = res;
        _isLoading = false;
      });
      _rebuildBlockedDisplay();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('Error loading apps: $e');
    }
  }

  void _toggleBlock(String exeName, String displayName) async {
    exeName = exeName.toLowerCase();
    
    if (blocked.contains(exeName)) {
      blocked.remove(exeName);
    } else {
      blocked.add(exeName);
    }

    _rebuildBlockedDisplay();
    await WindowsProcessMonitor.setBlockList(blocked);
    await _saveBlockedToPrefs();
    setState(() {});
  }
  
  void _removeBlocked(String id) async {
    blocked.remove(id);
    _rebuildBlockedDisplay();
    await WindowsProcessMonitor.setBlockList(blocked);
    await _saveBlockedToPrefs();
    setState(() {});
  }

  void _showManualBlockDialog() {
    String manualInput = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Block Custom Process'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the exact process name (e.g. leagueclient.exe)'),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Process name',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => manualInput = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (manualInput.trim().isNotEmpty) {
                _toggleBlock(manualInput.trim(), manualInput.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _startWindowPicker() {
    int countdown = 5;
    StateSetter? dialogSetState;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          dialogSetState = setState;
          return AlertDialog(
            title: const Text('Target Mode'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.center_focus_strong, size: 48, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  'Switch to the app you want to block now!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                Text(
                  '$countdown',
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('seconds remaining', style: TextStyle(color: Colors.grey)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      ),
    ).then((_) => countdown = -1);

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (countdown < 0) {
        timer.cancel();
        return;
      }
      
      countdown--;
      if (countdown > 0) {
        dialogSetState?.call(() {});
      } else {
        timer.cancel();
        if (mounted) Navigator.pop(context);
        
        final data = await WindowsProcessMonitor.getForegroundApp();
        final exe = data['exe'] as String? ?? '';
        
        if (exe.isNotEmpty && exe.toLowerCase() != 'focus_app.exe' && exe.toLowerCase() != 'runner.exe') {
          if (!mounted) return;
          showDialog(
            context: context, 
            builder: (ctx) => AlertDialog(
              title: const Text('Block this app?'),
              content: Text('Detected: $exe\n\nDo you want to block this process?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('No')),
                ElevatedButton(
                  onPressed: () {
                    _toggleBlock(exe, exe);
                    Navigator.pop(ctx);
                  },
                  child: const Text('Block'),
                ),
              ],
            )
          );
        }
      }
    });
  }

  Future<void> _saveBlockedToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBlockedKey, blocked);
  }

  Future<void> _loadBlockedFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kBlockedKey) ?? <String>[];
    setState(() {
      blocked = List<String>.from(list);
    });
    try {
      await WindowsProcessMonitor.setBlockList(blocked);
    } catch (_) {}
    _rebuildBlockedDisplay();
  }

  void _rebuildBlockedDisplay() {
    blockedDisplay = [];
    for (final id in blocked) {
      final match = installed.firstWhere(
          (i) => ((i['exe'] as String?)?.toLowerCase() == id),
          orElse: () => <String, dynamic>{});
      
      if (match.isNotEmpty) {
        blockedDisplay.add(match['name'] as String? ?? id);
      } else {
        blockedDisplay.add(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = searchQuery.toLowerCase();
    final filtered = installed.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      final exe = (item['exe'] as String? ?? '').toLowerCase();
      return name.contains(term) || exe.contains(term);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Apps'),
        elevation: 0,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           FloatingActionButton(
            heroTag: 'target_mode',
            onPressed: _startWindowPicker,
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            child: const Icon(Icons.center_focus_strong),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'manual_add',
            onPressed: _showManualBlockDialog,
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: (v) => setState(() => searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search apps...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          
          if (blocked.isNotEmpty)
             Container(
               width: double.infinity,
               padding: const EdgeInsets.all(12),
               child: Wrap(
                 spacing: 8,
                 runSpacing: 8,
                 children: List.generate(blocked.length, (index) {
                   final id = blocked[index];
                   final display = index < blockedDisplay.length ? blockedDisplay[index] : id;
                   return Chip(
                     label: Text(display, style: const TextStyle(fontSize: 12)),
                     onDeleted: () => _removeBlocked(id),
                   );
                 }),
               ),
             ),

          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                final name = item['name'] as String? ?? 'Unknown';
                final exe = item['exe'] as String? ?? '';
                final isBlocked = blocked.contains(exe.toLowerCase());

                Uint8List? iconBytes;
                final iconDataStr = item['iconData'] as String? ?? '';
                if (iconDataStr.isNotEmpty) {
                  try { iconBytes = base64Decode(iconDataStr); } catch (_) {}
                }

                return ListTile(
                  leading: iconBytes != null 
                      ? Image.memory(iconBytes, width: 32, height: 32)
                      : const Icon(Icons.apps),
                  title: Text(name),
                  subtitle: Text(exe),
                  trailing: Switch(
                    value: isBlocked,
                    onChanged: (val) => _toggleBlock(exe, name),
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