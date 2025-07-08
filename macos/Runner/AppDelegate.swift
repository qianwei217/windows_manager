import Cocoa
import FlutterMacOS

@NSApplicationMain
class AppDelegate: FlutterAppDelegate {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private let eventHandler = NativeEventHandler.shared // Use the singleton

    override func applicationDidFinishLaunching(_ notification: Notification) {
        // Access the Flutter view controller
        // The default Flutter template provides a mainFlutterWindow.
        // If you have a different setup, you might need to adjust how you get the controller.
        guard let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController else {
            fatalError("Failed to get FlutterViewController")
        }

        let messenger = flutterViewController.engine.binaryMessenger

        // Setup MethodChannel
        methodChannel = FlutterMethodChannel(name: "com.example.app/control",
                                             binaryMessenger: messenger)
        methodChannel?.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { return }

            switch call.method {
            case "startRecording":
                print("macOS AppDelegate: startRecording called")
                self.eventHandler.startRecording()
                result(true) // Assuming success, handler will send error via event channel if permissions fail
            case "stopRecording":
                print("macOS AppDelegate: stopRecording called")
                self.eventHandler.stopRecording()
                result(true)
            case "playEvents":
                print("macOS AppDelegate: playEvents called")
                if let events = call.arguments as? [[String: Any]] {
                    self.eventHandler.playEvents(events: events)
                    result(true)
                } else {
                    result(FlutterError(code: "INVALID_ARGUMENT",
                                        message: "Expected a list of event maps.",
                                        details: nil))
                }
            case "checkAccessibility": // Optional: a way for Flutter to explicitly check
                let granted = self.eventHandler.checkAccessibilityPermissions(prompt: false)
                result(granted)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        // Setup EventChannel
        eventChannel = FlutterEventChannel(name: "com.example.app/native_events",
                                           binaryMessenger: messenger)
        // Set the NativeEventHandler singleton as the stream handler.
        // The NativeEventHandler itself implements FlutterStreamHandler.
        eventChannel?.setStreamHandler(eventHandler)

        // It's good practice to check/request accessibility when the app starts if features depend on it.
        // However, startRecording also handles this.
        // let _ = eventHandler.checkAccessibilityPermissions(prompt: true) // Optionally prompt on launch

        super.applicationDidFinishLaunching(notification) // Call super if you override this method from a base class that implements it
    }

    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // Make sure to stop recording if the app is terminating
    override func applicationWillTerminate(_ notification: Notification) {
        print("macOS AppDelegate: applicationWillTerminate, stopping recording if active.")
        eventHandler.stopRecording()
        // Perform any other necessary cleanup
    }
}
