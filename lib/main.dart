import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones(); // Initialize time zones
  await NotificationHelper.initialize(); // Initialize notifications

  final prefs = await SharedPreferences.getInstance();
  final isDarkMode = prefs.getBool('isDarkMode') ?? false;
  final String? tasksString = prefs.getString('tasks');
  final List<Task> savedTasks = [];
  if (tasksString != null) {
    final List<dynamic> decodedTasks = jsonDecode(tasksString);
    for (var taskMap in decodedTasks) {
      savedTasks.add(Task.fromJson(taskMap));
    }
  }
  runApp(MyApp(isDarkMode: isDarkMode, savedTasks: savedTasks));
}

class Task {
  String title;
  String description;
  DateTime? deadline;

  Task({
    required this.title,
    this.description = '',
    this.deadline,
  });

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'deadline': deadline?.toIso8601String(),
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      title: json['title'],
      description: json['description'] ?? '',
      deadline: json['deadline'] != null ? DateTime.parse(json['deadline']) : null,
    );
  }
}

class MyApp extends StatelessWidget {
  final bool isDarkMode;
  final List<Task> savedTasks;

  const MyApp({Key? key, required this.isDarkMode, this.savedTasks = const []}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider(isDarkMode)),
        ChangeNotifierProvider(create: (_) => TaskProvider(savedTasks)),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'To-Do App',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: Brightness.light,
              textTheme: GoogleFonts.poppinsTextTheme(),
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              textTheme: GoogleFonts.poppinsTextTheme().apply(
                bodyColor: Colors.white,
                displayColor: Colors.white,
              ),
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.deepPurple, brightness: Brightness.dark),
              scaffoldBackgroundColor: const Color(0xFF121212), // Dark background color
              cardColor: const Color(0xFF1E1E1E), // Dark card color
            ),
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const HomePage(),
          );
        },
      ),
    );
  }
}

class TaskProvider extends ChangeNotifier {
  List<Task> _tasks = [];
  TaskProvider(List<Task> initialTasks) {
    _tasks = initialTasks;
    _scheduleAllNotifications();
  }

  List<Task> get tasks => _tasks;

  void addTask(Task task) {
    _tasks.add(task);
    NotificationHelper.scheduleNotification(task); // Schedule notification
    _saveTasks();
    notifyListeners();
  }

  void deleteTask(Task task) {
    NotificationHelper.cancelNotification(task); // Cancel notification
    _tasks.remove(task);
    _saveTasks();
    notifyListeners();
  }

  void updateTask(int index, Task task) {
    final oldTask = _tasks[index];
    NotificationHelper.cancelNotification(oldTask); // Cancel old notification
    _tasks[index] = task;
    NotificationHelper.scheduleNotification(task); // Schedule new notification
    _saveTasks();
    notifyListeners();
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> taskMaps = _tasks.map((task) => task.toJson()).toList();
    await prefs.setString('tasks', jsonEncode(taskMaps));
  }

  void _scheduleAllNotifications() {
    for (final task in _tasks) {
      NotificationHelper.scheduleNotification(task);
    }
  }
}


