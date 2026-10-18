#pragma once
#include <windows.h>
#include <filesystem>
#include <fstream>
#include <string>

namespace shiori::update {
inline constexpr char kInstallationId[] = "{317FAF26-80D6-47B9-A5EF-14B3829374B3}\n";
inline constexpr wchar_t kUninstallKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"
    L"{317FAF26-80D6-47B9-A5EF-14B3829374B3}_is1";

// Both a local marker and this user's Inno registration must name this exact
// directory. A different portable copy never inherits the installed copy's mode.
inline std::string InstallationMode(const std::filesystem::path& directory) {
  namespace fs = std::filesystem;
  const auto marker = directory / L".shiori-install";
  const DWORD attributes = GetFileAttributesW(marker.c_str());
  const bool present = attributes != INVALID_FILE_ATTRIBUTES;
  wchar_t location[32768]{};
  DWORD bytes = sizeof(location);
  const bool registered = RegGetValueW(HKEY_CURRENT_USER, kUninstallKey, L"InstallLocation",
      RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, location, &bytes) == ERROR_SUCCESS;
  std::error_code error;
  const auto current = fs::weakly_canonical(directory, error);
  if (error) return "invalid";
  bool matches = false;
  if (registered) {
    const auto target = fs::weakly_canonical(fs::path(location), error);
    matches = !error && CompareStringOrdinal(current.c_str(), -1, target.c_str(), -1, TRUE) == CSTR_EQUAL;
  }
  if (!present) return matches ? "invalid" : "portable";
  if ((attributes & (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY)) || !matches) return "invalid";
  if (fs::file_size(marker, error) != sizeof(kInstallationId) - 1 || error) return "invalid";
  std::ifstream input(marker, std::ios::binary);
  const std::string text((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
  return text == kInstallationId ? "setup" : "invalid";
}
}  // namespace shiori::update
