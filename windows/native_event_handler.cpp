#include "native_event_handler.h"
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <windows.h>
#include <iostream> // For debugging
#include <vector>
#include <map>
#include <sstream> // Required for ostringstream

// Initialize static instance pointer
NativeEventHandler* NativeEventHandler::instance_ = nullptr;

NativeEventHandler::NativeEventHandler(flutter::BinaryMessenger* messenger) {
    instance_ = this; // Set the static instance

    // Setup EventChannel to send events from C++ to Dart
    event_channel_ = std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
        messenger, "com.example.app/native_events",
        &flutter::StandardMethodCodec::GetInstance());

    auto handler = std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
        [this](const flutter::EncodableValue* arguments, std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
            this->event_sink_ = std::move(events);
            return nullptr; // Success
        },
        [this](const flutter::EncodableValue* arguments) {
            this->event_sink_.reset();
            return nullptr; // Success
        }
    );
    event_channel_->SetStreamHandler(std::move(handler));
}

NativeEventHandler::~NativeEventHandler() {
    StopRecording();
    instance_ = nullptr;
}

void NativeEventHandler::StartRecording() {
    if (is_recording_) return;

    std::cout << "Native: StartRecording called" << std::endl;

    // Set low-level keyboard hook
    keyboard_hook_ = SetWindowsHookExA(
        WH_KEYBOARD_LL,
        LowLevelKeyboardProc,
        GetModuleHandle(nullptr),
        0
    );

    // Set low-level mouse hook
    mouse_hook_ = SetWindowsHookExA(
        WH_MOUSE_LL,
        LowLevelMouseProc,
        GetModuleHandle(nullptr),
        0
    );

    if (keyboard_hook_ && mouse_hook_) {
        is_recording_ = true;
        std::cout << "Native: Hooks set successfully." << std::endl;
        flutter::EncodableMap details;
        details[flutter::EncodableValue("message")] = flutter::EncodableValue("Recording started successfully.");
        SendEventToFlutter("status", details);
    } else {
        std::cerr << "Native: Failed to set hooks. Keyboard: " << (keyboard_hook_ != nullptr)
                  << ", Mouse: " << (mouse_hook_ != nullptr)
                  << " Error: " << GetLastError() << std::endl;
        if (keyboard_hook_) UnhookWindowsHookEx(keyboard_hook_);
        if (mouse_hook_) UnhookWindowsHookEx(mouse_hook_);
        keyboard_hook_ = nullptr;
        mouse_hook_ = nullptr;
        is_recording_ = false;

        flutter::EncodableMap details;
        details[flutter::EncodableValue("error")] = flutter::EncodableValue("Failed to set hooks.");
        SendEventToFlutter("status", details);
    }
}

void NativeEventHandler::StopRecording() {
    if (!is_recording_) return;

    std::cout << "Native: StopRecording called" << std::endl;

    if (keyboard_hook_) {
        UnhookWindowsHookEx(keyboard_hook_);
        keyboard_hook_ = nullptr;
    }
    if (mouse_hook_) {
        UnhookWindowsHookEx(mouse_hook_);
        mouse_hook_ = nullptr;
    }
    is_recording_ = false;
    std::cout << "Native: Hooks removed." << std::endl;
    flutter::EncodableMap details;
    details[flutter::EncodableValue("message")] = flutter::EncodableValue("Recording stopped.");
    SendEventToFlutter("status", details);
}

// This function converts a virtual key code to its string representation
std::string NativeEventHandler::VKCodeToString(int vk_code) {
    // For common keys, directly map them
    if (vk_code >= 0x30 && vk_code <= 0x39) return std::string(1, (char)vk_code); // 0-9
    if (vk_code >= 0x41 && vk_code <= 0x5A) return std::string(1, (char)vk_code); // A-Z

    // Special keys
    switch (vk_code) {
        case VK_SPACE: return "SPACE";
        case VK_RETURN: return "ENTER";
        case VK_BACK: return "BACKSPACE";
        case VK_TAB: return "TAB";
        case VK_SHIFT: case VK_LSHIFT: case VK_RSHIFT: return "SHIFT";
        case VK_CONTROL: case VK_LCONTROL: case VK_RCONTROL: return "CTRL";
        case VK_MENU: case VK_LMENU: case VK_RMENU: return "ALT";
        case VK_ESCAPE: return "ESC";
        case VK_LEFT: return "LEFT_ARROW";
        case VK_UP: return "UP_ARROW";
        case VK_RIGHT: return "RIGHT_ARROW";
        case VK_DOWN: return "DOWN_ARROW";
        case VK_OEM_1: return ";:";
        case VK_OEM_PLUS: return "+=";
        case VK_OEM_COMMA: return ",<";
        case VK_OEM_MINUS: return "-_";
        case VK_OEM_PERIOD: return ".>";
        case VK_OEM_2: return "/?";
        case VK_OEM_3: return "`~";
        case VK_OEM_4: return "[{";
        case VK_OEM_5: return "\\|";
        case VK_OEM_6: return "]}";
        case VK_OEM_7: return "'\"";
        // Add more mappings as needed
        default:
            std::ostringstream oss;
            oss << "VK(" << vk_code << ")";
            return oss.str();
    }
}