class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher'); // Replace with your app icon

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(initializationSettings);
  }

  static Future<void> scheduleNotification(Task task) async {
    if (task.deadline == null) return;

    final DateTime deadline = task.deadline!;
    final int notificationId = task.hashCode; // Unique ID for each task

    await _notificationsPlugin.zonedSchedule(
      notificationId,
      'Deadline Passed',
      'The deadline for "${task.title}" has passed.',
      tz.TZDateTime.from(deadline.add(const Duration(minutes: 1)), tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'deadline_channel', // Channel ID
          'Deadline Notifications', // Channel name
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelNotification(Task task) async {
    final int notificationId = task.hashCode;
    await _notificationsPlugin.cancel(notificationId);
  }
}
class ThemeProvider extends ChangeNotifier {
  bool isDarkMode;

  ThemeProvider(this.isDarkMode);

  void toggleTheme() async {
    isDarkMode = !isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isDarkMode', isDarkMode);
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final taskProvider = Provider.of<TaskProvider>(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("To-Do App"),
        centerTitle: true,
        backgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,
        iconTheme: IconThemeData(
          color: isDarkMode ? Colors.white : Colors.black,
        ),
        titleTextStyle: TextStyle(
          color: isDarkMode ? Colors.white : Colors.black,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return RotationTransition(
                turns: Tween<double>(begin: 0.75, end: 1).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeOut),
                ),
                child: ScaleTransition(
                  scale: animation,
                  child: child,
                ),
              );
            },
            child: IconButton(
              key: ValueKey<bool>(themeProvider.isDarkMode),
              icon: Icon(
                themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: Theme.of(context).iconTheme.color,
              ),
              onPressed: () {
                themeProvider.toggleTheme();
              },
            ),
          ),
        ],
      ),
      body: taskProvider.tasks.isEmpty
          ? Center(
        child: Text(
          'No tasks added yet.\nTap + to add a task!',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 18,
              color: isDarkMode ? Colors.white70 : Colors.black87),
        ),
      )
          : ListView.builder(
        itemCount: taskProvider.tasks.length,
        padding: const EdgeInsets.only(bottom: 80),
        itemBuilder: (context, index) {
          final task = taskProvider.tasks[index];
          return Dismissible(
            key: ValueKey(task), // Use the task object as the key
            background: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            direction: DismissDirection.endToStart,
            confirmDismiss: (direction) async {
              return await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    backgroundColor:
                    isDarkMode ? const Color(0xFF303030) : Colors.white,
                    title: const Text('Confirm Delete'),
                    content: Text('Are you sure you want to delete "${task.title}"?'),
                    actions: [
                      TextButton(
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        child: const Text('Delete', style: TextStyle(color: Colors.red)),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  );
                },
              );
            },
            onDismissed: (_) {
              taskProvider.deleteTask(task); // Pass the task object
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Task "${task.title}" deleted successfully.'),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              );
            },
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).cardColor,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TaskDetailPage(
                        task: task,
                        taskIndex: index,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: ListTile(
                    title: Text(
                      task.title,
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: task.deadline != null
                        ? Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 16,
                            color: _isDeadlinePassed(task.deadline!)
                                ? Colors.red
                                : (isDarkMode ? Colors.white60 : Colors.black54),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _formatDeadline(task.deadline!),
                            style: TextStyle(
                              color: _isDeadlinePassed(task.deadline!)
                                  ? Colors.red
                                  : (isDarkMode ? Colors.white60 : Colors.black54),
                            ),
                          ),
                        ],
                      ),
                    )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle_outline),
                          color: Colors.green,
                          onPressed: () {
                            // Remove the task
                            taskProvider.deleteTask(task);

                            // Show a SnackBar with a motivational message
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Congrats on completing "${task.title}"! 🎉\n"${_getMotivationalQuote()}"',
                                  style: TextStyle(
                                    color: isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                          onPressed: () async {
                            final delete = await showDialog<bool>(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  backgroundColor:
                                  isDarkMode ? const Color(0xFF303030) : Colors.white,
                                  title: const Text('Confirm Delete'),
                                  content: Text('Are you sure you want to delete "${task.title}"?'),
                                  actions: [
                                    TextButton(
                                      child: Text(
                                        'Cancel',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white70 : Colors.black54,
                                        ),
                                      ),
                                      onPressed: () => Navigator.of(context).pop(false),
                                    ),
                                    TextButton(
                                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                      onPressed: () => Navigator.of(context).pop(true),
                                    ),
                                  ],
                                );
                              },
                            );
                            if (delete == true) {
                              taskProvider.deleteTask(task); // Pass the task object
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF5E35B1),
        onPressed: () => _showAddTaskDialog(context),
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: 'Add Task',
      ),
    );
  }

  bool _isDeadlinePassed(DateTime deadline) {
    return deadline.isBefore(DateTime.now());
  }

  String _formatDeadline(DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final deadlineDate = DateTime(deadline.year, deadline.month, deadline.day);
    String dateStr;
    if (deadlineDate == today) {
      dateStr = 'Today';
    } else if (deadlineDate == tomorrow) {
      dateStr = 'Tomorrow';
    } else {
      dateStr = DateFormat('MMM d').format(deadline);
    }
    return '$dateStr, ${DateFormat('h:mm a').format(deadline)}';
  }

  String _getMotivationalQuote() {
    final List<String> quotes = [
      "You're capable of amazing things!",
      "Success is the sum of small efforts.",
      "Keep going, you're doing great!",
      "Every accomplishment starts with the decision to try.",
      "Believe in yourself and all that you are.",
      "Hard work pays off, keep pushing!",
    ];
    return quotes[DateTime.now().millisecondsSinceEpoch % quotes.length];
  }

  void _showAddTaskDialog(BuildContext context) {
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController titleController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    DateTime? selectedDate;
    TimeOfDay? selectedTime;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDarkMode ? const Color(0xFF303030) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add New Task',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                // Title field
                Text(
                  'Title',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: titleController,
                  style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Enter task title',
                    hintStyle: TextStyle(
                        color: isDarkMode ? const Color(0xFFBDB6C8) : Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: const Color(0xFFB39DDB).withOpacity(isDarkMode ? 0.5 : 1),
                          width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: const Color(0xFF9575CD).withOpacity(isDarkMode ? 0.7 : 1),
                          width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDarkMode ? const Color(0xFF424242) : Colors.grey[50],
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                // Description field
                Text(
                  'Description',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descriptionController,
                  style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    hintText: 'Enter task description',
                    hintStyle: TextStyle(
                        color: isDarkMode ? const Color(0xFFBDB6C8) : Colors.grey),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: const Color(0xFFB39DDB).withOpacity(isDarkMode ? 0.5 : 1),
                          width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                          color: const Color(0xFF9575CD).withOpacity(isDarkMode ? 0.7 : 1),
                          width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDarkMode ? const Color(0xFF424242) : Colors.grey[50],
                    contentPadding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                // Deadline section
                Text(
                  'Deadline (Optional)',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white60 : Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                // Date & Time pickers
                Row(
                  children: [
                    Expanded(
                      child: StatefulBuilder(
                        builder: (context, setState) => OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(
                            selectedDate == null
                                ? 'Set Date'
                                : DateFormat('MMM d, y').format(selectedDate!),
                            style: TextStyle(
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: const Color(0xFFB39DDB).withOpacity(isDarkMode ? 0.5 : 1),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            final DateTime? pickedDate = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: ColorScheme.light(
                                      primary: const Color(0xFF5E35B1),
                                      onPrimary: Colors.white,
                                      surface: isDarkMode ? const Color(0xFF303030) : Colors.white,
                                      onSurface: isDarkMode ? Colors.white : Colors.black,
                                    ),
                                    dialogBackgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (pickedDate != null) {
                              setState(() {
                                selectedDate = pickedDate;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatefulBuilder(
                        builder: (context, setState) => OutlinedButton.icon(
                          icon: const Icon(Icons.access_time, size: 16),
                          label: Text(
                            selectedTime == null
                                ? 'Set Time'
                                : selectedTime!.format(context),
                            style: TextStyle(
                              color: isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: const Color(0xFFB39DDB).withOpacity(isDarkMode ? 0.5 : 1),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () async {
                            final TimeOfDay? pickedTime = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.now(),
                              builder: (context, child) {
                                return Theme(
                                  data: Theme.of(context).copyWith(
                                    colorScheme: ColorScheme.light(
                                      primary: const Color(0xFF5E35B1),
                                      onPrimary: Colors.white,
                                      surface: isDarkMode ? const Color(0xFF303030) : Colors.white,
                                      onSurface: isDarkMode ? Colors.white : Colors.black,
                                    ),
                                    dialogBackgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,
                                  ),
                                  child: child!,
                                );
                              },
                            );
                            if (pickedTime != null) {
                              setState(() {
                                selectedTime = pickedTime;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: isDarkMode ? const Color(0xFFB39DDB) : Colors.black54,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDarkMode
                            ? const Color(0xFF5E35B1)
                            : const Color(0xFF232025),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                        side: BorderSide(
                            color: isDarkMode
                                ? const Color(0xFF3E3750)
                                : Colors.grey[400]!,
                            width: 2),
                      ),
                      onPressed: () {
                        final title = titleController.text.trim();
                        if (title.isNotEmpty) {
                          DateTime? deadline;
                          if (selectedDate != null && selectedTime != null) {
                            deadline = DateTime(
                              selectedDate!.year,
                              selectedDate!.month,
                              selectedDate!.day,
                              selectedTime!.hour,
                              selectedTime!.minute,
                            );
                          }
                          taskProvider.addTask(Task(
                            title: title,
                            description: descriptionController.text.trim(),
                            deadline: deadline,
                          ));
                          Navigator.of(context).pop();
                        }
                      },
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TaskDetailPage extends StatefulWidget {
  final Task task;
  final int taskIndex;

  const TaskDetailPage({
    Key? key,
    required this.task,
    required this.taskIndex,
  }) : super(key: key);

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late DateTime? _selectedDate;
  late TimeOfDay? _selectedTime;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController = TextEditingController(text: widget.task.description);

    if (widget.task.deadline != null) {
      _selectedDate = widget.task.deadline;
      _selectedTime = TimeOfDay.fromDateTime(widget.task.deadline!);
    } else {
      _selectedDate = null;
      _selectedTime = null;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final taskProvider = Provider.of<TaskProvider>(context, listen: false);

    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(_isEditing ? "Edit Task" : "Task Details"),
          centerTitle: true,
          backgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,
          iconTheme: IconThemeData(
            color: isDarkMode ? Colors.white : Colors.black,
          ),
          titleTextStyle: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          actions: [
            IconButton(
              icon: Icon(_isEditing ? Icons.save : Icons.edit),
              onPressed: () {
                if (_isEditing) {
                  // Save changes
                  final updatedTask = Task(
                    title: _titleController.text.trim(),
                    description: _descriptionController.text.trim(),
                    deadline: _combineDateAndTime(),
                  );

                  taskProvider.updateTask(widget.taskIndex, updatedTask);
                  setState(() {
                    _isEditing = false;
                  });

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Task updated'),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  );
                } else {
                  // Enable editing
                  setState(() {
                    _isEditing = true;
                  });
                }
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // Title
    Text(
    'Title',
    style: TextStyle(
    color: isDarkMode ? Colors.white60 : Colors.black54,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    ),
    ),
    const SizedBox(height: 8),
    _isEditing
    ? TextField(
    controller: _titleController,
    style: TextStyle(
    color: isDarkMode ? Colors.white : Colors.black),
    decoration: InputDecoration(
    hintText: 'Enter task title',
    hintStyle: TextStyle(
    color: isDarkMode
    ? const Color(0xFFBDB6C8)
        : Colors.grey),
    enabledBorder: OutlineInputBorder(
    borderSide: BorderSide(
    color: const Color(0xFFB39DDB).withOpacity(
    isDarkMode ? 0.5 : 1),
    width: 1.5),
    borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
    borderSide: BorderSide(
    color: const Color(0xFF9575CD).withOpacity(
    isDarkMode ? 0.7 : 1),
    width: 2),
    borderRadius: BorderRadius.circular(12),
    ),
    filled: true,
    fillColor: isDarkMode
    ? const Color(0xFF424242)
        : Colors.grey[50],
    contentPadding:
    const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    ),
    )
        : Card(
    color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
    elevation: 1,
    shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
    padding: const EdgeInsets.all(16.0),
    child: Text(
    widget.task.title,
    style: TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: isDarkMode ? Colors.white : Colors.black87,
    ),
    ),
    ),
    ),

    const SizedBox(height: 24),

    // Description
    Text(
    'Description',
    style: TextStyle(
    color: isDarkMode ? Colors.white60 : Colors.black54,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    ),
    ),
    const SizedBox(height: 8),
    _isEditing
    ? TextField(
    controller: _descriptionController,
    style: TextStyle(
    color: isDarkMode ? Colors.white : Colors.black),
    decoration: InputDecoration(
    hintText: 'Enter task description',
    hintStyle: TextStyle(
    color: isDarkMode
    ? const Color(0xFFBDB6C8)
        : Colors.grey),
    enabledBorder: OutlineInputBorder(
    borderSide: BorderSide(
        color: const Color(0xFFB39DDB).withOpacity(
            isDarkMode ? 0.5 : 1),
        width: 1.5),
      borderRadius: BorderRadius.circular(12),
    ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(
            color: const Color(0xFF9575CD).withOpacity(
                isDarkMode ? 0.7 : 1),
            width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
      fillColor: isDarkMode
          ? const Color(0xFF424242)
          : Colors.grey[50],
      contentPadding:
      const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    ),
      maxLines: 3,
    )
        : Card(
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          widget.task.description.isNotEmpty
              ? widget.task.description
              : 'No description',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
      ),
    ),
      const SizedBox(height: 24),
      // Deadline
      Text(
        'Deadline',
        style: TextStyle(
          color: isDarkMode ? Colors.white60 : Colors.black54,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      const SizedBox(height: 8),
      _isEditing
          ? Row(
        children: [
          Expanded(
            child: StatefulBuilder(
              builder: (context, setState) => OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(
                  _selectedDate == null
                      ? 'Set Date'
                      : DateFormat('MMM d, y').format(_selectedDate!),
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: const Color(0xFFB39DDB).withOpacity(
                        isDarkMode ? 0.5 : 1),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  final DateTime? pickedDate = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.light(
                            primary: const Color(0xFF5E35B1),
                            onPrimary: Colors.white,
                            surface: isDarkMode ? const Color(0xFF303030) : Colors.white,
                            onSurface: isDarkMode ? Colors.white : Colors.black,
                          ),
                          dialogBackgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (pickedDate != null) {
                    setState(() {
                      _selectedDate = pickedDate;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: StatefulBuilder(
              builder: (context, setState) => OutlinedButton.icon(
                icon: const Icon(Icons.access_time, size: 16),
                label: Text(
                  _selectedTime == null
                      ? 'Set Time'
                      : _selectedTime!.format(context),
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: const Color(0xFFB39DDB).withOpacity(
                        isDarkMode ? 0.5 : 1),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  final TimeOfDay? pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.light(
                            primary: const Color(0xFF5E35B1),
                            onPrimary: Colors.white,
                            surface: isDarkMode ? const Color(0xFF303030) : Colors.white,
                            onSurface: isDarkMode ? Colors.white : Colors.black,
                          ),
                          dialogBackgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (pickedTime != null) {
                    setState(() {
                      _selectedTime = pickedTime;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      )
          : Card(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            widget.task.deadline != null
                ? DateFormat('MMM d, y - h:mm a').format(widget.task.deadline!)
                : 'No deadline set',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    ],
    ),
        ),
    );
  }

  DateTime? _combineDateAndTime() {
    if (_selectedDate == null || _selectedTime == null) {
      return null;
    }
    return DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
  }
}


