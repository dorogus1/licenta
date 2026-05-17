import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

enum Recurrence { none, daily, weekly }

class TodoTask {
  final String id;
  String title;
  DateTime startTime;
  DateTime endTime;
  bool isCompleted;
  Recurrence recurrence;
  String? calendarEventId;

  TodoTask({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.isCompleted = false,
    this.recurrence = Recurrence.none,
    this.calendarEventId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'isCompleted': isCompleted,
    'recurrence': recurrence.index,
    'calendarEventId': calendarEventId,
  };

  factory TodoTask.fromJson(Map<String, dynamic> json) => TodoTask(
    id: json['id'],
    title: json['title'],
    startTime: DateTime.parse(json['startTime']),
    endTime: DateTime.parse(json['endTime']),
    isCompleted: json['isCompleted'] ?? false,
    recurrence: Recurrence.values[json['recurrence'] ?? 0],
    calendarEventId: json['calendarEventId'],
  );
}

class TodoPage extends StatefulWidget {
  final AuthService authService;
  const TodoPage({super.key, required this.authService});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  List<TodoTask> _tasks = [];
  DateTime _selectedDate = DateTime.now();
  final TextEditingController _quickAddController = TextEditingController();
  
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _headerHorizontalController = ScrollController();
  final ScrollController _gridHorizontalController = ScrollController();
  
  Timer? _nowTimer;
  bool _isSyncing = false;
  bool _isWeekView = false;
  bool _showTimeline = true;

  // Check if current platform is desktop
  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _checkAndPerformAutoSync();
    
    _gridHorizontalController.addListener(() {
      if (_headerHorizontalController.hasClients && 
          _headerHorizontalController.offset != _gridHorizontalController.offset) {
        _headerHorizontalController.jumpTo(_gridHorizontalController.offset);
      }
    });
    _headerHorizontalController.addListener(() {
      if (_gridHorizontalController.hasClients && 
          _gridHorizontalController.offset != _headerHorizontalController.offset) {
        _gridHorizontalController.jumpTo(_headerHorizontalController.offset);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_verticalScrollController.hasClients) {
        double scrollOffset = DateTime.now().hour * 80.0;
        _verticalScrollController.animateTo(scrollOffset, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      }
    });

    _nowTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _checkAndPerformAutoSync() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final String lastSyncMonth = prefs.getString('last_google_sync_month') ?? '';
    final String currentMonthStr = '${now.year}-${now.month}';

    if (lastSyncMonth != currentMonthStr) {
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      
      Future.delayed(const Duration(seconds: 2), () async {
        final token = await widget.authService.getGoogleAccessToken();
        if (token != null) {
          await _importFromGoogleCalendar(token, startOfMonth, endOfMonth);
          await prefs.setString('last_google_sync_month', currentMonthStr);
        }
      });
    }
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    _verticalScrollController.dispose();
    _headerHorizontalController.dispose();
    _gridHorizontalController.dispose();
    _quickAddController.dispose();
    super.dispose();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? tasksJson = prefs.getString('todo_tasks');
    if (tasksJson != null) {
      final List<dynamic> decoded = json.decode(tasksJson);
      setState(() {
        _tasks = decoded.map((item) => TodoTask.fromJson(item)).toList();
      });
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('todo_tasks', json.encode(_tasks.map((t) => t.toJson()).toList()));
  }

  // --- GOOGLE CALENDAR SYNC ---

  Future<void> _syncWithGoogleCalendar() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final token = await widget.authService.getGoogleAccessToken();
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vă rugăm să vă autentificați cu Google mai întâi.'))
        );
        return;
      }

