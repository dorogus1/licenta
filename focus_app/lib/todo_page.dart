import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

enum Recurrence { none, daily, weekly }

class TodoTask {
  final String id;
  final String title;
  final DateTime startTime;
  final DateTime endTime;
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
  final ScrollController _timelineScrollController = ScrollController();
  Timer? _nowTimer;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    // Scroll to current hour
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_timelineScrollController.hasClients) {
        double scrollOffset = DateTime.now().hour * 80.0;
        _timelineScrollController.animateTo(scrollOffset, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      }
    });

    // Refresh for current time line every minute
    _nowTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    _timelineScrollController.dispose();
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

  void _showAddTaskDialog() {
    final titleController = TextEditingController();
    TimeOfDay startTime = TimeOfDay.now();
    TimeOfDay endTime = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
    Recurrence recurrence = Recurrence.none;

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
              const Text('Sarcina Nouă', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              TextField(
                controller: titleController,
                autofocus: true,
                style: const TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  hintText: 'Ce vrei să faci?',
                  hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.edit_note, size: 28),
                ),
              ),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: startTime);
                        if (picked != null) setSheetState(() => startTime = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.4), borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            const Text('START', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(startTime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(context: context, initialTime: endTime);
                        if (picked != null) setSheetState(() => endTime = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.4), borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            const Text('FINAL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(endTime.format(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text('Recurență', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: Recurrence.values.map((r) {
                    bool selected = recurrence == r;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(r.name.toUpperCase()),
                        selected: selected,
                        onSelected: (val) => setSheetState(() => recurrence = r),
                      ),
                    );
                  }).toList(),
                ),
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
                  onPressed: () {
                    if (titleController.text.isEmpty) return;
                    final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, startTime.hour, startTime.minute);
                    final end = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, endTime.hour, endTime.minute);
                    final newTask = TodoTask(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: titleController.text,
                      startTime: start,
                      endTime: end,
                      recurrence: recurrence,
                    );
                    setState(() => _tasks.add(newTask));
                    _saveTasks();
                    Navigator.pop(context);
                  },
                  child: const Text('Salvează Sarcina', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final bool isToday = _selectedDate.year == now.year && 
                        _selectedDate.month == now.month && 
                        _selectedDate.day == now.day;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Focus Timeline', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(DateFormat('EEEE, d MMMM').format(_selectedDate), style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView.builder(
            controller: _timelineScrollController,
            padding: const EdgeInsets.only(bottom: 100),
            itemCount: 25, 
            itemBuilder: (context, hour) {
              return Container(
                height: 80,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${(hour % 24).toString().padLeft(2, '0')}:00', 
                        style: TextStyle(
                          color: hour == 24 ? Theme.of(context).colorScheme.primary : Colors.grey, 
                          fontSize: 12,
                          fontWeight: hour == 24 ? FontWeight.bold : FontWeight.normal,
                        )
                      ),
                    ),
                    Expanded(
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          ..._tasks.where((t) {
            if (t.recurrence == Recurrence.daily) return true;
            if (t.recurrence == Recurrence.weekly && t.startTime.weekday == _selectedDate.weekday) return true;
            return t.startTime.year == _selectedDate.year && t.startTime.month == _selectedDate.month && t.startTime.day == _selectedDate.day;
          }).map((task) {
            double top = (task.startTime.hour * 80.0) + (task.startTime.minute * 80.0 / 60.0);
            double height = ((task.endTime.hour - task.startTime.hour) * 80.0) + ((task.endTime.minute - task.startTime.minute) * 80.0 / 60.0);
            if (height < 40) height = 40;

            return Positioned(
              top: top,
              left: 70,
              right: 16,
              child: GestureDetector(
                onLongPress: () {
                  setState(() => _tasks.remove(task));
                  _saveTasks();
                },
                child: Container(
                  height: height,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).colorScheme.primary),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      if (height > 50)
                        Text('${DateFormat.Hm().format(task.startTime)} - ${DateFormat.Hm().format(task.endTime)}', style: const TextStyle(fontSize: 11)),
                      if (task.recurrence != Recurrence.none)
                        Icon(Icons.repeat, size: 12, color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),

          if (isToday)
            Positioned(
              top: (now.hour * 80.0) + (now.minute * 80.0 / 60.0),
              left: 0,
              right: 0,
              child: Row(
                children: [
                  Container(
                    width: 60,
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      color: Colors.red.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
