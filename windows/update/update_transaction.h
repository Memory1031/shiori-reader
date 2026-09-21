#pragma once

#include <windows.h>

#include <filesystem>
#include <functional>
#include <string>
#include <vector>

namespace shiori::update {
namespace fs = std::filesystem;

struct FileEntry {
  std::string path;
  std::string sha256;
};

// Prepared, authenticated file lists belong to the caller. This engine neither
// downloads nor trusts an unsigned task as release authorization. The standalone
// probe uses synthetic lists; release-manifest binding precedes app integration.
struct PreparedUpdate {
  fs::path install;
  fs::path workspace;  // A dedicated sibling of install, on the same local volume.
  std::vector<FileEntry> current;
  std::vector<FileEntry> next;  // Expanded, verified files under workspace/payload.
};

enum class Status { installed, rolled_back, recovery_required, launch_failed };
struct Result {
  Status status;
  std::string detail;
};

// Optional synchronous progress observer. Fixtures implement crash/lock barriers
// outside the engine; no failure-injection switches ship in application code.
using Progress = std::function<void(const std::string&)>;

std::string FileSha256(const fs::path& path);
void SaveTask(const fs::path& path, const PreparedUpdate& task);
PreparedUpdate ReadTask(const fs::path& path);

// parent is an already-open SYNCHRONIZE process handle, avoiding PID reuse.
// The caller retains ownership. Timeout fails before changing installed files.
// Persists the publish boundary before exposing the new executable: recovery
// never rolls back after the app may have started data migrations. Restart
// failure retains the coherent new version.
Result Apply(const PreparedUpdate& task, HANDLE parent, DWORD timeout_ms,
             const Progress& progress = {});
Result Recover(const fs::path& workspace, const Progress& progress = {});
}  // namespace shiori::update