LRESULT CALLBACK NativeEventHandler::LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode == HC_ACTION && instance_ && instance_->is_recording_ && instance_->event_sink_) {
        KBDLLHOOKSTRUCT *pkhs = (KBDLLHOOKSTRUCT *)lParam;
        std::string event_type;
        flutter::EncodableMap details;

        if (wParam == WM_KEYDOWN || wParam == WM_SYSKEYDOWN) {
            event_type = "keyDown";
        } else if (wParam == WM_KEYUP || wParam == WM_SYSKEYUP) {
            event_type = "keyUp";
        }

        if (!event_type.empty()) {
            details[flutter::EncodableValue("vk_code")] = flutter::EncodableValue((int)pkhs->vkCode);
            details[flutter::EncodableValue("key")] = flutter::EncodableValue(instance_->VKCodeToString(pkhs->vkCode));
            details[flutter::EncodableValue("scan_code")] = flutter::EncodableValue((int)pkhs->scanCode);
            details[flutter::EncodableValue("timestamp")] = flutter::EncodableValue((int64_t)GetTickCount64());
            // Add more details if needed, e.g., flags for ctrl/shift/alt
            // pkhs->flags & LLKHF_ALTDOWN, LLKHF_EXTENDED etc.
            // GetKeyState(VK_SHIFT) & 0x8000, etc.
            details[flutter::EncodableValue("is_ctrl_pressed")] = flutter::EncodableValue((GetKeyState(VK_CONTROL) & 0x8000) != 0);
            details[flutter::EncodableValue("is_shift_pressed")] = flutter::EncodableValue((GetKeyState(VK_SHIFT) & 0x8000) != 0);
            details[flutter::EncodableValue("is_alt_pressed")] = flutter::EncodableValue((GetKeyState(VK_MENU) & 0x8000) != 0);

            instance_->SendEventToFlutter(event_type, details);
        }
    }
    return CallNextHookEx(instance_ ? instance_->keyboard_hook_ : NULL, nCode, wParam, lParam);
}

LRESULT CALLBACK NativeEventHandler::LowLevelMouseProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode == HC_ACTION && instance_ && instance_->is_recording_ && instance_->event_sink_) {
        MSLLHOOKSTRUCT *pmhs = (MSLLHOOKSTRUCT *)lParam;
        std::string event_type;
        flutter::EncodableMap details;

        switch (wParam) {
            case WM_LBUTTONDOWN: event_type = "mouseDown"; details[flutter::EncodableValue("button")] = flutter::EncodableValue("left"); break;
            case WM_LBUTTONUP: event_type = "mouseUp"; details[flutter::EncodableValue("button")] = flutter::EncodableValue("left"); break;
            case WM_RBUTTONDOWN: event_type = "mouseDown"; details[flutter::EncodableValue("button")] = flutter::EncodableValue("right"); break;
            case WM_RBUTTONUP: event_type = "mouseUp"; details[flutter::EncodableValue("button")] = flutter::EncodableValue("right"); break;
            case WM_MBUTTONDOWN: event_type = "mouseDown"; details[flutter::EncodableValue("button")] = flutter::EncodableValue("middle"); break;
            case WM_MBUTTONUP: event_type = "mouseUp"; details[flutter::EncodableValue("button")] = flutter::EncodableValue("middle"); break;
            case WM_MOUSEMOVE: event_type = "mouseMove"; break;
            case WM_MOUSEWHEEL:
                event_type = "mouseWheel";
                details[flutter::EncodableValue("delta")] = flutter::EncodableValue((int)GET_WHEEL_DELTA_WPARAM(pmhs->mouseData));
                break;
            // case WM_XBUTTONDOWN: // For extra mouse buttons
            // case WM_XBUTTONUP:
            //     event_type = (wParam == WM_XBUTTONDOWN) ? "mouseDown" : "mouseUp";
            //     details[flutter::EncodableValue("button")] = flutter::EncodableValue( (GET_XBUTTON_WPARAM(pmhs->mouseData) == XBUTTON1) ? "xbutton1" : "xbutton2" );
            //     break;
        }

        if (!event_type.empty()) {
            details[flutter::EncodableValue("x")] = flutter::EncodableValue(pmhs->pt.x);
            details[flutter::EncodableValue("y")] = flutter::EncodableValue(pmhs->pt.y);
            details[flutter::EncodableValue("timestamp")] = flutter::EncodableValue((int64_t)GetTickCount64());

            instance_->SendEventToFlutter(event_type, details);
        }
    }
    return CallNextHookEx(instance_ ? instance_->mouse_hook_ : NULL, nCode, wParam, lParam);
}

