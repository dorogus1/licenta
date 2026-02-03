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
  List<ProcessInfo> processes = [];
  List<Map<String, dynamic>> installed = [];
  List<String> blocked = [];
  List<String> blockedDisplay = []; // Stores the display names of blocked apps
  static const String _kBlockedKey = 'blocked_apps';
  bool showInstalled = true;
  String searchQuery = '';
  StreamSubscription? _blockedSubscription;
  bool _isLoading = false;

  // Known mappings from Display Name (partial match) to actual Process Names
  final Map<String, List<String>> _gameMappings = {
    'league of legends': ['leagueclient.exe', 'league of legends.exe', 'riotclientservices.exe'],
    'valorant': ['valorant.exe', 'valorant-win64-shipping.exe', 'riotclientservices.exe'],
    'counter-strike': ['cs2.exe', 'csgo.exe'],
    'dota 2': ['dota2.exe'],
    'minecraft': ['minecraft.exe', 'javaw.exe', 'minecraftlauncher.exe'],
    'world of warcraft': ['wow.exe', 'wow-64.exe', 'battle.net.exe'],
    'fortnite': ['fortniteclient-win64-shipping.exe', 'fortnitelauncher.exe'],
  };

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
    _refresh();
    _loadBlockedFromPrefs().then((_) => _loadInstalled());
  }

  @override
  void dispose() {
    _blockedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ps = await WindowsProcessMonitor.getRunningProcesses();
    if (mounted) setState(() => processes = ps);
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

  // --- Logic for Blocking ---

  void _toggleBlock(String id, String displayName) async {
    id = id.toLowerCase();
    String lowerDisplay = displayName.toLowerCase();
    
    // 1. Identify all targets (ID + .exe variant + Known Game Mappings)
    Set<String> targets = {};
    targets.add(id);
    if (!id.endsWith('.exe')) targets.add('$id.exe');

    // Check against known mappings
    _gameMappings.forEach((key, processes) {
      if (lowerDisplay.contains(key) || id.contains(key)) {
        targets.addAll(processes);
      }
    });

    // 2. Decide action: If the MAIN id is blocked, we unblock everything. Otherwise block everything.
    bool isCurrentlyBlocked = blocked.contains(id);

    if (isCurrentlyBlocked) {
      // Unblock all targets
      blocked.removeWhere((item) => targets.contains(item));
      _rebuildBlockedDisplay();
    } else {
      // Block all targets
      for (var t in targets) {
        if (!blocked.contains(t)) {
          blocked.add(t);
        }
      }
      // Optimistic display update (for the main one at least)
      if (!blockedDisplay.contains(displayName)) {
        blockedDisplay.add(displayName);
      }
    }

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
                Text(
                  'Switch to the app you want to block now!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
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
    ).then((_) => countdown = -1); // Signal cancellation

    Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (countdown < 0) {
        timer.cancel(); // Dialog closed manually
        return;
      }
      
      countdown--;
      if (countdown > 0) {
        dialogSetState?.call(() {});
      } else {
        timer.cancel();
        if (mounted) Navigator.pop(context); // Close dialog
        
        // Capture
        final data = await WindowsProcessMonitor.getForegroundApp();
        final exe = data['exe'] as String? ?? '';
        
        if (exe.isNotEmpty && exe.toLowerCase() != 'focus_app.exe' && exe.toLowerCase() != 'runner.exe') {
          if (!mounted) return;
          
          // Ask for confirmation
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
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not detect a valid external app.')));
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
          (i) => ((i['exe'] as String?)?.toLowerCase() == id) || ((i['name'] as String?)?.toLowerCase() == id),
          orElse: () => <String, dynamic>{});
      
      if (match.isNotEmpty) {
        blockedDisplay.add(match['name'] as String? ?? id);
      } else {
        // Fallback: try to find in running processes if not in installed list
        final procMatch = processes.firstWhere(
             (p) => p.name.toLowerCase() == id,
             orElse: () => ProcessInfo(name: '', pid: 0));
        
        if (procMatch.name.isNotEmpty) {
           blockedDisplay.add(procMatch.name);
        } else {
           blockedDisplay.add(id);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter logic
    final term = searchQuery.toLowerCase();
    final List<dynamic> currentList = showInstalled ? installed : processes;
    
    final filtered = currentList.where((item) {
      String name = '';
      if (showInstalled) {
        name = (item['name'] as String? ?? '').toLowerCase();
      } else {
        name = (item as ProcessInfo).name.toLowerCase();
      }
      return name.contains(term);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Apps'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           FloatingActionButton(
            heroTag: 'target_mode',
            onPressed: _startWindowPicker,
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            tooltip: 'Target Mode (Detect Active Window)',
            child: const Icon(Icons.center_focus_strong),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'manual_add',
            onPressed: _showManualBlockDialog,
            tooltip: 'Block Custom Process Name',
            child: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          // Header / Search Area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              children: [
                // Segmented Control (Toggle)
                Container(
                  width: double.infinity,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.black26 : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => showInstalled = true),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: showInstalled ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Installed Apps',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: showInstalled ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            showInstalled = false;
                            _refresh(); // Auto refresh running processes
                          }),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: !showInstalled ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Running Processes',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: !showInstalled ? Colors.white : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Search Bar
                TextField(
                  onChanged: (v) => setState(() => searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.black12 : Colors.grey.shade200,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  ),
                ),
              ],
            ),
          ),
          
          // Blocked Apps Chips Header
          if (blocked.isNotEmpty)
             Container(
               width: double.infinity,
               padding: const EdgeInsets.all(12),
               decoration: BoxDecoration(
                 color: Theme.of(context).brightness == Brightness.dark 
                    ? const Color(0xFF2A2A2A) 
                    : Colors.grey.shade100,
                 border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
               ),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   Text(
                     'BLOCKED APPS', 
                     style: TextStyle(
                       fontSize: 12, 
                       fontWeight: FontWeight.bold, 
                       color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), 
                       letterSpacing: 1.2
                     )
                   ),
                   const SizedBox(height: 8),
                   Wrap(
                     spacing: 8,
                     runSpacing: 8,
                     children: List.generate(blocked.length, (index) {
                       final id = blocked[index];
                       final display = index < blockedDisplay.length ? blockedDisplay[index] : id;
                       return Chip(
                         label: Text(display, style: const TextStyle(fontSize: 12)),
                         backgroundColor: Colors.redAccent.withOpacity(0.2),
                         side: BorderSide.none,
                         deleteIcon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                         onDeleted: () => _removeBlocked(id),
                       );
                     }),
                   ),
                 ],
               ),
             ),

          // List
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                
                String name;
                String id; // The value to block (exe name or process name)
                Uint8List? iconBytes;
                
                if (showInstalled) {
                   name = item['name'] as String? ?? 'Unknown';
                   final exe = item['exe'] as String? ?? '';
                   id = exe.isNotEmpty ? exe.toLowerCase() : name.toLowerCase();
                   
                   final iconDataStr = item['iconData'] as String? ?? '';
                   if (iconDataStr.isNotEmpty) {
                     try {
                       iconBytes = base64Decode(iconDataStr);
                     } catch (_) {}
                   }
                } else {
                   final p = item as ProcessInfo;
                   name = p.name;
                   id = p.name.toLowerCase();
                }

                final isBlocked = blocked.contains(id);

                return Card(
                  color: isBlocked 
                      ? Colors.redAccent.withOpacity(0.1) 
                      : Theme.of(context).colorScheme.surface,
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12), 
                    side: isBlocked 
                        ? const BorderSide(color: Colors.redAccent, width: 1) 
                        : BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1))
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 48, 
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: iconBytes != null 
                          ? Padding(padding: const EdgeInsets.all(8.0), child: Image.memory(iconBytes))
                          : Icon(Icons.apps, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4)),
                    ),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: showInstalled 
                        ? Text(id.endsWith('.exe') ? id : '$id.exe', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12))
                        : Text('PID: ${(item as ProcessInfo).pid}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6), fontSize: 12)),
                    trailing: Switch(
                      value: isBlocked,
                      activeColor: Colors.redAccent,
                      onChanged: (val) => _toggleBlock(id, name),
                    ),
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