      await _exportToGoogleCalendar(token);
      
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 7, hours: 23, minutes: 59));
      
      await _importFromGoogleCalendar(token, start, end);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sincronizare finalizată!'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Eroare la sincronizare: $e'))
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _importFromGoogleCalendar(String token, DateTime from, DateTime to) async {
    final timeMin = from.toUtc().toIso8601String();
    final timeMax = to.toUtc().toIso8601String();

    final url = 'https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=$timeMin&timeMax=$timeMax&singleEvents=true';

    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['items'] ?? [];

      setState(() {
        for (var item in items) {
          final String? eventId = item['id'];
          final String title = item['summary'] ?? '(Fără titlu)';
          final dynamic start = item['start']['dateTime'] ?? item['start']['date'];
          final dynamic end = item['end']['dateTime'] ?? item['end']['date'];
          
          if (start == null || end == null) continue;

          final DateTime startTime = DateTime.parse(start).toLocal();
          final DateTime endTime = DateTime.parse(end).toLocal();

          final int existingIdx = _tasks.indexWhere((t) => t.calendarEventId == eventId);
          
          if (existingIdx != -1) {
            _tasks[existingIdx].title = title;
            _tasks[existingIdx].startTime = startTime;
            _tasks[existingIdx].endTime = endTime;
          } else {
            final bool existsByContent = _tasks.any((t) => 
              t.title == title && 
              t.startTime.isAtSameMomentAs(startTime) && 
              t.endTime.isAtSameMomentAs(endTime)
            );

            if (!existsByContent) {
              _tasks.add(TodoTask(
                id: DateTime.now().millisecondsSinceEpoch.toString() + eventId!,
                title: title,
                startTime: startTime,
                endTime: endTime,
                calendarEventId: eventId,
              ));
            }
          }
        }
      });
      await _saveTasks();
    }
  }

  Future<void> _exportToGoogleCalendar(String token) async {
    for (var task in _tasks) {
      if (task.calendarEventId == null) {
        await _createGoogleCalendarEvent(task, token);
      }
    }
  }

  Future<void> _createGoogleCalendarEvent(TodoTask task, String token) async {
    final url = 'https://www.googleapis.com/calendar/v3/calendars/primary/events';
    
    final event = {
      'summary': task.title,
      'start': {'dateTime': task.startTime.toUtc().toIso8601String()},
      'end': {'dateTime': task.endTime.toUtc().toIso8601String()},
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(event),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      task.calendarEventId = data['id'];
    }
  }

  Future<void> _updateGoogleCalendarEvent(TodoTask task) async {
    if (task.calendarEventId == null) return;
    
    final token = await widget.authService.getGoogleAccessToken();
    if (token == null) return;

    final url = 'https://www.googleapis.com/calendar/v3/calendars/primary/events/${task.calendarEventId}';
    
    final event = {
      'summary': task.title,
      'start': {'dateTime': task.startTime.toUtc().toIso8601String()},
      'end': {'dateTime': task.endTime.toUtc().toIso8601String()},
    };

    await http.patch(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode(event),
    );
  }

  Future<void> _deleteGoogleCalendarEvent(String eventId) async {
    final token = await widget.authService.getGoogleAccessToken();
    if (token == null) return;

    final url = 'https://www.googleapis.com/calendar/v3/calendars/primary/events/$eventId';
    
    await http.delete(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  void _quickAddTask(String title) async {
    if (title.isEmpty) return;
    
    // Default to current time + 1 hour
    final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, DateTime.now().hour, DateTime.now().minute);
    final end = start.add(const Duration(hours: 1));
    
    final newTask = TodoTask(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      startTime: start,
      endTime: end,
    );
    
    setState(() {
      _tasks.add(newTask);
      _quickAddController.clear();
    });
    
    _saveTasks();
    
    final token = await widget.authService.getGoogleAccessToken();
    if (token != null) {
      await _createGoogleCalendarEvent(newTask, token);
    }
  }

  void _showTaskDialog({TodoTask? taskToEdit, DateTime? initialDate}) {
    final targetDate = initialDate ?? _selectedDate;
    final titleController = TextEditingController(text: taskToEdit?.title ?? '');
    
    TimeOfDay startTime = taskToEdit != null 
        ? TimeOfDay.fromDateTime(taskToEdit.startTime)
        : (initialDate != null ? const TimeOfDay(hour: 9, minute: 0) : TimeOfDay.now());
        
    TimeOfDay endTime = taskToEdit != null
        ? TimeOfDay.fromDateTime(taskToEdit.endTime)
        : TimeOfDay.fromDateTime((taskToEdit?.startTime ?? (initialDate != null ? DateTime(targetDate.year, targetDate.month, targetDate.day, 9, 0) : DateTime.now())).add(const Duration(hours: 1)));
    
    Recurrence recurrence = taskToEdit?.recurrence ?? Recurrence.none;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            top: 12, left: 24, right: 24
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(taskToEdit == null ? 'Nou Task' : 'Editare Task', 
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  if (taskToEdit != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () {
                        if (taskToEdit.calendarEventId != null) {
                          _deleteGoogleCalendarEvent(taskToEdit.calendarEventId!);
                        }
                        setState(() => _tasks.remove(taskToEdit));
                        _saveTasks();
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(DateFormat('EEEE, d MMMM').format(targetDate), style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              TextField(
                controller: titleController,
                autofocus: taskToEdit == null,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Ce vrei să realizezi?',
                  hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.task_alt),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('ÎNCEPUT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: startTime);
                            if (picked != null) setSheetState(() => startTime = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(startTime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('SFÂRȘIT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () async {
                            final picked = await showTimePicker(context: context, initialTime: endTime);
                            if (picked != null) setSheetState(() => endTime = picked);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(endTime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () async {
                    if (titleController.text.isEmpty) return;
                    
                    final start = DateTime(targetDate.year, targetDate.month, targetDate.day, startTime.hour, startTime.minute);
                    final end = DateTime(targetDate.year, targetDate.month, targetDate.day, endTime.hour, endTime.minute);
                    
                    if (taskToEdit == null) {
                      final newTask = TodoTask(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        title: titleController.text,
                        startTime: start,
                        endTime: end,
                        recurrence: recurrence,
                      );
                      setState(() => _tasks.add(newTask));
                      
                      final token = await widget.authService.getGoogleAccessToken();
                      if (token != null) {
                        await _createGoogleCalendarEvent(newTask, token);
                      }
                    } else {
                      setState(() {
                        taskToEdit.title = titleController.text;
                        taskToEdit.startTime = start;
                        taskToEdit.endTime = end;
                        taskToEdit.recurrence = recurrence;
                      });
                      await _updateGoogleCalendarEvent(taskToEdit);
                    }
                    
                    _saveTasks();
                    Navigator.pop(context);
                  },
                  child: Text(taskToEdit == null ? 'Adaugă în Calendar' : 'Actualizează', 
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime get _startOfWeek {
    int dayOffset = _selectedDate.weekday - 1; 
    return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).subtract(Duration(days: dayOffset));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final bool isActualWeekView = _isWeekView && _isDesktop;
    final double dayWidth = isActualWeekView ? 150.0 : MediaQuery.of(context).size.width - 60;
    final double totalWidth = isActualWeekView ? dayWidth * 7 : dayWidth;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Tracker', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_showTimeline ? Icons.list : Icons.view_timeline),
            tooltip: _showTimeline ? 'View List' : 'View Timeline',
            onPressed: () => setState(() => _showTimeline = !_showTimeline),
          ),
          if (_isDesktop)
            IconButton(
              icon: Icon(isActualWeekView ? Icons.view_day : Icons.view_week),
              onPressed: () => setState(() => _isWeekView = !_isWeekView),
            ),
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              onPressed: _syncWithGoogleCalendar,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Quick Add Field
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quickAddController,
                    decoration: InputDecoration(
                      hintText: 'Adaugă un task rapid...',
                      prefixIcon: const Icon(Icons.add),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                    ),
                    onSubmitted: _quickAddTask,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => _quickAddTask(_quickAddController.text),
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
          // Date Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)))),
                Expanded(
                  child: TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _selectedDate = picked);
                    },
                    child: Text(
                      DateFormat('EEEE, d MMMM').format(_selectedDate),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)))),
              ],
            ),
          ),
          const Divider(),
          // Content
          Expanded(
            child: _showTimeline ? _buildTimeline(dayWidth, totalWidth, isActualWeekView, now) : _buildListView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTaskDialog(),
        label: const Text('New Task'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildListView() {
    final dayTasks = _tasks.where((t) {
      if (t.recurrence == Recurrence.daily) return true;
      if (t.recurrence == Recurrence.weekly && t.startTime.weekday == _selectedDate.weekday) return true;
      return t.startTime.year == _selectedDate.year && t.startTime.month == _selectedDate.month && t.startTime.day == _selectedDate.day;
    }).toList();

    if (dayTasks.isEmpty) {
      return const Center(child: Text('Niciun task pentru azi.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: dayTasks.length,
      itemBuilder: (context, index) {
        final task = dayTasks[index];
        return Card(
          child: ListTile(
            leading: Checkbox(
              value: task.isCompleted,
              onChanged: (val) {
                setState(() => task.isCompleted = val ?? false);
                _saveTasks();
              },
            ),
            title: Text(task.title, style: TextStyle(decoration: task.isCompleted ? TextDecoration.lineThrough : null)),
            subtitle: Text('${DateFormat.Hm().format(task.startTime)} - ${DateFormat.Hm().format(task.endTime)}'),
            trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _showTaskDialog(taskToEdit: task)),
          ),
        );
      },
    );
  }

  Widget _buildTimeline(double dayWidth, double totalWidth, bool isActualWeekView, DateTime now) {
    return SingleChildScrollView(
      controller: _verticalScrollController,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            child: Column(
              children: List.generate(24, (hour) => Container(
                height: 80,
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 8),
                child: Text('${hour.toString().padLeft(2, '0')}:00', style: const TextStyle(color: Colors.grey, fontSize: 11)),
              )),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _gridHorizontalController,
              scrollDirection: Axis.horizontal,
              child: Container(
                width: totalWidth,
                height: 24 * 80.0,
                child: Stack(
                  children: [
                    Row(
                      children: List.generate(isActualWeekView ? 7 : 1, (dayIdx) => Container(
                        width: dayWidth,
                        child: Column(
                          children: List.generate(24, (h) => Container(
                            height: 80,
                            decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.withOpacity(0.1)), bottom: BorderSide(color: Colors.grey.withOpacity(0.1)))),
                          )),
                        ),
                      )),
                    ),
                    ...List.generate(isActualWeekView ? 7 : 1, (dayIdx) {
                      final date = isActualWeekView ? _startOfWeek.add(Duration(days: dayIdx)) : _selectedDate;
                      final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
                      final dayTasks = _tasks.where((t) {
                        if (t.recurrence == Recurrence.daily) return true;
                        if (t.recurrence == Recurrence.weekly && t.startTime.weekday == date.weekday) return true;
                        return t.startTime.year == date.year && t.startTime.month == date.month && t.startTime.day == date.day;
                      });

                      return Stack(
                        children: [
                          if (isToday)
                            Positioned(
                              top: (now.hour * 80.0) + (now.minute * 80.0 / 60.0),
                              left: dayIdx * dayWidth,
                              width: dayWidth,
                              child: Row(children: [Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)), Expanded(child: Container(height: 2, color: Colors.red.withOpacity(0.5)))]),
                            ),
                          ...dayTasks.map((task) {
                            double top = (task.startTime.hour * 80.0) + (task.startTime.minute * 80.0 / 60.0);
                            double height = ((task.endTime.hour - task.startTime.hour) * 80.0) + ((task.endTime.minute - task.startTime.minute) * 80.0 / 60.0);
                            if (height < 30) height = 30;

                            return Positioned(
                              top: top,
                              left: (dayIdx * dayWidth) + 4,
                              width: dayWidth - 8,
                              child: GestureDetector(
                                onTap: () => _showTaskDialog(taskToEdit: task, initialDate: date),
                                child: Container(
                                  height: height,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: task.isCompleted ? Colors.grey.withOpacity(0.3) : Theme.of(context).colorScheme.primaryContainer.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(task.title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, decoration: task.isCompleted ? TextDecoration.lineThrough : null), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      if (height > 40) Text(DateFormat.Hm().format(task.startTime), style: const TextStyle(fontSize: 10)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