void NativeEventHandler::SendEventToFlutter(const std::string& event_type, const flutter::EncodableMap& details_map) {
    if (event_sink_) {
        flutter::EncodableMap event_data;
        event_data[flutter::EncodableValue("type")] = flutter::EncodableValue(event_type);
        event_data[flutter::EncodableValue("details")] = flutter::EncodableValue(details_map);
        event_sink_->Success(flutter::EncodableValue(event_data));
    }
}


void NativeEventHandler::PlayEvents(const flutter::EncodableList& events_from_flutter) {
    std::cout << "Native: PlayEvents called with " << events_from_flutter.size() << " events." << std::endl;
    if (is_recording_) {
        std::cerr << "Native: Cannot play events while recording." << std::endl;
        return;
    }

    INPUT input = {0};
    DWORD last_event_time_ms = 0;
    bool first_event = true;

    for (const auto& encodable_event : events_from_flutter) {
        if (!encodable_event.IsMap()) continue;
        const auto& event_map = std::get<flutter::EncodableMap>(encodable_event);

        auto type_it = event_map.find(flutter::EncodableValue("type"));
        auto details_it = event_map.find(flutter::EncodableValue("details"));
        auto timestamp_it = event_map.find(flutter::EncodableValue("timestamp")); // Assuming timestamp is at the top level of the event map from Dart

        if (type_it == event_map.end() || !std::holds_alternative<std::string>(type_it->second) ||
            details_it == event_map.end() || !std::holds_alternative<flutter::EncodableMap>(details_it->second) ||
            timestamp_it == event_map.end() || !std::holds_alternative<int64_t>(timestamp_it->second) ) {
            std::cerr << "Native: Malformed event received for playback." << std::endl;
            continue;
        }

        std::string type = std::get<std::string>(type_it->second);
        const auto& details = std::get<flutter::EncodableMap>(details_it->second);
        int64_t current_event_time_flutter_ms = std::get<int64_t>(timestamp_it->second); // This is the original timestamp from Flutter/Dart

        // Calculate delay
        // The timestamp from Flutter is DateTime.millisecondsSinceEpoch
        // We need to simulate the *delay* between events, not absolute time.
        // For now, let's assume the Dart side will send a "delay_ms" field if precise timing is needed,
        // or we use a fixed delay for simplicity. Or, better, calculate delta from Dart timestamps.
        // Let's try to use the original timestamps to calculate delays.

        DWORD current_event_time_ms = static_cast<DWORD>(current_event_time_flutter_ms % 0xFFFFFFFF); // Using lower 32 bits, similar to GetTickCount()

        if (!first_event && last_event_time_ms != 0) {
            DWORD delay_ms = 0;
            if (current_event_time_ms >= last_event_time_ms) {
                 delay_ms = current_event_time_ms - last_event_time_ms;
            } else { // Tick count wrapped around
                 delay_ms = (0xFFFFFFFF - last_event_time_ms) + current_event_time_ms + 1;
            }
            if (delay_ms > 0) {
                Sleep(delay_ms);
            }
        }
        last_event_time_ms = current_event_time_ms;
        first_event = false;


        ZeroMemory(&input, sizeof(INPUT));

        if (type == "keyDown" || type == "keyUp") {
            input.type = INPUT_KEYBOARD;
            auto vk_code_it = details.find(flutter::EncodableValue("vk_code"));
            if (vk_code_it != details.end() && std::holds_alternative<int32_t>(vk_code_it->second)) {
                input.ki.wVk = static_cast<WORD>(std::get<int32_t>(vk_code_it->second));
            } else {
                 std::cerr << "Native: Missing vk_code for key event." << std::endl;
                 continue;
            }
            input.ki.dwFlags = (type == "keyUp" ? KEYEVENTF_KEYUP : 0);
            // input.ki.dwFlags |= KEYEVENTF_SCANCODE; // If using scancodes
            // auto scan_code_it = details.find(flutter::EncodableValue("scan_code"));
            // if (scan_code_it != details.end() && std::holds_alternative<int32_t>(scan_code_it->second)) {
            //    input.ki.wScan = static_cast<WORD>(std::get<int32_t>(scan_code_it->second));
            // }
        } else if (type == "mouseMove" || type == "mouseDown" || type == "mouseUp" || type == "mouseWheel") {
            input.type = INPUT_MOUSE;
            auto x_it = details.find(flutter::EncodableValue("x"));
            auto y_it = details.find(flutter::EncodableValue("y"));

            if (x_it != details.end() && std::holds_alternative<int32_t>(x_it->second) &&
                y_it != details.end() && std::holds_alternative<int32_t>(y_it->second)) {
                // Mouse coordinates need to be normalized (0-65535)
                input.mi.dx = static_cast<LONG>((std::get<int32_t>(x_it->second) * 65535.0) / GetSystemMetrics(SM_CXSCREEN));
                input.mi.dy = static_cast<LONG>((std::get<int32_t>(y_it->second) * 65535.0) / GetSystemMetrics(SM_CYSCREEN));
                input.mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE;
            } else if (type != "mouseWheel") { // mouseWheel might not have x,y if it's just scrolling
                 std::cerr << "Native: Missing x/y for mouse event." << std::endl;
                 continue;
            }


            if (type == "mouseDown" || type == "mouseUp") {
                auto button_it = details.find(flutter::EncodableValue("button"));
                if (button_it != details.end() && std::holds_alternative<std::string>(button_it->second)) {
                    std::string button = std::get<std::string>(button_it->second);
                    if (button == "left") {
                        input.mi.dwFlags |= (type == "mouseDown" ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP);
                    } else if (button == "right") {
                        input.mi.dwFlags |= (type == "mouseDown" ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP);
                    } else if (button == "middle") {
                        input.mi.dwFlags |= (type == "mouseDown" ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP);
                    }
                    // Add XBUTTON support if needed
                } else {
                    std::cerr << "Native: Missing button type for mouse click." << std::endl;
                    continue;
                }
            } else if (type == "mouseWheel") {
                auto delta_it = details.find(flutter::EncodableValue("delta"));
                 if (delta_it != details.end() && std::holds_alternative<int32_t>(delta_it->second)) {
                    input.mi.mouseData = static_cast<DWORD>(std::get<int32_t>(delta_it->second));
                    input.mi.dwFlags = MOUSEEVENTF_WHEEL; // No MOUSEEVENTF_ABSOLUTE or MOUSEEVENTF_MOVE for wheel
                 } else {
                    std::cerr << "Native: Missing delta for mouse wheel." << std::endl;
                    continue;
                 }
            }
             // If it's just a move, MOUSEEVENTF_MOVE is already set.
            // If it's a click, MOUSEEVENTF_MOVE might also be needed if the click implies a position.
            // SendInput will use current cursor position if MOUSEEVENTF_MOVE is not set with MOUSEEVENTF_ABSOLUTE.
            // For playback, we always want to set the position explicitly.
            if (type != "mouseWheel") { // mouseWheel uses current cursor position
                 input.mi.dwFlags |= MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
                 if (x_it == details.end() || y_it == details.end()) { // Ensure x,y are present for non-wheel mouse events
                    std::cerr << "Native: x/y coordinates are required for non-wheel mouse events during playback." << std::endl;
                    continue;
                 }
            }


        } else {
            std::cerr << "Native: Unknown event type for playback: " << type << std::endl;
            continue;
        }

        UINT res = SendInput(1, &input, sizeof(INPUT));
        if (res == 0) {
            std::cerr << "Native: SendInput failed. Error: " << GetLastError() << std::endl;
        }
    }
    std::cout << "Native: Finished playing events." << std::endl;
}
