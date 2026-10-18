#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace shiori::update {
struct ReleaseFile {
  std::string path;  // UTF-8, '/'-separated, relative to the installation.
  uint64_t size;
  std::string sha256;
};

struct WindowsRelease {
  std::string tag;
  int64_t build;
  std::vector<ReleaseFile> files;
  std::string name;
  uint64_t size;
  std::string sha256;
};

// Reads one Windows variant from the unified manifest whose signature the caller
// has already verified. Strict JSON: duplicate keys, non-ASCII bytes, fractions
// and unexpected protocol values are rejected. Throws std::runtime_error.
WindowsRelease ReadWindowsRelease(const std::string& manifest,
                                 const std::string& variant = "windows-x64-portable");
}  // namespace shiori::update
