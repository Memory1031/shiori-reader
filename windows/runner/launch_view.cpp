#include "launch_view.h"

#include <algorithm>

#include "resource.h"

namespace {

constexpr wchar_t kLaunchClass[] = L"SHIORI_LAUNCH_VIEW";

void PaintLaunchView(HWND window, HDC dc) {
  RECT bounds;
  GetClientRect(window, &bounds);
  DWORD light = 1;
  DWORD size = sizeof(light);
  RegGetValueW(HKEY_CURRENT_USER,
               L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
               L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &size);
  // Same paper/ink palette as the shared Flutter theme.
  const COLORREF paper = light ? RGB(250, 248, 244) : RGB(27, 24, 28);
  const auto background = CreateSolidBrush(paper);
  FillRect(dc, &bounds, background);
  DeleteObject(background);

  const double dpi_scale = GetDpiForWindow(window) / 96.0;
  // Keep the logo inside very small windows, preserving its proportions.
  const double scale = std::max(0.1, std::min({
      dpi_scale, (bounds.right - bounds.left) / 240.0,
      (bounds.bottom - bounds.top) / 356.0}));
  const int logo_size = static_cast<int>(128 * scale);
  const int left = (bounds.right - logo_size) / 2;
  // Keep the logo aligned with Flutter's LaunchView, including its text below.
  const int top = (bounds.bottom - static_cast<int>(356 * scale)) / 2;
  const int frame_left = (bounds.right - static_cast<int>(208 * scale)) / 2;
  const auto surface = CreateSolidBrush(light ? RGB(255, 252, 248) : RGB(37, 33, 38));
  const auto line = CreatePen(PS_SOLID, 1,
      light ? RGB(236, 234, 231) : RGB(53, 49, 55));
  const auto old_brush = SelectObject(dc, surface);
  const auto old_pen = SelectObject(dc, line);
  RoundRect(dc, frame_left + static_cast<int>(34 * scale),
            top + static_cast<int>(34 * scale),
            frame_left + static_cast<int>(174 * scale),
            top + static_cast<int>(174 * scale),
            static_cast<int>(60 * scale), static_cast<int>(60 * scale));
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(surface);
  DeleteObject(line);
  const int logo_top = top + static_cast<int>(40 * scale);
  // Load the existing high-resolution brand icon, not the small titlebar icon.
  const auto icon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      256, 256, LR_DEFAULTCOLOR));
  if (icon) {
    const int saved = SaveDC(dc);
    const int corner = static_cast<int>(48 * scale);
    const auto clip = CreateRoundRectRgn(left, logo_top, left + logo_size,
                                        logo_top + logo_size, corner, corner);
    SelectClipRgn(dc, clip);
    DrawIconEx(dc, left, logo_top, icon, logo_size, logo_size, 0, nullptr, DI_NORMAL);
    RestoreDC(dc, saved);
    DeleteObject(clip);
    DestroyIcon(icon);
  }
}

LRESULT CALLBACK LaunchWindowProc(HWND window, UINT message, WPARAM wparam,
                                  LPARAM lparam) {
  switch (message) {
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT paint;
      HDC dc = BeginPaint(window, &paint);
      PaintLaunchView(window, dc);
      EndPaint(window, &paint);
      return 0;
    }
    case WM_SETTINGCHANGE:
    case WM_DPICHANGED_AFTERPARENT:
      InvalidateRect(window, nullptr, FALSE);
      return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

}  // namespace

HWND CreateLaunchView(HWND parent) {
  const auto instance = GetModuleHandle(nullptr);
  WNDCLASSW window_class{};
  if (!GetClassInfoW(instance, kLaunchClass, &window_class)) {
    window_class.hInstance = instance;
    window_class.lpszClassName = kLaunchClass;
    window_class.lpfnWndProc = LaunchWindowProc;
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    if (!RegisterClassW(&window_class)) return nullptr;
  }
  RECT bounds;
  GetClientRect(parent, &bounds);
  return CreateWindowExW(0, kLaunchClass, L"Shiori", WS_CHILD | WS_VISIBLE,
                         0, 0, bounds.right, bounds.bottom, parent, nullptr,
                         instance, nullptr);
}
