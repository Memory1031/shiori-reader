#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <string>
#include <vector>
#include <flutter/standard_method_codec.h>
#include <flutter/event_stream_handler_functions.h>

#include "flutter/generated_plugin_registrant.h"
#include "launch_view.h"
#include "utils.h"

namespace {

// Starts the updater copy staged in <install>.update, handing it a waitable
// handle to this process so it replaces files only after the app has exited.
// Paths are derived here rather than taken from Dart, so the channel cannot
// launch arbitrary programs.
bool StartUpdater() {
  std::wstring executable(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = GetModuleFileNameW(nullptr, executable.data(),
                                            static_cast<DWORD>(executable.size()));
    if (length == 0) return false;
    if (length < executable.size()) {
      executable.resize(length);
      break;
    }
    if (executable.size() >= 32768) return false;
    executable.resize(executable.size() * 2);
  }
  const auto separator = executable.find_last_of(L'\\');
  // A drive root cannot have a sibling workspace.
  if (separator == std::wstring::npos || separator < 3) return false;
  const std::wstring install = executable.substr(0, separator);
  const std::wstring workspace = install + L".update";
  const std::wstring updater = workspace + L"\\shiori-updater.exe";

  // The updater waits on the handle and checks with GetProcessId that it names a process.
  HANDLE self = nullptr;
  if (!DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(), GetCurrentProcess(),
                       &self, SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, TRUE, 0)) {
    return false;
  }
  SIZE_T size = 0;
  InitializeProcThreadAttributeList(nullptr, 1, 0, &size);
  std::vector<char> storage(size);
  auto* attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
  bool started = false;
  if (InitializeProcThreadAttributeList(attributes, 1, 0, &size)) {
    // Only the process handle is inherited, nothing else this process holds.
    if (UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                  &self, sizeof(self), nullptr, nullptr)) {
      STARTUPINFOEXW startup{};
      startup.StartupInfo.cb = sizeof(startup);
      startup.lpAttributeList = attributes;
      std::wstring command = L"\"" + updater + L"\" apply \"" + workspace + L"\" \"" +
                             install + L"\" " +
                             std::to_wstring(reinterpret_cast<uintptr_t>(self));
      PROCESS_INFORMATION process{};
      // Leave a job that would kill the updater when the app exits, if allowed.
      const DWORD attempts[] = {EXTENDED_STARTUPINFO_PRESENT | CREATE_BREAKAWAY_FROM_JOB,
                                EXTENDED_STARTUPINFO_PRESENT};
      for (const DWORD flags : attempts) {
        if (CreateProcessW(updater.c_str(), command.data(), nullptr, nullptr, TRUE, flags,
                           nullptr, workspace.c_str(), &startup.StartupInfo, &process)) {
          CloseHandle(process.hThread);
          CloseHandle(process.hProcess);
          started = true;
          break;
        }
        if (GetLastError() != ERROR_ACCESS_DENIED) break;
      }
    }
    DeleteProcThreadAttributeList(attributes);
  }
  CloseHandle(self);
  return started;
}

}  // namespace

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
  app_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "dev.shiori.reader/app",
      &flutter::StandardMethodCodec::GetInstance());
  app_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "info") {
      const auto version = std::to_string(FLUTTER_VERSION_MAJOR) + "." +
          std::to_string(FLUTTER_VERSION_MINOR) + "." + std::to_string(FLUTTER_VERSION_PATCH);
      result->Success(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("version"), flutter::EncodableValue(version)},
          {flutter::EncodableValue("build"), flutter::EncodableValue(FLUTTER_VERSION_BUILD)}}));
    } else if (call.method_name() == "openRelease") {
      const auto* url = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
      const std::string prefix = "https://github.com/Memory1031/shiori-reader/releases/";
      if (!url || (*url != "https://github.com/Memory1031/shiori-reader" &&
                   url->rfind(prefix, 0) != 0) ||
          url->find_first_of("\r\n\"\\?#") != std::string::npos ||
          url->find('\0') != std::string::npos) {
        result->Success(flutter::EncodableValue(false));
        return;
      }
      const std::wstring target(url->begin(), url->end());
      const auto opened = reinterpret_cast<INT_PTR>(ShellExecuteW(
          nullptr, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
      result->Success(flutter::EncodableValue(opened > 32));
    } else if (call.method_name() == "startUpdater") {
      result->Success(flutter::EncodableValue(StartUpdater()));
    } else if (call.method_name() == "exit") {
      // Normal window close, after Dart has flushed and closed its stores.
      result->Success();
      PostMessage(GetHandle(), WM_CLOSE, 0, 0);
    } else {
      result->NotImplemented();
    }
  });
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
  if (app_channel_) app_channel_->SetMethodCallHandler(nullptr);
  app_channel_.reset();
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
