#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"
#include "../native_event_handler.h" // Added for native event handling
#include <flutter/method_channel.h>    // Added for method channel
#include <flutter/standard_method_codec.h> // Added for method channel

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  void SetupMethodChannel(); // Added
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native event handler instance
  std::unique_ptr<NativeEventHandler> native_event_handler_; // Added

  // Method channel for communication with Flutter
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> method_channel_; // Added
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
