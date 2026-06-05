import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/services.dart';
import 'l10n/app_localizations.dart';
import 'auth_service.dart';
import 'services/app_blocker_service.dart';
import 'todo_page.dart';
import 'mobile_apps_page.dart';
import 'windows_apps_page.dart';
import 'windows_process_monitor.dart';
import 'settings_page.dart';

class HomePage extends StatefulWidget {
  final VoidCallback toggleTheme;
  final VoidCallback onLogout;
  final Function(Locale) setLocale;
  final Locale? currentLocale;
  final bool isDark;
  final AuthService authService;

  const HomePage({
    super.key,
    required this.toggleTheme,
    required this.isDark,
    required this.onLogout,
    required this.authService,
    required this.setLocale,
    required this.currentLocale,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const int defaultTime = 25 * 60;
  int timeLeft = defaultTime;
  int totalTime = defaultTime;
  Timer? _timer;
  bool running = false;
  late AnimationController _pulseController;
  static const _killerChannel = MethodChannel('com.example.focus_app/app_killer');
  StreamSubscription? _sessionSubscription;
  StreamSubscription? _blockedAppSubscription;
  StreamSubscription? _windowsBlockedSubscription;
  List<TodoTask> _todayTasks = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppBlockerService.init();
    _loadTodayTasks();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _sessionSubscription = widget.authService.sessionStream.listen((update) {
      if (update.isActive) {
        if (update.endTime != null) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final remaining = ((update.endTime! - now) / 1000).floor();

          if (remaining > 0) {
             if (!running || (timeLeft - remaining).abs() > 2) {
               setState(() {
                 timeLeft = remaining;
               });
               if (!running) {
                 startTimer(fromSync: true);
               }
             }
          } else {
            stopTimer(fromSync: true);
          }
        }
      } else {
        if (running) {
          stopTimer(fromSync: true);
        }
      }
    });

    if (Platform.isAndroid || Platform.isIOS) {
      _blockedAppSubscription = FlutterBackgroundService().on("blockedAppDetected").listen((event) {
        if (event != null && event["packageName"] != null) {
          _handleBlockedApp(event["packageName"]);
        }
      });
    }

    if (Platform.isWindows) {
      _windowsBlockedSubscription = WindowsProcessMonitor.onBlocked.listen((process) {
        _handleBlockedApp(process.name);
      });
    }
  }

