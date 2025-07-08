#include "flutter_window.h"

#include <optional>
#include <iostream> // For debugging output

#include "flutter/generated_plugin_registrant.h"
// #include "../native_event_handler.h" // Already included via flutter_window.h

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
    // native_event_handler_ will be automatically destructed if unique_ptr,
    // which should call its StopRecording and release hooks.
}

void FlutterWindow::SetupMethodChannel() {
    if (!flutter_controller_ || !flutter_controller_->engine()) {
        return;
    }
    flutter::BinaryMessenger* messenger = flutter_controller_->engine()->messenger();
    native_event_handler_ = std::make_unique<NativeEventHandler>(messenger);

    method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        messenger, "com.example.app/control",
        &flutter::StandardMethodCodec::GetInstance());

    method_channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
            if (!native_event_handler_) {
                result->Error("UNAVAILABLE", "Native event handler not initialized.");
                return;
            }
            if (call.method_name().compare("startRecording") == 0) {
                std::cout << "Cpp: startRecording called from Flutter" << std::endl;
                native_event_handler_->StartRecording();
                result->Success(flutter::EncodableValue(true));
            } else if (call.method_name().compare("stopRecording") == 0) {
                std::cout << "Cpp: stopRecording called from Flutter" << std::endl;
                native_event_handler_->StopRecording();
                result->Success(flutter::EncodableValue(true));
            } else if (call.method_name().compare("playEvents") == 0) {
                std::cout << "Cpp: playEvents called from Flutter" << std::endl;
                const auto* args = std::get_if<flutter::EncodableList>(call.arguments());
                if (args) {
                    native_event_handler_->PlayEvents(*args);
                    result->Success(flutter::EncodableValue(true));
                } else {
                    result->Error("INVALID_ARGUMENT", "Expected a list of events.");
                }
            } else {
                result->NotImplemented();
            }
        });
}


bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  // Setup MethodChannel and NativeEventHandler
  SetupMethodChannel();

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (native_event_handler_) {
    native_event_handler_->StopRecording(); // Ensure hooks are released
    native_event_handler_ = nullptr;
  }
  if (method_channel_) {
    method_channel_->SetMethodCallHandler(nullptr);
    method_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
