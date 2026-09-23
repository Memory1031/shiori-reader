#include "update_transaction.h"

#include <bcrypt.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cwctype>
#include <fstream>
#include <map>
#include <set>
#include <stdexcept>
#include <utility>

namespace shiori::update {
namespace {
constexpr uint64_t kMaxBytes = 2ull * 1024 * 1024 * 1024;
constexpr size_t kMaxFiles = 10000;
constexpr wchar_t kExe[] = L"shiori.exe";

class Handle {
 public:
  explicit Handle(HANDLE value = INVALID_HANDLE_VALUE) : value_(value) {}
  ~Handle() { if (value_ && value_ != INVALID_HANDLE_VALUE) CloseHandle(value_); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  HANDLE get() const { return value_; }
 private:
  HANDLE value_;
};

void Require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

bool Exists(const fs::path& path) {
  const auto attr = GetFileAttributesW(path.c_str());
  if (attr != INVALID_FILE_ATTRIBUTES) return true;
  const auto error = GetLastError();
  Require(error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND,
          "Cannot inspect path");
  return false;
}

void SafeAncestors(const fs::path& path) {
  for (auto current = path; !current.empty();) {
    if (Exists(current)) {
      Require(!(GetFileAttributesW(current.c_str()) & FILE_ATTRIBUTE_REPARSE_POINT),
              "Reparse points are not supported");
    }
    const auto parent = current.parent_path();
    if (parent == current) break;
    current = parent;
  }
}

fs::path Absolute(const fs::path& path) {
  Require(path.is_absolute() && path.root_name().wstring().size() == 2,
          "Expected absolute local drive path");
  SafeAncestors(path);
  return fs::weakly_canonical(path);
}

std::wstring Fold(const fs::path& path) {
  const auto input = path.wstring();
  const auto size = LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE,
                                input.data(), static_cast<int>(input.size()),
                                nullptr, 0, nullptr, nullptr, 0);
  Require(size > 0, "Cannot normalize path identity");
  std::wstring output(size, L'\0');
  Require(LCMapStringEx(LOCALE_NAME_INVARIANT, LCMAP_LOWERCASE,
                       input.data(), static_cast<int>(input.size()), output.data(),
                       size, nullptr, nullptr, 0) == size, "Cannot normalize path identity");
  return output;
}

std::string Lower(std::string text) {
  std::transform(text.begin(), text.end(), text.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  return text;
}

void SafeRelative(const std::string& name) {
  Require(!name.empty() && name.size() <= 1024 && name.back() != '/',
          "Invalid relative file path");
  for (const auto c : name) {
    Require(static_cast<unsigned char>(c) >= 32 &&
                std::string("\\:\"<>|?*").find(c) == std::string::npos,
            "Invalid file path character");
  }
  const auto path = fs::u8path(name);
  Require(!path.is_absolute() && !path.has_root_path(), "Absolute file path");
  for (const auto& part : path) {
    const auto component = Lower(part.u8string());
    Require(!component.empty() && component != "." && component != ".." &&
                component.back() != '.' && component.back() != ' ',
            "Unsafe file path component");
    const auto stem = component.substr(0, component.find('.'));
    Require(stem != "con" && stem != "prn" && stem != "aux" && stem != "nul" &&
                !(stem.size() == 4 && (stem.substr(0, 3) == "com" ||
                                      stem.substr(0, 3) == "lpt") &&
                  stem[3] >= '1' && stem[3] <= '9'), "Reserved device path");
  }
  Require(name.find("//") == std::string::npos, "Empty path component");
}

using Entries = std::map<std::wstring, FileEntry>;
Entries Index(const std::vector<FileEntry>& files) {
  Require(!files.empty() && files.size() <= kMaxFiles, "Invalid file count");
  Entries result;
  for (const auto& file : files) {
    SafeRelative(file.path);
    Require(file.sha256.size() == 64 &&
                file.sha256.find_first_not_of("0123456789abcdef") == std::string::npos,
            "Invalid SHA-256");
    Require(result.emplace(Fold(fs::u8path(file.path)), file).second,
            "Duplicate file path");
  }
  Require(result.count(kExe) == 1, "Missing application executable");
  for (const auto& [name, file] : result) {
    (void)file;
    for (auto parent = fs::path(name).parent_path(); !parent.empty(); parent = parent.parent_path()) {
      Require(!result.count(Fold(parent)), "File/directory collision");
    }
  }
  return result;
}

PreparedUpdate ValidateLayout(const PreparedUpdate& input) {
  auto task = input;
  task.install = Absolute(task.install);
  task.workspace = Absolute(task.workspace);
  Require(Fold(task.install) != Fold(task.workspace) &&
              Fold(task.install.parent_path()) == Fold(task.workspace.parent_path()) &&
              !task.install.filename().empty(), "Workspace must be a separate sibling directory");
  Require(fs::is_directory(task.install) && fs::is_directory(task.workspace),
          "Missing installation or workspace");
  Require(GetDriveTypeW(task.install.root_path().c_str()) == DRIVE_FIXED,
          "Only local fixed volumes are supported");
  auto all = Index(task.current);
  const auto next = Index(task.next);
  all.insert(next.begin(), next.end());
  // Rollback restores files, not directory role changes. Reject both directions
  // before locks, backups, or mutations to the installation.
  for (const auto& [name, file] : all) {
    (void)file;
    for (auto parent = fs::path(name).parent_path(); !parent.empty(); parent = parent.parent_path()) {
      Require(!all.count(Fold(parent)), "Cross-version file/directory collision");
    }
  }
  return task;
}

void ProgressAt(const Progress& observer, const std::string& point) {
  if (observer) observer(point);
}

std::string Hex(const unsigned char* bytes, size_t length) {
  constexpr char digits[] = "0123456789abcdef";
  std::string result;
  for (size_t i = 0; i < length; ++i) {
    result += digits[bytes[i] >> 4];
    result += digits[bytes[i] & 15];
  }
  return result;
}

std::wstring MutexName(const fs::path& install) {
  const auto name = Fold(install);
  std::array<unsigned char, 32> digest{};
  Require(BCryptHash(BCRYPT_SHA256_ALG_HANDLE, nullptr, 0,
                    reinterpret_cast<PUCHAR>(const_cast<wchar_t*>(name.data())),
                    static_cast<ULONG>(name.size() * sizeof(wchar_t)),
                    digest.data(), static_cast<ULONG>(digest.size())) >= 0,
          "Cannot hash installation identity");
  const auto hex = Hex(digest.data(), digest.size());
  return L"Local\\Shiori.Update." + std::wstring(hex.begin(), hex.end());
}

class Locks {
 public:
  explicit Locks(const PreparedUpdate& task)
      : mutex_(CreateMutexW(nullptr, FALSE, MutexName(task.install).c_str())),
        workspace_(OpenWorkspace(task.workspace)) {
    Require(mutex_.get() != nullptr, "Cannot create update mutex");
    const auto wait = WaitForSingleObject(mutex_.get(), 0);
    Require(wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED, "Another update is active");
    owned_ = true;
    if (workspace_.get() == INVALID_HANDLE_VALUE) {
      ReleaseMutex(mutex_.get());
      owned_ = false;
      throw std::runtime_error("Workspace is locked");
    }
  }
  ~Locks() { if (owned_) ReleaseMutex(mutex_.get()); }
 private:
  static HANDLE OpenWorkspace(const fs::path& workspace) {
    const auto path = workspace / L"transaction.lock";
    SafeAncestors(path);
    return CreateFileW(path.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                       OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  }
  Handle mutex_;
  Handle workspace_;
  bool owned_ = false;
};

void Flush(const fs::path& path) {
  Handle file(CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                          OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  Require(file.get() != INVALID_HANDLE_VALUE && FlushFileBuffers(file.get()),
          "Cannot flush transaction file");
}

void Move(const fs::path& from, const fs::path& to, bool replace = false) {
  SafeAncestors(from);
  SafeAncestors(to);
  Require(MoveFileExW(from.c_str(), to.c_str(), MOVEFILE_WRITE_THROUGH |
                          (replace ? MOVEFILE_REPLACE_EXISTING : 0)) != 0,
          "Cannot move file (possibly in use)");
}

void Copy(const fs::path& from, const fs::path& to) {
  SafeAncestors(from);
  SafeAncestors(to);
  fs::create_directories(to.parent_path());
  Require(CopyFileW(from.c_str(), to.c_str(), TRUE) != 0, "Cannot copy file");
  Flush(to);
}

// A replacement is first flushed in the workspace and then atomically renamed.
void Replace(const fs::path& from, const fs::path& to, const fs::path& workspace,
             const std::string& expected_hash) {
  const auto temp = workspace / L"replacement.tmp";
  SafeAncestors(temp);
  if (Exists(temp)) Require(DeleteFileW(temp.c_str()) != 0, "Cannot remove staging file");
  Copy(from, temp);
  Require(FileSha256(temp) == expected_hash, "Replacement file hash mismatch");
  SafeAncestors(to);
  fs::create_directories(to.parent_path());
  Move(temp, to, true);
}

void WriteState(const fs::path& workspace, const char* state) {
  const auto temp = workspace / L"state.tmp";
  SafeAncestors(temp);
  if (Exists(temp)) FileSha256(temp);  // Reject hard-linked control files.
  std::ofstream output(temp, std::ios::binary | std::ios::trunc);
  output << state;
  output.close();
  Require(!output.fail(), "Cannot write transaction state");
  Flush(temp);
  Move(temp, workspace / L"state", true);
}

std::string ReadState(const fs::path& workspace) {
  const auto path = workspace / L"state";
  SafeAncestors(path);
  if (!Exists(path)) return "unprepared";
  Require(fs::file_size(path) <= 64, "Invalid transaction state");
  std::ifstream input(path, std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(input), {});
}

void VerifyFiles(const fs::path& root, const std::vector<FileEntry>& files) {
  uint64_t total = 0;
  for (const auto& file : files) {
    const auto path = root / fs::u8path(file.path);
    Require(FileSha256(path) == file.sha256, "Managed file hash mismatch");
    total += fs::file_size(path);
    Require(total <= kMaxBytes, "Package exceeds size limit");
  }
}

void Gate(const PreparedUpdate& task) {
  const auto exe = task.install / kExe;
  if (Exists(exe)) Move(exe, task.workspace / L"gated.exe", true);
}

void Rollback(const PreparedUpdate& task, const Progress& progress) {
  const auto old = Index(task.current);
  const auto next = Index(task.next);
  VerifyFiles(task.workspace / L"backup", task.current);
  // Re-entry is allowed after any individual replacement. Unknown changes are
  // not overwritten, even during recovery.
  auto all = old;
  all.insert(next.begin(), next.end());
  for (const auto& [name, file] : all) {
    const auto path = task.install / fs::u8path(file.path);
    if (!Exists(path)) continue;
    const auto digest = FileSha256(path);
    Require((old.count(name) && digest == old.at(name).sha256) ||
                (next.count(name) && digest == next.at(name).sha256),
            "Installed file changed outside transaction");
  }
  Gate(task);
  WriteState(task.workspace, "rolling_back");
  ProgressAt(progress, "rollback_gated");
  size_t number = 0;
  for (const auto& [name, file] : all) {
    if (name == kExe) continue;
    const auto destination = task.install / fs::u8path(file.path);
    if (old.count(name)) {
      // Unchanged files stay in place, so an external reader of one (scanner,
      // preview) cannot block restoring the rest.
      if (Exists(destination) && FileSha256(destination) == old.at(name).sha256) {
        ProgressAt(progress, "rollback_file:" + std::to_string(++number));
        continue;
      }
      Replace(task.workspace / L"backup" / fs::u8path(old.at(name).path),
              destination, task.workspace, old.at(name).sha256);
    } else if (Exists(destination)) {
      SafeAncestors(destination);
      Require(DeleteFileW(destination.c_str()) != 0, "Cannot remove new file during rollback");
    }
    ProgressAt(progress, "rollback_file:" + std::to_string(++number));
  }
  Replace(task.workspace / L"backup" / kExe, task.install / kExe, task.workspace,
          old.at(kExe).sha256);
  VerifyFiles(task.install, task.current);
  WriteState(task.workspace, "rolled_back");
}

void FinishPublishing(const PreparedUpdate& task) {
  const auto next = Index(task.next);
  // Once publishing is durable the new executable may have been visible to a
  // manual launch. Recovery must finish forward, never roll back migrated data.
  std::vector<FileEntry> content;
  for (const auto& file : task.next) {
    if (Fold(fs::u8path(file.path)) != kExe) content.push_back(file);
  }
  VerifyFiles(task.install, content);
  const auto executable = task.install / kExe;
  if (Exists(executable)) {
    Require(FileSha256(executable) == next.at(kExe).sha256,
            "Unexpected executable after publish boundary");
  } else {
    Replace(task.workspace / L"next-executable", executable, task.workspace,
            next.at(kExe).sha256);
  }
  VerifyFiles(task.install, task.next);
  WriteState(task.workspace, "committed");
}

bool Launch(const fs::path& install) {
  const auto executable = install / kExe;
  auto command = L"\"" + executable.wstring() + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  DWORD previous_mode = 0;
  const bool changed_mode = SetThreadErrorMode(SEM_FAILCRITICALERRORS |
      SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX, &previous_mode) != 0;
  const bool started = CreateProcessW(executable.c_str(), command.data(), nullptr,
      nullptr, FALSE, CREATE_NO_WINDOW, nullptr, install.c_str(), &startup, &process) != 0;
  if (changed_mode) SetThreadErrorMode(previous_mode, nullptr);
  if (!started) return false;
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return true;
}

// Checks that precede every mutation of the installation or its backups.
void Preflight(const PreparedUpdate& task) {
  VerifyFiles(task.install, task.current);
  VerifyFiles(task.workspace / L"payload", task.next);
  const auto old = Index(task.current);
  const auto next = Index(task.next);
  uint64_t bytes = 0;
  for (const auto& file : task.current) bytes += fs::file_size(task.install / fs::u8path(file.path));
  for (const auto& file : task.next) bytes += fs::file_size(task.workspace / L"payload" / fs::u8path(file.path));
  ULARGE_INTEGER free{};
  Require(GetDiskFreeSpaceExW(task.workspace.c_str(), &free, nullptr, nullptr) &&
              free.QuadPart > bytes + 1024 * 1024, "Insufficient free space");
  for (const auto& [name, file] : next) {
    const auto target = task.install / fs::u8path(file.path);
    SafeAncestors(target);
    Require(old.count(name) || !Exists(target), "New file would overwrite unmanaged data");
  }
}

void PutString(std::ostream& out, const std::string& value) {
  Require(value.size() <= 32768, "Task field too large");
  const auto size = static_cast<uint32_t>(value.size());
  out.write(reinterpret_cast<const char*>(&size), sizeof(size));
  out.write(value.data(), size);
}

std::string GetString(std::istream& input) {
  uint32_t size = 0;
  input.read(reinterpret_cast<char*>(&size), sizeof(size));
  Require(input.good() && size <= 32768, "Invalid task field");
  std::string value(size, '\0');
  input.read(value.data(), size);
  Require(input.good() && value.find('\0') == std::string::npos, "Truncated task field");
  return value;
}
}  // namespace

std::wstring InstallationMutexName(const fs::path& install) {
  return MutexName(Absolute(install));
}

bool LaunchApplication(const fs::path& install) { return Launch(Absolute(install)); }

void Check(const PreparedUpdate& task) { Preflight(ValidateLayout(task)); }

void ValidateRelativePath(const std::string& path) { SafeRelative(path); }

std::string FileSha256(const fs::path& path) {
  SafeAncestors(path);
  Handle file(CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                         OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nullptr));
  Require(file.get() != INVALID_HANDLE_VALUE, "Cannot read managed file");
  BY_HANDLE_FILE_INFORMATION info{};
  Require(GetFileInformationByHandle(file.get(), &info) && info.nNumberOfLinks == 1 &&
              !(info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)),
          "Expected ordinary file with one link");
  const uint64_t size = (static_cast<uint64_t>(info.nFileSizeHigh) << 32) | info.nFileSizeLow;
  Require(size <= kMaxBytes, "Managed file too large");
  BCRYPT_HASH_HANDLE hash = nullptr;
  Require(BCryptCreateHash(BCRYPT_SHA256_ALG_HANDLE, &hash, nullptr, 0,
                           nullptr, 0, 0) >= 0, "Cannot create SHA-256");
  try {
    std::array<unsigned char, 65536> buffer{};
    DWORD count = 0;
    do {
      Require(ReadFile(file.get(), buffer.data(), static_cast<DWORD>(buffer.size()),
                       &count, nullptr) != 0, "Cannot read hash input");
      Require(BCryptHashData(hash, buffer.data(), count, 0) >= 0, "Cannot hash file");
    } while (count);
    std::array<unsigned char, 32> digest{};
    Require(BCryptFinishHash(hash, digest.data(), static_cast<ULONG>(digest.size()), 0) >= 0,
            "Cannot finish SHA-256");
    BCryptDestroyHash(hash);
    return Hex(digest.data(), digest.size());
  } catch (...) {
    BCryptDestroyHash(hash);
    throw;
  }
}

// Published atomically: an interrupted write leaves only plan.tmp, which is
// not a transaction, so the untouched installation stays retryable.
void SaveTask(const fs::path& path, const PreparedUpdate& task, const Progress& progress) {
  const auto temp = fs::path(path).replace_extension(L".tmp");
  SafeAncestors(path);
  SafeAncestors(temp);
  Require(!Exists(path), "Task already exists");
  if (Exists(temp)) Require(DeleteFileW(temp.c_str()) != 0, "Cannot remove stale task");
  std::ofstream output(temp, std::ios::binary | std::ios::trunc);
  PutString(output, "ShioriUpdateTransaction/1");
  PutString(output, task.install.u8string());
  PutString(output, task.workspace.u8string());
  for (const auto* files : {&task.current, &task.next}) {
    Require(files->size() <= kMaxFiles, "Task file count too large");
    const auto size = static_cast<uint32_t>(files->size());
    output.write(reinterpret_cast<const char*>(&size), sizeof(size));
    for (const auto& file : *files) {
      PutString(output, file.path);
      PutString(output, file.sha256);
    }
  }
  output.close();
  Require(!output.fail(), "Cannot write task");
  Flush(temp);
  ProgressAt(progress, "planning");
  Move(temp, path);
}

PreparedUpdate ReadTask(const fs::path& path) {
  SafeAncestors(path);
  Require(fs::file_size(path) <= 24 * 1024 * 1024, "Task too large");
  std::ifstream input(path, std::ios::binary);
  Require(GetString(input) == "ShioriUpdateTransaction/1", "Unknown task protocol");
  PreparedUpdate task;
  task.install = fs::u8path(GetString(input));
  task.workspace = fs::u8path(GetString(input));
  for (auto* files : {&task.current, &task.next}) {
    uint32_t count = 0;
    input.read(reinterpret_cast<char*>(&count), sizeof(count));
    Require(input.good() && count <= kMaxFiles, "Invalid task file count");
    for (uint32_t i = 0; i < count; ++i) {
      auto name = GetString(input);
      auto digest = GetString(input);
      files->push_back({std::move(name), std::move(digest)});
    }
  }
  Require(input.peek() == std::char_traits<char>::eof(), "Unexpected task data");
  return ValidateLayout(task);
}

Result Apply(const PreparedUpdate& input, HANDLE parent, DWORD timeout_ms,
             const Progress& progress) {
  const auto task = ValidateLayout(input);
  Locks locks(task);
  Require(ReadState(task.workspace) == "unprepared" &&
              !Exists(task.workspace / L"plan.bin") && !Exists(task.workspace / L"backup"),
          "Transaction already exists; recover instead");
  if (parent) {
    ProgressAt(progress, "waiting");
    Require(WaitForSingleObject(parent, timeout_ms) == WAIT_OBJECT_0,
            "Application exit timed out");
  }
  Preflight(task);
  const auto old = Index(task.current);
  const auto next = Index(task.next);
  SaveTask(task.workspace / L"plan.bin", task, progress);
  ProgressAt(progress, "planned");
  for (const auto& file : task.current) {
    Copy(task.install / fs::u8path(file.path),
         task.workspace / L"backup" / fs::u8path(file.path));
  }
  VerifyFiles(task.workspace / L"backup", task.current);
  WriteState(task.workspace, "prepared");
  ProgressAt(progress, "prepared");
  try {
    WriteState(task.workspace, "applying");
    Gate(task);
    ProgressAt(progress, "gated");
    for (const auto& [name, file] : old) {
      if (name != kExe && !next.count(name)) {
        const auto target = task.install / fs::u8path(file.path);
        SafeAncestors(target);
        Require(DeleteFileW(target.c_str()) != 0, "Cannot remove obsolete program file");
      }
    }
    ProgressAt(progress, "removed");
    size_t number = 0;
    for (const auto& [name, file] : next) {
      if (name == kExe) continue;
      Replace(task.workspace / L"payload" / fs::u8path(file.path),
              task.install / fs::u8path(file.path), task.workspace, file.sha256);
      ProgressAt(progress, "file_applied:" + std::to_string(++number));
    }
    std::vector<FileEntry> content;
    for (const auto& file : task.next) {
      if (Fold(fs::u8path(file.path)) != kExe) content.push_back(file);
    }
    VerifyFiles(task.install, content);
    Copy(task.workspace / L"payload" / kExe, task.workspace / L"next-executable");
    Require(FileSha256(task.workspace / L"next-executable") == next.at(kExe).sha256,
            "Executable changed after preparation");
    // This boundary must be durable BEFORE restoring a runnable entry point.
    WriteState(task.workspace, "publishing");
    ProgressAt(progress, "publishing");
    Replace(task.workspace / L"next-executable", task.install / kExe, task.workspace,
            next.at(kExe).sha256);
    ProgressAt(progress, "installed");
    FinishPublishing(task);
  } catch (const std::exception& error) {
    const std::string reason = error.what();
    const auto state = ReadState(task.workspace);
    if (state == "publishing" || state == "committed") {
      return {Status::recovery_required, reason};
    }
    try {
      Rollback(task, progress);
      return {Status::rolled_back, reason};
    } catch (const std::exception& recovery) {
      return {Status::recovery_required, reason + "; " + recovery.what()};
    }
  }
  ProgressAt(progress, "committed");
  if (!Launch(task.install)) return {Status::launch_failed, "New version installed; restart failed"};
  return {Status::installed, "New version installed and process created"};
}

Result Recover(const fs::path& workspace, const Progress& progress) {
  const auto task = ReadTask(workspace / L"plan.bin");
  Require(Fold(task.workspace) == Fold(Absolute(workspace)), "Recovery workspace mismatch");
  Locks locks(task);
  const auto state = ReadState(task.workspace);
  if (state == "publishing") {
    try {
      FinishPublishing(task);
      return {Status::installed, "Publication completed; no automatic relaunch"};
    } catch (const std::exception& error) {
      return {Status::recovery_required, error.what()};
    }
  }
  if (state == "committed") {
    VerifyFiles(task.install, task.next);
    return {Status::installed, "Already committed; no rollback or automatic relaunch"};
  }
  if (state == "unprepared" || state == "prepared" || state == "rolled_back") {
    VerifyFiles(task.install, task.current);
    return {Status::rolled_back, "Original installation intact"};
  }
  Require(state == "applying" || state == "rolling_back", "Unknown transaction state");
  try {
    Rollback(task, progress);
    return {Status::rolled_back, "Original installation restored"};
  } catch (const std::exception& error) {
    return {Status::recovery_required, error.what()};
  }
}
}  // namespace shiori::update
