#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/event_channel.h>
#include <flutter/event_sink.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"

// Hosts a native launch cover until the Flutter view has rendered its first frame.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  HWND launch_view_ = nullptr;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> drop_channel_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> drop_sink_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> app_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
