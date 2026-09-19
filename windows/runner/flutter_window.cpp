#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>

#include "flutter/generated_plugin_registrant.h"
#include "launch_view.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  launch_view_ = CreateLaunchView(GetHandle());
  if (launch_view_) {
    Show();
    // Paint before synchronous engine/plugin initialization occupies this thread.
    UpdateWindow(launch_view_);
  }

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  if (launch_view_) {
    SetWindowPos(launch_view_, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }

  drop_channel_ =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "dev.shiori.reader/file_drop",
          &flutter::StandardMethodCodec::GetInstance());
  drop_channel_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [this](const flutter::EncodableValue*,
                 std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& sink)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            drop_sink_ = std::move(sink);
            DragAcceptFiles(GetHandle(), TRUE);
            return nullptr;
          },
          [this](const flutter::EncodableValue*)
              -> std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>> {
            DragAcceptFiles(GetHandle(), FALSE);
            drop_sink_.reset();
            return nullptr;
          }));

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (launch_view_) {
      DestroyWindow(launch_view_);
      launch_view_ = nullptr;
    } else {
      Show();
    }
  });

  // Flutter can complete the first frame before the launch-cover callback is
  // registered. The following call ensures a frame is pending to ensure the
  // Flutter view is revealed. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (launch_view_) {
    DestroyWindow(launch_view_);
    launch_view_ = nullptr;
  }
  DragAcceptFiles(GetHandle(), FALSE);
  drop_sink_.reset();
  drop_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_SIZE && launch_view_) {
    RECT bounds = GetClientArea();
    MoveWindow(launch_view_, 0, 0, bounds.right, bounds.bottom, TRUE);
  }
  if (message == WM_DROPFILES) {
    const auto drop = reinterpret_cast<HDROP>(wparam);
    const UINT count = DragQueryFileW(drop, 0xFFFFFFFF, nullptr, 0);
    flutter::EncodableList paths;
    bool valid = count > 0 && count <= 64;
    for (UINT i = 0; valid && i < count; ++i) {
      const UINT length = DragQueryFileW(drop, i, nullptr, 0);
      if (length == 0 || length > 32767) {
        valid = false;
        break;
      }
      std::vector<wchar_t> path(length + 1);
      if (DragQueryFileW(drop, i, path.data(), length + 1) != length) {
        valid = false;
        break;
      }
      const auto utf8 = Utf8FromUtf16(path.data());
      if (utf8.empty()) {
        valid = false;
        break;
      }
      paths.emplace_back(utf8);
    }
    DragFinish(drop);
    if (drop_sink_) {
      if (valid) {
        drop_sink_->Success(flutter::EncodableValue(paths));
      } else {
        drop_sink_->Error(count > 64 ? "batchLimit" : "unreadable",
                          "Cannot receive the dropped files");
      }
    }
    return 0;
  }
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
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
