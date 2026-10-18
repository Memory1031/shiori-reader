#include "win32_window.h"
#include "window_placement.h"
#include <flutter_windows.h>

#include <iostream>
#include <algorithm>
#include <stdexcept>
#include <string>

using shiori::window::FitBounds;
using shiori::window::LoadPlacement;
using shiori::window::Placement;
using shiori::window::RestoreBounds;
using shiori::window::SavePlacement;

namespace {
void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
bool Same(RECT a, RECT b) { return EqualRect(&a, &b) != FALSE; }
void Pump() {
  MSG message;
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
}
RECT Bounds(HWND window) {
  RECT rect{};
  Check(GetWindowRect(window, &rect), "Cannot read native bounds");
  return rect;
}
RECT Work(HWND window) {
  MONITORINFO info{sizeof(info)};
  Check(GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &info),
        "Cannot read native work area");
  return info.rcWork;
}
class Window : public Win32Window {
 public:
  explicit Window(const std::wstring& key) : Win32Window(key) {}
  void Open() {
    Check(Create(L"Shiori window placement test", Point(0, 0), Size(1280, 900), true),
          "Cannot create native test window");
    Pump();
  }
 protected:
  bool OnCreate() override { return Show(); }
};

void Geometry() {
  Check(Same(FitBounds({-100, -200, 2000, 1200}, {0, 40, 1024, 728}, {840, 600}),
             {0, 40, 1024, 728}), "Oversized window must fit below a top taskbar");
  Check(Same(FitBounds({900, 700, 1000, 800}, {0, 0, 1024, 768}, {840, 600}),
             {184, 168, 1024, 768}), "Minimum size must remain on-screen");
  Check(Same(FitBounds({0, 0, 1100, 800}, {-800, -600, 0, 0}, {840, 600}),
             {-800, -600, 0, 0}), "Small and negative-coordinate screens must fit");
  Placement saved;
  saved.bounds = {120, 140, 1220, 940};
  saved.work = {0, 40, 1920, 1080};
  Check(Same(RestoreBounds(saved, {-3840, 80, 0, 2160}, 192, {}),
             {-3600, 280, -1400, 1880}), "DPI change must preserve logical size and work-relative position");
  Check(Same(RestoreBounds(saved, {0, 0, 800, 600}, 96, {840, 600}),
             {0, 0, 800, 600}), "Disconnected large screen must fit the replacement screen");
  Check(shiori::window::ValidPlacement(saved), "Known placement must be valid");
  saved.version = 2;
  Check(!shiori::window::ValidPlacement(saved), "Unknown placement version must be ignored");
  saved.version = 1;
  saved.dpi = 0;
  Check(!shiori::window::ValidPlacement(saved), "Zero DPI must be ignored");
  saved.dpi = 96;
  saved.bounds.right = LONG_MAX;
  Check(!shiori::window::ValidPlacement(saved), "Corrupt dimensions must be ignored before arithmetic");
}

void Lifecycle(const std::wstring& key) {
  Check(!LoadPlacement(key), "Test must begin with isolated empty preferences");
  RECT ordinary{};
  {
    Window first(key);
    first.Open();
    const auto dpi = FlutterDesktopGetDpiForHWND(first.GetHandle());
    const auto work = Work(first.GetHandle());
    const auto frame = Bounds(first.GetHandle());
    Check(frame.right - frame.left == std::min<LONG>(MulDiv(1280, dpi, 96), work.right - work.left) &&
          frame.bottom - frame.top == std::min<LONG>(MulDiv(900, dpi, 96), work.bottom - work.top),
          "Default window must be 1280x900 logical outer pixels, fitted to work area");
    Check(frame.left == work.left + (work.right - work.left - (frame.right - frame.left)) / 2 &&
          frame.top == work.top + (work.bottom - work.top - (frame.bottom - frame.top)) / 2,
          "First launch must be centered in the usable screen area");
    SetWindowPos(first.GetHandle(), nullptr, work.left + 60, work.top + 50,
                 MulDiv(960, dpi, 96), MulDiv(680, dpi, 96), SWP_NOZORDER);
    Pump();
    ordinary = Bounds(first.GetHandle());
    first.Destroy();
  }
  Check(Same(LoadPlacement(key)->bounds, ordinary), "Close must persist actual ordinary bounds");
  {
    Window second(key);
    second.Open();
    Check(Same(Bounds(second.GetHandle()), ordinary), "Native recreation must restore size and position");
    ShowWindow(second.GetHandle(), SW_MAXIMIZE);
    Pump();
    second.Show();
    Check(IsZoomed(second.GetHandle()), "Repeated Show must not undo maximization");
    ShowWindow(second.GetHandle(), SW_MINIMIZE);
    Pump();
    second.Destroy();
  }
  const auto maximum = LoadPlacement(key);
  Check(maximum && maximum->maximized == 1 && Same(maximum->bounds, ordinary),
        "Minimizing a maximized window must preserve maximized state and ordinary bounds");
  {
    Window third(key);
    third.Open();
    Check(IsZoomed(third.GetHandle()), "Native recreation must restore maximization");
    ShowWindow(third.GetHandle(), SW_RESTORE);
    Pump();
    Check(Same(Bounds(third.GetHandle()), ordinary), "Restoring maximization must recover ordinary bounds");
    ShowWindow(third.GetHandle(), SW_MINIMIZE);
    Pump();
    third.Destroy();
  }
  Check(LoadPlacement(key)->maximized == 0, "A minimized ordinary window must reopen normally");
  auto offscreen = *LoadPlacement(key);
  offscreen.bounds = {30000, 20000, 32000, 22000};
  offscreen.work = {30000, 20000, 34000, 24000};
  offscreen.monitor[0] = L'\0';
  SavePlacement(key, offscreen);
  {
    Window fourth(key);
    fourth.Open();
    const auto rect = Bounds(fourth.GetHandle());
    Check(Same(rect, FitBounds(rect, Work(fourth.GetHandle()), {})),
          "A removed monitor must not strand the restored window off-screen");
    fourth.Destroy();
  }
  const DWORD marker = 42;
  RegSetKeyValueW(HKEY_CURRENT_USER, key.c_str(), L"Unrelated", REG_DWORD, &marker, sizeof(marker));
  RegSetKeyValueW(HKEY_CURRENT_USER, key.c_str(), L"Placement", REG_BINARY, &marker, sizeof(marker));
  Check(!LoadPlacement(key), "Truncated registry preference must be ignored");
  {
    Window fallback(key);
    fallback.Open();
    fallback.Destroy();
  }
  DWORD preserved = 0;
  DWORD size = sizeof(preserved);
  Check(RegGetValueW(HKEY_CURRENT_USER, key.c_str(), L"Unrelated", RRF_RT_REG_DWORD,
                     nullptr, &preserved, &size) == ERROR_SUCCESS && preserved == marker,
        "Preference recovery must preserve unrelated settings");
}
}  // namespace

int main(int argc, char** argv) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  const std::wstring key = L"Software\\Shiori\\Tests\\WindowPlacement-" + std::to_wstring(GetCurrentProcessId());
  try {
    Check(argc == 2, "Expected geometry or lifecycle");
    if (std::string(argv[1]) == "geometry") Geometry();
    else Lifecycle(key);
    RegDeleteTreeW(HKEY_CURRENT_USER, key.c_str());
    std::cout << "PASS " << argv[1] << std::endl;
    return 0;
  } catch (const std::exception& error) {
    RegDeleteTreeW(HKEY_CURRENT_USER, key.c_str());
    std::cerr << error.what() << std::endl;
    return 1;
  }
}
