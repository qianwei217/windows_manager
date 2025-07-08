#ifndef NATIVE_EVENT_HANDLER_H
#define NATIVE_EVENT_HANDLER_H

#include <windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <string>
#include <vector>
#include <map> // Required for flutter::EncodableMap

// Forward declaration
namespace flutter {
    class EventSink;
    class BinaryMessenger;
}

struct RecordedEvent {
    std::string type; // "keyDown", "keyUp", "mouseMove", "mouseDown", "mouseUp"
    std::map<std::string, flutter::EncodableValue> details;
    DWORD time; // Using DWORD for GetTickCount() compatibility
};

class NativeEventHandler {
public:
    NativeEventHandler(flutter::BinaryMessenger* messenger);
    ~NativeEventHandler();

    void StartRecording();
    void StopRecording();
    void PlayEvents(const flutter::EncodableList& events);

private:
    static LRESULT CALLBACK LowLevelKeyboardProc(int nCode, WPARAM wParam, LPARAM lParam);
    static LRESULT CALLBACK LowLevelMouseProc(int nCode, WPARAM wParam, LPARAM lParam);

    void SendEventToFlutter(const std::string& event_type, const flutter::EncodableMap& details);
    // void SendRecordedEventToFlutter(const RecordedEvent& event); // This will be handled by SendEventToFlutter


    static NativeEventHandler* instance_; // Static instance pointer

    HHOOK keyboard_hook_ = nullptr;
    HHOOK mouse_hook_ = nullptr;
    bool is_recording_ = false;

    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> event_channel_;
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;

    std::vector<RecordedEvent> recorded_events_for_playback_; // Not used for recording, but for playing back events from Flutter

    // Helper to convert VK_CODE to string, can be expanded
    std::string VKCodeToString(int vk_code);
};

#endif // NATIVE_EVENT_HANDLER_H
