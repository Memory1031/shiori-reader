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
  const COLORREF ink = light ? RGB(48, 44, 43) : RGB(238, 231, 235);
  const auto background = CreateSolidBrush(paper);
  FillRect(dc, &bounds, background);
  DeleteObject(background);

  const double dpi_scale = GetDpiForWindow(window) / 96.0;
  // Keep the brand group inside very small windows, preserving its proportions.
  const double scale = std::max(0.1, std::min({
      dpi_scale, (bounds.right - bounds.left) / 192.0,
      (bounds.bottom - bounds.top) / 248.0}));
  const int logo_size = static_cast<int>(128 * scale);
  const int group_height = static_cast<int>(192 * scale);
  const int left = (bounds.right - logo_size) / 2;
  const int top = (bounds.bottom - group_height) / 2;
  // Load the existing high-resolution brand icon, not the small titlebar icon.
  const auto icon = static_cast<HICON>(LoadImageW(
      GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      256, 256, LR_DEFAULTCOLOR));
  if (icon) {
    const int saved = SaveDC(dc);
    const int corner = static_cast<int>(48 * scale);
    const auto clip = CreateRoundRectRgn(left, top, left + logo_size,
                                        top + logo_size, corner, corner);
    SelectClipRgn(dc, clip);
    DrawIconEx(dc, left, top, icon, logo_size, logo_size, 0, nullptr, DI_NORMAL);
    RestoreDC(dc, saved);
    DeleteObject(clip);
    DestroyIcon(icon);
  }

  const auto font = CreateFontW(
      -static_cast<int>(32 * scale), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  const auto old_font = SelectObject(dc, font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, ink);
  RECT title = {0, top + static_cast<LONG>(152 * scale), bounds.right,
                top + group_height};
  DrawTextW(dc, L"Shiori", -1, &title, DT_CENTER | DT_SINGLELINE | DT_VCENTER);
  SelectObject(dc, old_font);
  DeleteObject(font);
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
