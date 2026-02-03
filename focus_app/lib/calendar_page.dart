import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class CalendarPage extends StatefulWidget {
  final AuthService authService;

  const CalendarPage({super.key, required this.authService});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  List<dynamic> _events = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final token = await widget.authService.getGoogleAccessToken();
    if (token == null) {
      setState(() {
        _error = 'Google Calendar not connected. Please sign in with Google.';
        _isLoading = false;
      });
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final url = 'https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=$now&maxResults=20&singleEvents=true&orderBy=startTime';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _events = data['items'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load events: ${response.statusCode} - ${response.body}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading events: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _addEvent() async {
    final titleController = TextEditingController();
    DateTime start = DateTime.now();
    DateTime end = start.add(const Duration(hours: 1));
    TimeOfDay startTime = TimeOfDay.fromDateTime(start);
    TimeOfDay endTime = TimeOfDay.fromDateTime(end);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF2C2C2C),
          title: const Text('Add Event', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Event Title',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Start: ${startTime.format(context)}', style: const TextStyle(color: Colors.white)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: startTime);
                      if (t != null) setStateDialog(() => startTime = t);
                    },
                    child: const Text('Change'),
                  ),
                ],
              ),
              Row(
                children: [
                  Text('End: ${endTime.format(context)}', style: const TextStyle(color: Colors.white)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(context: context, initialTime: endTime);
                      if (t != null) setStateDialog(() => endTime = t);
                    },
                    child: const Text('Change'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _postEvent(titleController.text, startTime, endTime);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _postEvent(String title, TimeOfDay start, TimeOfDay end) async {
    if (title.isEmpty) return;

    final token = await widget.authService.getGoogleAccessToken();
    if (token == null) return;

    final now = DateTime.now();
    final startDt = DateTime(now.year, now.month, now.day, start.hour, start.minute);
    var endDt = DateTime(now.year, now.month, now.day, end.hour, end.minute);
    if (endDt.isBefore(startDt)) {
      endDt = endDt.add(const Duration(days: 1));
    }

    final event = {
      'summary': title,
      'start': {'dateTime': startDt.toUtc().toIso8601String()},
      'end': {'dateTime': endDt.toUtc().toIso8601String()},
    };

    try {
      final response = await http.post(
        Uri.parse('https://www.googleapis.com/calendar/v3/calendars/primary/events'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(event),
      );

      if (response.statusCode == 200) {
        _fetchEvents(); // Refresh
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event added!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add event: ${response.statusCode}')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Your Schedule'),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchEvents,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      if (_error!.contains('not connected'))
                        ElevatedButton(
                          onPressed: () {
                             // This is a bit tricky as navigation is handled by parent,
                             // but we can tell user to re-login or handle it via a callback if needed.
                          }, 
                          child: const Text('Re-login with Google'),
                        )
                    ],
                  ),
                )
              : _events.isEmpty
                  ? const Center(child: Text('No upcoming events found.', style: TextStyle(color: Colors.white70)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _events.length,
                      itemBuilder: (context, index) {
                        final event = _events[index];
                        final summary = event['summary'] ?? '(No Title)';
                        final start = event['start']['dateTime'] ?? event['start']['date'];
                        final dt = DateTime.parse(start).toLocal();
                        final timeStr = "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
                        
                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${dt.day}\n${_getMonth(dt.month)}",
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(summary, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            subtitle: Text("$timeStr", style: const TextStyle(color: Colors.grey)),
                          ),
                        );
                      },
                    ),
    );
  }

  String _getMonth(int m) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    return months[m - 1];
  }
}
