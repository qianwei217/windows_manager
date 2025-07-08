import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for MethodChannel and EventChannel
import 'dart:io' show Platform; // Required for Platform.isWindows
import 'dart:async'; // Required for StreamSubscription

void main() {
  // Ensure Flutter bindings are initialized for platform channel communication before runApp.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '按键精灵 Flutter',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

enum RecordingState {
  idle,
  recording,
  playing,
}

// Keep InputEvent simple for now, will store raw map from native
class RawInputEvent {
  final String type;
  final Map<dynamic, dynamic> details; // Raw details map from native
  final int nativeTimestamp; // e.g., GetTickCount64 result
  final DateTime recordedAt; // Dart side timestamp

  RawInputEvent({
    required this.type,
    required this.details,
    required this.nativeTimestamp,
    required this.recordedAt,
  });

  String get formattedDetails {
    List<String> parts = [];
    if (type == "keyDown" || type == "keyUp") {
      parts.add("Key: ${details['key']}");
      // Windows uses 'vk_code', macOS uses 'keyCode' for the virtual key code.
      // The native Swift code sends 'keyCode'. The native C++ code sends 'vk_code'.
      // Let's prefer 'keyCode' if present, else 'vk_code'.
      if (details.containsKey('keyCode')) {
        parts.add("Code: ${details['keyCode']}");
      } else if (details.containsKey('vk_code')) {
        parts.add("VK: ${details['vk_code']}");
      }
      if (details.containsKey('characters')) {
        parts.add("Chars: '${details['characters']}'");
      }
      parts.add("Ctrl: ${details['is_ctrl_pressed'] ?? false}");
      parts.add("Shift: ${details['is_shift_pressed'] ?? false}");
      parts.add("Alt: ${details['is_alt_pressed'] ?? false}");
      if (Platform.isMacOS) {
        parts.add("Cmd: ${details['is_cmd_pressed'] ?? false}");
      }
       if (details['isARepeat'] == true) {
        parts.add("(Repeat)");
      }
    } else if (type == "mouseMove" || type == "mouseDown" || type == "mouseUp") {
      // Prefer global coordinates for display if available
      final String xCoord = details.containsKey('x_global') ? details['x_global'].toString() : details['x'].toString();
      final String yCoord = details.containsKey('y_global') ? details['y_global'].toString() : details['y'].toString();
      parts.add("X: $xCoord, Y: $yCoord");

      if (type == "mouseDown" || type == "mouseUp") {
        parts.add("Button: ${details['button']}");
        if (details.containsKey('clickCount')) {
          parts.add("Clicks: ${details['clickCount']}");
        }
      }
      if (details.containsKey('dragged_button')){
        parts.add("Dragged: ${details['dragged_button']}");
      }
      if (details.containsKey('pressure')) {
        parts.add("Pressure: ${details['pressure']}");
      }
    } else if (type == "mouseWheel") {
      // Windows sends 'delta' (vertical). macOS sends 'deltaX', 'deltaY'.
      if (Platform.isMacOS) {
        parts.add("dX: ${details['deltaX']}, dY: ${details['deltaY']}");
        if (details.containsKey('phase')) {
           parts.add("Phase: ${details['phase']}"); // Trackpad phase
        }
      } else { // Windows
        parts.add("Scroll: ${details['delta']}");
      }
      // Mouse wheel events might also have x,y for where the cursor was when scroll happened
      final String xCoord = details.containsKey('x_global') ? details['x_global'].toString() : (details['x']?.toString() ?? "N/A");
      final String yCoord = details.containsKey('y_global') ? details['y_global'].toString() : (details['y']?.toString() ?? "N/A");
      if (xCoord != "N/A") parts.add("at X: $xCoord, Y: $yCoord");
    } else {
      return details.toString();
    }
    return parts.join(" | ");
  }

  // Method to convert to a format suitable for sending back to native for playback
  Map<String, dynamic> toJsonForPlayback() {
    return {
      'type': type,
      'details': details, // Send the original details map
      'timestamp': nativeTimestamp, // Send the original native timestamp
    };
  }

  @override
  String toString() {
    return "${recordedAt.toIso8601String()} - [$type] $formattedDetails (NativeTs: $nativeTimestamp)";
  }
}


class _MyHomePageState extends State<MyHomePage> {
  static const MethodChannel _controlChannel = MethodChannel('com.example.app/control');
  static const EventChannel _eventChannel = EventChannel('com.example.app/native_events');
  StreamSubscription? _eventSubscription;

  RecordingState _currentState = RecordingState.idle;
  final List<RawInputEvent> _recordedEvents = [];

  @override
  void initState() {
    super.initState();
    _listenToNativeEvents();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    // If recording is active on dispose (e.g. app quit unexpectedly), try to stop.
    if (_currentState == RecordingState.recording) {
       _stopRecordingNative();
    }
    super.dispose();
  }

  void _listenToNativeEvents() {
    if (!Platform.isWindows && !Platform.isMacOS) return; // Only listen on supported platforms

    _eventSubscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
      // The event from C++ is EncodableMap, which becomes Map<dynamic, dynamic> in Dart
      if (event is Map) {
        final String type = event['type'] as String? ?? 'unknown';
        final Map<dynamic, dynamic> details = event['details'] as Map<dynamic, dynamic>? ?? {};

        if (type == "status") {
          print("Native status: ${details['message'] ?? details['error']}");
          // Could show this in a snackbar or log
          if (mounted && details['error'] != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Native Error: ${details['error']}")),
            );
          }
          return;
        }

        // All other events are input events
        final int nativeTimestamp = details['timestamp'] as int? ?? 0;

        if (mounted && _currentState == RecordingState.recording) {
          setState(() {
            _recordedEvents.add(RawInputEvent(
              type: type,
              details: details,
              nativeTimestamp: nativeTimestamp,
              recordedAt: DateTime.now(), // Dart timestamp for display ordering
            ));
          });
        }
      }
    }, onError: (dynamic error) {
      print('Error receiving native event: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error from native listener: $error")),
        );
      }
    });
  }

  Future<void> _startRecording() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
       _showUnsupportedPlatformDialog();
       return;
    }
    if (_currentState == RecordingState.idle) {
      try {
        final bool? success = await _controlChannel.invokeMethod('startRecording');
        if (success == true) {
          setState(() {
            _currentState = RecordingState.recording;
            _recordedEvents.clear();
            // Add a visual cue that recording has started
            _recordedEvents.add(RawInputEvent(type: "Status", details: {"message": "Recording Started"}, nativeTimestamp: 0, recordedAt: DateTime.now()));
          });
          print("Dart: Start Recording successful");
        } else {
          print("Dart: Start Recording failed or returned null");
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("无法开始录制 (native error or platform not supported).")),
          );
        }
      } on PlatformException catch (e) {
        print("Dart: Error starting recording: ${e.message}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("开始录制失败: ${e.message}")),
        );
      }
    }
  }

  Future<void> _stopRecordingNative() async {
      if (!Platform.isWindows && !Platform.isMacOS) return;
      try {
        await _controlChannel.invokeMethod('stopRecording');
        print("Dart: Stop Recording successful");
      } on PlatformException catch (e) {
        print("Dart: Error stopping recording: ${e.message}");
      }
  }

  Future<void> _stopRecording() async {
    if (_currentState == RecordingState.recording) {
      await _stopRecordingNative();
      setState(() {
        _currentState = RecordingState.idle;
        _recordedEvents.add(RawInputEvent(type: "Status", details: {"message": "Recording Stopped"}, nativeTimestamp: 0, recordedAt: DateTime.now()));
      });
    }
  }

  Future<void> _playRecording() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
       _showUnsupportedPlatformDialog();
       return;
    }
    if (_currentState == RecordingState.idle && _recordedEvents.where((e) => e.type != "Status").isNotEmpty) {
      setState(() {
        _currentState = RecordingState.playing;
      });
      print("Dart: Play Recording - Events: ${_recordedEvents.length}");

      // Filter out status messages, prepare for native
      List<Map<String, dynamic>> eventsToPlay = _recordedEvents
          .where((event) => event.type != "Status") // Exclude our "Status" messages
          .map((event) => event.toJsonForPlayback())
          .toList();

      if (eventsToPlay.isEmpty) {
        print("Dart: No actual input events to play.");
        setState(() {
          _currentState = RecordingState.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("没有有效事件可播放。")),
        );
        return;
      }

      try {
        await _controlChannel.invokeMethod('playEvents', eventsToPlay);
        print("Dart: Playback finished command sent.");
      } on PlatformException catch (e) {
        print("Dart: Error playing events: ${e.message}");
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("播放失败: ${e.message}")),
        );
      } finally {
        // It's better if native side sends a "playbackFinished" event.
        // For now, just revert state after a delay or immediately.
        // Let's assume native side is synchronous for now for simplicity,
        // or it handles its own async nature and Flutter just waits.
        // For a better UX, native could send progress or a completion event.
        setState(() {
          _currentState = RecordingState.idle;
        });
      }
    } else if (_recordedEvents.where((e) => e.type != "Status").isEmpty) {
      print("No events to play.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("没有录制的事件可播放。")),
      );
    }
  }

  void _showUnsupportedPlatformDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Platform Not Supported"),
          content: const Text("This feature is currently only supported on Windows and macOS."),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  String get _statusText {
    switch (_currentState) {
      case RecordingState.idle:
        return Platform.isWindows || Platform.isMacOS ? "状态：未开始" : "状态：平台不支持";
      case RecordingState.recording:
        return "状态：录制中...";
      case RecordingState.playing:
        return "状态：播放中...";
    }
  }

  @override
  Widget build(BuildContext context) {
    bool canStart = _currentState == RecordingState.idle && (Platform.isWindows || Platform.isMacOS);
    bool canStop = _currentState == RecordingState.recording;
    bool canPlay = _currentState == RecordingState.idle && _recordedEvents.where((e) => e.type != "Status").isNotEmpty && (Platform.isWindows || Platform.isMacOS);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter 按键精灵 (Windows/Mac)'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _statusText,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              ElevatedButton(
                onPressed: canStart ? _startRecording : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('开始录制'),
              ),
              ElevatedButton(
                onPressed: canStop ? _stopRecording : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('停止录制'),
              ),
              ElevatedButton(
                onPressed: canPlay ? _playRecording : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('播放录制'),
              ),
            ],
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Text(
              "录制的事件 (${_recordedEvents.where((e) => e.type != "Status").length} actual events):", // Count actual events
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _recordedEvents.length,
              itemBuilder: (context, index) {
                final event = _recordedEvents[index];
                 // Highlight status messages differently
                bool isStatusMessage = event.type == "Status";
                return ListTile(
                  title: Text(event.type, style: TextStyle(fontWeight: isStatusMessage ? FontWeight.bold : FontWeight.normal, color: isStatusMessage ? Colors.blueGrey : null)),
                  subtitle: Text(isStatusMessage ? event.details["message"].toString() : event.formattedDetails),
                  trailing: Text(TimeOfDay.fromDateTime(event.recordedAt).format(context)),
                  dense: true,
                  tileColor: isStatusMessage ? Colors.grey[200] : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
