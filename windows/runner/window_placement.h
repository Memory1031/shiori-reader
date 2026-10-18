#ifndef RUNNER_WINDOW_PLACEMENT_H_
#define RUNNER_WINDOW_PLACEMENT_H_

#include <windows.h>

#include <optional>
#include <string>

namespace shiori::window {

// Screen coordinates, with the source work area and DPI for monitor changes.
struct Placement {
  DWORD version = 1;
  RECT bounds{};
  RECT work{};
  UINT dpi = 96;
  DWORD maximized = 0;
  wchar_t monitor[CCHDEVICENAME]{};
};

bool ValidPlacement(const Placement& placement);
RECT FitBounds(RECT bounds, RECT work, SIZE minimum);
RECT RestoreBounds(const Placement& placement, RECT work, UINT dpi, SIZE minimum);
std::optional<Placement> LoadPlacement(const std::wstring& key);
void SavePlacement(const std::wstring& key, const Placement& placement);
HMONITOR PlacementMonitor(const Placement& placement);

}  // namespace shiori::window

#endif  // RUNNER_WINDOW_PLACEMENT_H_
