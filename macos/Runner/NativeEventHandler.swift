import FlutterMacOS
import Cocoa
import CoreGraphics

// Helper to convert CGKeyCode to String (simplified)
func keyStringFromKeyCode(keyCode: CGKeyCode) -> String {
    // This is a very simplified version. For a full mapping, you'd need a large table
    // or use TISCopyCurrentKeyboardInputSource and related APIs.
    switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        // case 10: // § (Section sign) / ± (Plus-minus sign) on ISO keyboards
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "=" // Equal sign
        case 25: return "9"
        case 26: return "7"
        case 27: return "-" // Minus sign
        case 28: return "8"
        case 29: return "0"
        case 30: return "]" // Close bracket
        case 31: return "O"
        case 32: return "U"
        case 33: return "[" // Open bracket
        case 34: return "I"
        case 35: return "P"
        case 36: return "RETURN" // Enter
        case 37: return "L"
        case 38: return "J"
        case 39: return "'" // Quote
        case 40: return "K"
        case 41: return ";" // Semicolon
        case 42: return "\\" // Backslash
        case 43: return "," // Comma
        case 44: return "/" // Slash
        case 45: return "N"
        case 46: return "M"
        case 47: return "." // Period
        case 48: return "TAB"
        case 49: return "SPACE"
        case 50: return "`" // Grave accent (backtick)
        case 51: return "DELETE" // Backspace
        // case 52: // Enter (numpad) - different from RETURN
        case 53: return "ESCAPE"
        // Modifiers are usually handled by flags, not separate key strings here
        case 54: return "RCOMMAND" // Right Command
        case 55: return "LCOMMAND" // Left Command
        case 56: return "LSHIFT"   // Left Shift
        case 57: return "CAPSLOCK"
        case 58: return "LOPTION"  // Left Option (Alt)
        case 59: return "LCONTROL" // Left Control
        case 60: return "RSHIFT"   // Right Shift
        case 61: return "ROPTION"  // Right Option (Alt)
        case 62: return "RCONTROL" // Right Control
        // Function Keys
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        // Arrow keys
        case 123: return "LEFT_ARROW"
        case 124: return "RIGHT_ARROW"
        case 125: return "DOWN_ARROW"
        case 126: return "UP_ARROW"
        default: return "VK(\(keyCode))"
    }
}


class NativeEventHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?
    private var keyboardMonitor: Any?
    private var mouseDownMonitor: Any?
    private var mouseUpMonitor: Any?
    private var mouseMoveMonitor: Any?
    private var mouseDraggedMonitor: Any? // Catches both left and right drags
    private var scrollWheelMonitor: Any?

    private var isRecording = false
    private var lastMouseEventTime: TimeInterval = 0
    private let mouseMoveThrottleInterval: TimeInterval = 0.016 // ~60 FPS

    public static let shared = NativeEventHandler()

    private override init() {
        super.init()
    }

    // MARK: - FlutterStreamHandler
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        // Send a status message if needed, or just be ready
        // events(["type": "status", "details": ["message": "Event channel established"]])
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    private func sendEventToFlutter(type: String, details: [String: Any]) {
        guard let sink = self.eventSink, isRecording else { return }
        var eventData = details
        eventData["timestamp"] = Int64(Date().timeIntervalSince1970 * 1000) // Native timestamp for consistency with Windows

        var flutterDetails: [String: Any] = [:]
        for (key, value) in eventData {
            flutterDetails[key] = value // Directly use, assuming Flutter EncodableValue compatibility
        }

        sink(["type": type, "details": flutterDetails])
    }

    // MARK: - Recording Control
    public func startRecording() {
        if isRecording { return }
        print("Native (macOS): StartRecording called")

        guard checkAccessibilityPermissions(prompt: true) else {
            print("Native (macOS): Accessibility permissions not granted.")
            if let sink = self.eventSink {
                 sink(["type": "status", "details": ["error": "Accessibility permissions required."]])
            }
            return
        }

        isRecording = true

        let maskDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: maskDown) { [weak self] (event: NSEvent) in
            self?.handleMouseEvent(event: event)
        }

        let maskUp: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: maskUp) { [weak self] (event: NSEvent) in
            self?.handleMouseEvent(event: event)
        }

        // NSEvent.mouseLocation includes changes even without movement if other things change (like screen params)
        // Using mouseMoved for actual physical mouse movements.
        // mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] (event: NSEvent) in
        //     self?.handleMouseEvent(event: event)
        // }

        // MouseDragged includes left, right, and other drags.
        // We need to combine this with mouseMoved for complete tracking if we only use global monitors.
        // However, for recording, it's often simpler to use a CGEventTap for mouse move/drag if precision is key,
        // as global monitors for mouseMoved can be lossy or not fire for all movements.
        // For now, let's try with global monitors.
        mouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] (event: NSEvent) in
             self?.handleMouseEvent(event: event)
        }


        scrollWheelMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] (event: NSEvent) in
            self?.handleMouseEvent(event: event)
        }

        keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] (event: NSEvent) in
            self?.handleKeyEvent(event: event)
        }

        print("Native (macOS): Hooks set successfully.")
        if let sink = self.eventSink {
            sink(["type": "status", "details": ["message": "Recording started successfully."]])
        }
    }

    public func stopRecording() {
        if !isRecording { return }
        isRecording = false
        print("Native (macOS): StopRecording called")

        if let monitor = keyboardMonitor { NSEvent.removeMonitor(monitor); keyboardMonitor = nil }
        if let monitor = mouseDownMonitor { NSEvent.removeMonitor(monitor); mouseDownMonitor = nil }
        if let monitor = mouseUpMonitor { NSEvent.removeMonitor(monitor); mouseUpMonitor = nil }
        if let monitor = mouseMoveMonitor { NSEvent.removeMonitor(monitor); mouseMoveMonitor = nil }
        // if let monitor = mouseDraggedMonitor { NSEvent.removeMonitor(monitor); mouseDraggedMonitor = nil }
        if let monitor = scrollWheelMonitor { NSEvent.removeMonitor(monitor); scrollWheelMonitor = nil }

        print("Native (macOS): Hooks removed.")
        if let sink = self.eventSink {
             sink(["type": "status", "details": ["message": "Recording stopped."]])
        }
    }

    // MARK: - Event Handlers
    private func handleKeyEvent(event: NSEvent) {
        guard isRecording else { return }
        var type = ""
        switch event.type {
            case .keyDown: type = "keyDown"
            case .keyUp: type = "keyUp"
            case .flagsChanged: // Modifier keys like Shift, Ctrl, Option, Cmd
                // This is complex because flagsChanged can mean a modifier was pressed OR released.
                // We need to compare with previous flags or interpret based on the keyCode.
                // For simplicity, we'll send it as a generic "flagsChanged" and let Dart decide,
                // or try to infer if it's a press/release based on keyCode.
                // Common modifier keyCodes: 56 (Shift), 59 (Ctrl), 58 (Option), 55 (Cmd)
                // However, event.keyCode for flagsChanged is often the modifier itself.
                // A more robust way is to check event.modifierFlags
                // For now, let's assume keyUp/keyDown for modifiers are distinct events if possible,
                // or we might get duplicates if we also process them here.
                // Let's try to map them to keyDown/keyUp based on current state of modifier flags.
                // This is tricky. For now, we'll just send the keyCode and let Flutter interpret.
                // A better approach might be to ignore flagsChanged here and rely on the individual keyUp/keyDown for modifiers.
                // Or, if we want to capture ONLY modifier changes, handle them specially.
                // For now, let's report it as a key event.
                // We need to determine if it's a press or release. This is not straightforward from flagsChanged alone.
                // Let's skip explicit flagsChanged processing for now and rely on keyDown/keyUp for individual keys including modifiers.
                // If a modifier is pressed *alone*, it generates a flagsChanged. If pressed with another key, it's part of that key's event.
                // For simplicity, we'll send a generic "keyEquivalent" for flagsChanged and let Dart figure it out, or refine this later.
                // For recording purposes, we mainly care about the characters produced or the virtual key codes.
                // Let's try to get key up/down for modifier keys if they are sent that way.
                // If a modifier is pressed and released by itself, it sends flagsChanged.
                // If it's pressed, then another key, then modifier released, then other key released:
                // 1. flagsChanged (modifier down)
                // 2. keyDown (other key, with modifier flag)
                // 3. flagsChanged (modifier up)
                // 4. keyUp (other key, without modifier flag)
                // This can get complex. For now, we will send keyDown/keyUp for the event.keyCode associated with flagsChanged.
                // We need to infer if it's up or down.
                // This is not reliable. Let's ignore pure .flagsChanged for now to avoid double reporting or misinterpretation.
                // We will get modifier status from event.modifierFlags in keyDown/keyUp events.
                return // Skip raw .flagsChanged for now, rely on flags in other events.
            default: return
        }

        var details: [String: Any] = [
            "keyCode": event.keyCode, // This is CGKeyCode
            "key": keyStringFromKeyCode(keyCode: event.keyCode), // Simplified string
            "characters": event.characters ?? "",
            "charactersIgnoringModifiers": event.charactersIgnoringModifiers ?? "",
            "isARepeat": event.isARepeat,
            "modifierFlags": event.modifierFlags.rawValue, // Send raw value
            "is_ctrl_pressed": event.modifierFlags.contains(.control),
            "is_shift_pressed": event.modifierFlags.contains(.shift),
            "is_alt_pressed": event.modifierFlags.contains(.option), // Option key is Alt
            "is_cmd_pressed": event.modifierFlags.contains(.command)
        ]
        sendEventToFlutter(type: type, details: details)
    }

    private func handleMouseEvent(event: NSEvent) {
        guard isRecording else { return }

        let currentTime = Date.timeIntervalSinceReferenceDate
        if event.type == .mouseMoved || event.type == .leftMouseDragged || event.type == .rightMouseDragged || event.type == .otherMouseDragged {
            if currentTime - lastMouseEventTime < mouseMoveThrottleInterval {
                return // Throttle mouse move/drag events
            }
            lastMouseEventTime = currentTime
        }

        var type = ""
        var details: [String: Any] = [
            "x": Int(event.locationInWindow.x), // This is window coordinates. For global, use NSEvent.mouseLocation
            "y": Int(NSEvent.mouseLocation.y), // Global Y (bottom-left origin)
                                              // macOS screen coordinates are usually top-left origin for windows,
                                              // but global NSEvent.mouseLocation is bottom-left.
                                              // For consistency with Windows (top-left), we might need to flip Y.
                                              // Let's get screen height for that.
            // "y_flipped": Int(NSScreen.main?.frame.height ?? 0) - Int(NSEvent.mouseLocation.y), // Global Y (top-left origin)
            "modifierFlags": event.modifierFlags.rawValue,
            "pressure": event.pressure,
        ]

        // For global coordinates (bottom-left origin, which CGEvent also uses)
        let globalMouseLocation = NSEvent.mouseLocation
        details["x_global"] = Int(globalMouseLocation.x)
        details["y_global"] = Int(globalMouseLocation.y)


        switch event.type {
            case .leftMouseDown: type = "mouseDown"; details["button"] = "left"; details["clickCount"] = event.clickCount
            case .leftMouseUp: type = "mouseUp"; details["button"] = "left"
            case .rightMouseDown: type = "mouseDown"; details["button"] = "right"; details["clickCount"] = event.clickCount
            case .rightMouseUp: type = "mouseUp"; details["button"] = "right"
            case .otherMouseDown: type = "mouseDown"; details["button"] = "middle"; details["clickCount"] = event.clickCount // Often middle
            case .otherMouseUp: type = "mouseUp"; details["button"] = "middle"
            case .mouseMoved: type = "mouseMove"
            case .leftMouseDragged: type = "mouseMove"; details["dragged_button"] = "left" // Or treat as separate "mouseDrag"
            case .rightMouseDragged: type = "mouseMove"; details["dragged_button"] = "right"
            case .otherMouseDragged: type = "mouseMove"; details["dragged_button"] = "other"
            case .scrollWheel:
                type = "mouseWheel"
                details["deltaX"] = event.scrollingDeltaX
                details["deltaY"] = event.scrollingDeltaY
                details["hasPreciseScrollingDeltas"] = event.hasPreciseScrollingDeltas
                // phase is important for trackpads: .began, .changed, .ended, .cancelled, .mayBegin
                details["phase"] = event.phase.rawValue
                details["momentumPhase"] = event.momentumPhase.rawValue
            default: return
        }
        sendEventToFlutter(type: type, details: details)
    }

    // MARK: - Event Playback
    public func playEvents(events: [[String: Any]]) {
        if isRecording {
            print("Native (macOS): Cannot play events while recording.")
            return
        }
        print("Native (macOS): PlayEvents called with \(events.count) events.")

        // Ensure accessibility permissions first
        guard checkAccessibilityPermissions(prompt: false) else { // Don't re-prompt if already denied
            print("Native (macOS): Accessibility permissions required for playback.")
            if let sink = self.eventSink {
                 sink(["type": "status", "details": ["error": "Accessibility permissions required for playback."]])
            }
            return
        }

        var lastEventNativeTimestamp: Int64 = 0
        var firstEvent = true

        for eventData in events {
            guard let type = eventData["type"] as? String,
                  let details = eventData["details"] as? [String: Any],
                  let nativeTimestamp = eventData["timestamp"] as? Int64 else { // This is the original native timestamp
                print("Native (macOS): Malformed event for playback: \(eventData)")
                continue
            }

            if !firstEvent && lastEventNativeTimestamp != 0 {
                let delayMilliseconds = nativeTimestamp - lastEventNativeTimestamp
                if delayMilliseconds > 0 {
                    usleep(useconds_t(delayMilliseconds * 1000)) // usleep takes microseconds
                }
            }
            lastEventNativeTimestamp = nativeTimestamp
            firstEvent = false

            // Simulate event using CoreGraphics
            simulateEvent(type: type, details: details)
        }
        print("Native (macOS): Finished playing events.")
         if let sink = self.eventSink {
             sink(["type": "status", "details": ["message": "Playback finished."]])
        }
    }

    private func simulateEvent(type: String, details: [String: Any]) {
        var cgEvent: CGEvent?

        // Global mouse location for posting events. CG uses bottom-left origin.
        // The recorded 'x_global', 'y_global' should be used.
        // If not available, we might need to fall back or error.
        let x = details["x_global"] as? Int ?? (details["x"] as? Int ?? 0) // Prioritize global if available
        let y = details["y_global"] as? Int ?? (details["y"] as? Int ?? 0)
        let point = CGPoint(x: x, y: y)

        // Modifier flags for keyboard events
        let cgEventFlags = CGEventFlags(rawValue: details["modifierFlags"] as? UInt64 ?? 0)


        switch type {
        case "keyDown", "keyUp":
            guard let keyCode = details["keyCode"] as? UInt16 else { return }
            cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: (type == "keyDown"))
            if let event = cgEvent {
                 event.flags = cgEventFlags // Apply original modifier flags
                 event.post(tap: .cghidEventTap)
            }

        case "mouseDown", "mouseUp":
            var buttonType: CGMouseButton = .left
            if let buttonStr = details["button"] as? String {
                if buttonStr == "right" { buttonType = .right }
                else if buttonStr == "middle" { buttonType = .center }
            }

            var eventType: CGEventType?
            if type == "mouseDown" {
                switch buttonType {
                    case .left: eventType = .leftMouseDown
                    case .right: eventType = .rightMouseDown
                    case .center: eventType = .otherMouseDown
                    default: break
                }
            } else { // mouseUp
                switch buttonType {
                    case .left: eventType = .leftMouseUp
                    case .right: eventType = .rightMouseUp
                    case .center: eventType = .otherMouseUp
                    default: break
                }
            }
            guard let finalEventType = eventType else { return }
            cgEvent = CGEvent(mouseEventSource: nil, mouseType: finalEventType, mouseCursorPosition: point, mouseButton: buttonType)
            if let event = cgEvent {
                if let clickCount = details["clickCount"] as? Int64 { // Ensure click count is set for mouse down
                     event.setIntegerValueField(.mouseEventClickState, value: clickCount)
                }
                event.post(tap: .cghidEventTap)
            }


        case "mouseMove": // Also covers drags for simulation
            // If it was a drag, determine button
            var eventType: CGEventType = .mouseMoved
            var buttonForDrag: CGMouseButton? = nil

            if let draggedButton = details["dragged_button"] as? String {
                if draggedButton == "left" { eventType = .leftMouseDragged; buttonForDrag = .left }
                else if draggedButton == "right" { eventType = .rightMouseDragged; buttonForDrag = .right }
                else if draggedButton == "other" { eventType = .otherMouseDragged; buttonForDrag = .center }
            }
            cgEvent = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: buttonForDrag ?? .left) // .left is default for mouseMoved
             if let event = cgEvent {
                event.post(tap: .cghidEventTap)
            }


        case "mouseWheel":
            guard let deltaY = details["deltaY"] as? Double else { return }
            // deltaX is also possible
            let deltaX = details["deltaX"] as? Double ?? 0

            // CGEvent for scrolling is a bit more complex.
            // It takes pixels. NSEvent.scrollingDeltaY is often in "lines" or points.
            // We might need a scaling factor if hasPreciseScrollingDeltas was false.
            // For now, assume direct usage.
            let scrollWheelEvent = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: Int32(deltaY), wheel2: Int32(deltaX), wheel3: 0)
            if let event = scrollWheelEvent {
                 event.post(tap: .cghidEventTap)
            }

        default:
            print("Native (macOS): Unknown event type for simulation: \(type)")
            return
        }
    }

    // MARK: - Permissions
    public func checkAccessibilityPermissions(prompt: Bool) -> Bool {
        if prompt {
            let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
            return AXIsProcessTrustedWithOptions(options)
        } else {
            return AXIsProcessTrusted()
        }
    }
}

// Helper to get main Flutter ViewController (adjust if your setup is different)
func getFlutterViewController() -> FlutterViewController? {
    if let delegate = NSApplication.shared.delegate as? FlutterAppDelegate {
        if let window = NSApplication.shared.windows.first { // Or iterate if multiple windows
            return window.contentViewController as? FlutterViewController
        }
    }
    // Fallback if AppDelegate structure is different or window not found easily
    // This might happen if the app structure is customized.
    // You might need a more robust way to get the controller if this fails.
    print("Warning: Could not get FlutterViewController via AppDelegate. Trying active window.")
    return NSApplication.shared.keyWindow?.contentViewController as? FlutterViewController
}
