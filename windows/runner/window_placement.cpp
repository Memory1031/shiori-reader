#include "window_placement.h"

#include <algorithm>
#include <cwchar>

namespace shiori::window {
namespace {
bool ValidRect(RECT rect) {
  // Bound arithmetic before subtracting or scaling untrusted preference data.
  constexpr LONG limit = 1000000;
  return rect.left >= -limit && rect.top >= -limit && rect.right <= limit &&
         rect.bottom <= limit && rect.right > rect.left && rect.bottom > rect.top;
}

struct MonitorSearch {
  const wchar_t* device;
  HMONITOR found = nullptr;
};
BOOL CALLBACK FindMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto* search = reinterpret_cast<MonitorSearch*>(data);
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (GetMonitorInfoW(monitor, &info) && std::wcscmp(info.szDevice, search->device) == 0) {
    search->found = monitor;
    return FALSE;
  }
  return TRUE;
}
}  // namespace

bool ValidPlacement(const Placement& placement) {
  return placement.version == 1 && ValidRect(placement.bounds) &&
         ValidRect(placement.work) && placement.dpi >= 48 && placement.dpi <= 768 &&
         placement.maximized <= 1 && placement.monitor[CCHDEVICENAME - 1] == L'\0';
}

RECT FitBounds(RECT bounds, RECT work, SIZE minimum) {
  const LONG width = std::min(std::max(bounds.right - bounds.left, minimum.cx),
                              work.right - work.left);
  const LONG height = std::min(std::max(bounds.bottom - bounds.top, minimum.cy),
                               work.bottom - work.top);
  const LONG left = std::clamp(bounds.left, work.left, work.right - width);
  const LONG top = std::clamp(bounds.top, work.top, work.bottom - height);
  return RECT{left, top, left + width, top + height};
}

RECT RestoreBounds(const Placement& placement, RECT work, UINT dpi, SIZE minimum) {
  const LONG width = MulDiv(placement.bounds.right - placement.bounds.left,
                           dpi, placement.dpi);
  const LONG height = MulDiv(placement.bounds.bottom - placement.bounds.top,
                            dpi, placement.dpi);
  const LONG left = work.left + MulDiv(placement.bounds.left - placement.work.left,
                                       dpi, placement.dpi);
  const LONG top = work.top + MulDiv(placement.bounds.top - placement.work.top,
                                     dpi, placement.dpi);
  return FitBounds(RECT{left, top, left + width, top + height}, work, minimum);
}

std::optional<Placement> LoadPlacement(const std::wstring& key) {
  if (key.empty()) return std::nullopt;
  Placement placement{};
  DWORD size = sizeof(placement);
  if (RegGetValueW(HKEY_CURRENT_USER, key.c_str(), L"Placement", RRF_RT_REG_BINARY,
                   nullptr, &placement, &size) != ERROR_SUCCESS ||
      size != sizeof(placement) || !ValidPlacement(placement)) return std::nullopt;
  return placement;
}

void SavePlacement(const std::wstring& key, const Placement& placement) {
  if (key.empty() || !ValidPlacement(placement)) return;
  // A window preference failure must not interfere with saving reader progress.
  RegSetKeyValueW(HKEY_CURRENT_USER, key.c_str(), L"Placement", REG_BINARY,
                  &placement, sizeof(placement));
}

HMONITOR PlacementMonitor(const Placement& placement) {
  MonitorSearch search{placement.monitor};
  EnumDisplayMonitors(nullptr, nullptr, FindMonitor, reinterpret_cast<LPARAM>(&search));
  if (search.found) return search.found;
  RECT bounds = placement.bounds;
  return MonitorFromRect(&bounds, MONITOR_DEFAULTTONEAREST);
}
}  // namespace shiori::window