  Future<void> _handleBlockedApp(String packageName) async {
    // Try to kill the process
    try {
      if (Platform.isAndroid) {
        await _killerChannel.invokeMethod('killProcess', {'packageName': packageName});
      }
    } catch (e) {
      debugPrint("Failed to kill process: $e");
    }

    if (mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.block, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(l10n.appBlocked)),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _loadTodayTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksJson = prefs.getString('todo_tasks');
    if (tasksJson != null) {
      final List<dynamic> decoded = json.decode(tasksJson);
      final allTasks = decoded.map((item) => TodoTask.fromJson(item)).toList();
      final now = DateTime.now();
      setState(() {
        _todayTasks = allTasks.where((t) {
          return t.startTime.year == now.year && 
                 t.startTime.month == now.month && 
                 t.startTime.day == now.day &&
                 !t.isCompleted;
        }).toList();
        _todayTasks.sort((a, b) => a.startTime.compareTo(b.startTime));
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionSubscription?.cancel();
    _blockedAppSubscription?.cancel();
    _windowsBlockedSubscription?.cancel();
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      widget.authService.updatePresence('offline');
    } else if (state == AppLifecycleState.resumed) {
      widget.authService.updatePresence('online');
      _loadTodayTasks();
    }
  }

  String formatTime(int t) {
    final m = t ~/ 60;
    final s = t % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void startTimer({bool fromSync = false}) {
    if (running) return;
    setState(() => running = true);

    if (!fromSync) {
      widget.authService.updateFocusSession(true, DateTime.now().millisecondsSinceEpoch + (timeLeft * 1000));
    }

    AppBlockerService.startFocus();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (timeLeft > 0) {
        setState(() => timeLeft--);
      } else {
        stopTimer();
        _showFeedbackDialog();
      }
    });
  }

  void stopTimer({bool fromSync = false}) {
    if (!running) return;
    setState(() => running = false);

    if (!fromSync) {
      widget.authService.updateFocusSession(false, null);
    }

    _timer?.cancel();
    AppBlockerService.stopFocus();
  }

  void _showFeedbackDialog() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.celebration, size: 64, color: Colors.orangeAccent),
            const SizedBox(height: 24),
            Text(l10n.sessionFinished, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(l10n.achieveGoal, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.excellent), duration: const Duration(seconds: 2)));
                    },
                    icon: const Icon(Icons.check),
                    label: Text(l10n.yesDone),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showExtraTimeDialog();
                    },
                    icon: const Icon(Icons.more_time),
                    label: Text(l10n.extraTime),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExtraTimeDialog() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.howMuchExtra, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildExtraTimeOption(5, Colors.blue),
                _buildExtraTimeOption(10, Colors.indigo),
                _buildExtraTimeOption(15, Colors.purple),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildExtraTimeOption(int minutes, Color color) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        InkWell(
          onTap: () {
            adjustTime(minutes * 60);
            startTimer();
            Navigator.pop(context);
          },
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text('+$minutes', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(l10n.min, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  void adjustTime(int seconds) {
    setState(() {
      timeLeft = (timeLeft + seconds).clamp(60, 120 * 60);
      totalTime = timeLeft;
    });
  }

  void resetTimer() {
    stopTimer();
    setState(() {
      timeLeft = defaultTime;
      totalTime = defaultTime;
    });
  }

  @override
  Widget build(BuildContext context) {
    double progress = timeLeft / totalTime;
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(l10n.appTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: l10n.tasksCalendar,
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TodoPage(authService: widget.authService)),
              );
              _loadTodayTasks();
            },
          ),
          if (Platform.isWindows || Platform.isAndroid)
            IconButton(
              icon: const Icon(Icons.app_blocking),
              tooltip: l10n.blockApps,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => Platform.isWindows 
                  ? const WindowsAppsPage() 
                  : const MobileAppsPage()),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.settings,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsPage(
                authService: widget.authService,
                isDark: widget.isDark,
                onLogout: widget.onLogout,
                toggleTheme: widget.toggleTheme,
                setLocale: widget.setLocale,
                currentLocale: widget.currentLocale,
              )),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  if (running)
                    FadeTransition(
                      opacity: Tween(begin: 0.0, end: 0.3).animate(_pulseController),
                      child: Container(
                        width: 320,
                        height: 320,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 15,
                      backgroundColor: colorScheme.surfaceVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        running ? colorScheme.secondary : colorScheme.primary.withOpacity(0.3),
                      ),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatTime(timeLeft),
                        style: const TextStyle(
                          fontSize: 84,
                          fontWeight: FontWeight.w100,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: running ? colorScheme.secondary.withOpacity(0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          running ? l10n.focusing : l10n.ready,
                          style: TextStyle(
                            letterSpacing: 4,
                            fontSize: 14,
                            color: running ? colorScheme.secondary : colorScheme.onBackground.withOpacity(0.4),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 60),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildControlButton(
                    icon: Icons.remove,
                    onPressed: () => adjustTime(-5 * 60),
                  ),
                  const SizedBox(width: 32),
                  FloatingActionButton.large(
                    onPressed: running ? stopTimer : startTimer,
                    elevation: 4,
                    backgroundColor: running 
                        ? Colors.orangeAccent 
                        : colorScheme.primary,
                    foregroundColor: Colors.white,
                    child: Icon(
                      running ? Icons.pause : Icons.play_arrow, 
                      size: 48,
                    ),
                  ),
                  const SizedBox(width: 32),
                  _buildControlButton(
                    icon: Icons.add,
                    onPressed: () => adjustTime(5 * 60),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              TextButton.icon(
                onPressed: resetTimer,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(l10n.resetTimer),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onBackground.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 40),
              // Today's Tasks Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.todayTasks,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5, color: Colors.grey),
                        ),
                        TextButton(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => TodoPage(authService: widget.authService)),
                            );
                            _loadTodayTasks();
                          },
                          child: Text(l10n.viewAll),
                        ),
                      ],
                    ),
                    if (_todayTasks.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        child: Text(l10n.noUpcomingTasks, style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                      )
                    else
                      ..._todayTasks.take(3).map((task) => Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.circle, size: 12, color: colorScheme.primary),
                          title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          trailing: Text(DateFormat.Hm().format(task.startTime), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                      )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.1)),
      ),
      child: IconButton(
        icon: Icon(icon),
        iconSize: 24,
        onPressed: onPressed,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
