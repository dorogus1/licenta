import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'windows_apps_page.dart';
import 'mobile_apps_page.dart';
import 'windows_process_monitor.dart'; // Still needed for some internal types if referenced directly, but better to use facade
import 'services/app_blocker_service.dart';
import 'login_page.dart';
import 'auth_service.dart';
import 'calendar_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.dark;
  bool _isLoggedIn = false;
  bool _isLoadingAuth = true;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final loggedIn = await _authService.isLoggedIn();
    if (mounted) {
      setState(() {
        _isLoggedIn = loggedIn;
        _isLoadingAuth = false;
      });
    }
  }

  void _onLoginSuccess() {
    setState(() {
      _isLoggedIn = true;
    });
  }

  void _onLogout() async {
    await _authService.signOut();
    setState(() {
      _isLoggedIn = false;
    });
  }

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingAuth) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF121212),
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'Focus App',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF03DAC6),
          surface: Colors.white,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF),
          secondary: Color(0xFF03DAC6),
          surface: Color(0xFF1E1E1E),
        ),
        useMaterial3: true,
      ),
      home: _isLoggedIn 
          ? MyHomePage(toggleTheme: toggleTheme, isDark: _themeMode == ThemeMode.dark, onLogout: _onLogout, authService: _authService)
          : LoginPage(onLoginSuccess: _onLoginSuccess, authService: _authService),
    );
  }
}

class ProfileDialog extends StatefulWidget {
  final AuthService authService;
  const ProfileDialog({super.key, required this.authService});

  @override
  State<ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<ProfileDialog> {
  String? email;
  String? currentDeviceId;
  Map<String, dynamic> devices = {};
  Timer? _refreshTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchDevices());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    email = await widget.authService.getUserEmail();
    currentDeviceId = await widget.authService.getDeviceId();
    await _fetchDevices();
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _fetchDevices() async {
    final devs = await widget.authService.getDevices();
    if (mounted) {
      setState(() => devices = devs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.account_circle, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Profile', style: TextStyle(fontSize: 20)),
              if (email != null)
                Text(email!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text('Active Devices', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: _loading 
                ? const Center(child: CircularProgressIndicator())
                : devices.isEmpty 
                  ? const Center(child: Text('No active devices found.'))
                  : ListView.builder(
                      itemCount: devices.length,
                      itemBuilder: (context, index) {
                        final id = devices.keys.elementAt(index);
                        final data = devices[id];
                        final isMe = id == currentDeviceId;
                        
                        final type = data['type'] as String? ?? 'unknown';
                        final name = data['name'] as String? ?? 'Unknown Device';
                        final platform = data['platform'] as String? ?? '';
                        final state = data['state'] as String? ?? 'offline';
                        final lastSeen = data['last_seen'] as int? ?? 0;
                        
                        // Online check logic (similar to extension)
                        final now = DateTime.now().millisecondsSinceEpoch;
                        final isOnline = (state != 'offline') && ((now - lastSeen) < 90000); // 90s timeout

                        IconData icon;
                        if (type == 'extension') icon = Icons.language;
                        else if (type == 'windows') icon = Icons.laptop_windows;
                        else if (type == 'mobile') icon = Icons.smartphone;
                        else icon = Icons.devices;

                        return ListTile(
                          leading: Icon(icon, color: isMe ? Theme.of(context).colorScheme.primary : null),
                          title: Text('$name ${isMe ? '(You)' : ''}', style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text(platform),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isOnline ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isOnline ? Colors.green : Colors.grey),
                            ),
                            child: Text(
                              isOnline ? 'Online' : 'Offline',
                              style: TextStyle(
                                fontSize: 12, 
                                color: isOnline ? Colors.green : Colors.grey
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class MyHomePage extends StatefulWidget {
  final VoidCallback toggleTheme;
  final VoidCallback onLogout;
  final bool isDark;
  final AuthService authService;
  const MyHomePage({super.key, required this.toggleTheme, required this.isDark, required this.onLogout, required this.authService});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin, WidgetsBindingObserver {
  static const int defaultTime = 25 * 60;
  int timeLeft = defaultTime;
  int totalTime = defaultTime;
  Timer? _timer;
  bool running = false;
  late AnimationController _pulseController;
  StreamSubscription? _sessionSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppBlockerService.init();
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionSubscription?.cancel();
    _pulseController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      // App is minimized or hidden
      widget.authService.updatePresence('offline');
    } else if (state == AppLifecycleState.resumed) {
      // App is back
      widget.authService.updatePresence('online');
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
    
    // Sync start only if user clicked
    if (!fromSync) {
      widget.authService.updateFocusSession(true, DateTime.now().millisecondsSinceEpoch + (timeLeft * 1000));
    }

    AppBlockerService.startFocus();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (timeLeft > 0) {
        setState(() => timeLeft--);
      } else {
        stopTimer();
      }
    });
  }

  void stopTimer({bool fromSync = false}) {
    if (!running) return;
    setState(() => running = false);
    
    // Sync stop only if user clicked
    if (!fromSync) {
      widget.authService.updateFocusSession(false, null);
    }

    _timer?.cancel();
    AppBlockerService.stopFocus();
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

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('Focus Timer', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Profile',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => ProfileDialog(authService: widget.authService),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: widget.onLogout,
          ),
          IconButton(
            icon: Icon(widget.isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: 'Toggle Theme',
            onPressed: widget.toggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Schedule',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CalendarPage(authService: widget.authService)),
            ),
          ),
          if (Platform.isWindows || Platform.isAndroid)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Manage Blocked Apps',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => Platform.isWindows 
                  ? const WindowsAppsPage() 
                  : const MobileAppsPage()),
              ),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Timer Circle
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
                    strokeWidth: 20,
                    backgroundColor: colorScheme.surface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      running ? colorScheme.secondary : Colors.grey,
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
                        fontSize: 72,
                        fontWeight: FontWeight.w200,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      running ? 'FOCUSING' : 'PAUSED',
                      style: TextStyle(
                        letterSpacing: 4,
                        color: colorScheme.onBackground.withOpacity(0.6),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 60),
            
            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildControlButton(
                  icon: Icons.remove,
                  onPressed: () => adjustTime(-5 * 60),
                ),
                const SizedBox(width: 24),
                
                // Play/Pause Big Button
                FloatingActionButton.large(
                  onPressed: running ? stopTimer : startTimer,
                  backgroundColor: running 
                      ? Colors.orangeAccent 
                      : colorScheme.primary,
                  foregroundColor: Colors.white,
                  child: Icon(
                    running ? Icons.pause : Icons.play_arrow, 
                    size: 40,
                  ),
                ),
                
                const SizedBox(width: 24),
                _buildControlButton(
                  icon: Icons.add,
                  onPressed: () => adjustTime(5 * 60),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: resetTimer,
              icon: const Icon(Icons.refresh, color: Colors.grey),
              label: const Text('RESET', style: TextStyle(color: Colors.grey)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ]
      ),
      child: IconButton(
        icon: Icon(icon),
        iconSize: 28,
        onPressed: onPressed,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}