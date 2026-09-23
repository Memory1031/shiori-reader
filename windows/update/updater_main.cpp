// Standalone Windows updater. Trust comes from the key and build embedded at
// compile time from assets/release/build-info.json, never from the workspace.
//
//   check <workspace> <install> <app pid>      Validate before the app exits.
//   apply <workspace> <install> <process handle> Wait for the app, then update.
//   recover <workspace> <install>             Report or finish a transaction.
//   (no arguments)                            Recover the workspace it runs in.
#include <windows.h>
#include <shellapi.h>
#include <tlhelp32.h>

#include <cstdint>
#include <fstream>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

#include "manifest_signature.h"
#include "release_manifest.h"
#include "update_transaction.h"

#ifndef SHIORI_UPDATE_MODULUS
#error SHIORI_UPDATE_MODULUS must be defined (empty for development builds)
#endif
#ifndef SHIORI_UPDATE_BUILD
#error SHIORI_UPDATE_BUILD must be defined
#endif

namespace {
namespace fs = std::filesystem;
using namespace shiori::update;

// Stable process protocol shared with the Dart WindowsUpdateInstaller.
enum Code : int {
  kInstalled = 0,
  kRolledBack = 1,
  kRecoveryRequired = 2,
  kLaunchFailed = 3,
  kError = 10,
  kBusy = 20,
  kNone = 21,
  kFailed = 22,
  kTimeout = 23,
  kInstances = 30,
  kStorage = 31,
  kInvalid = 32,
  kUnsupported = 33,
};

constexpr DWORD kExitTimeoutMs = 120000;
constexpr int kRecoverRetries = 3;
constexpr DWORD kRecoverDelayMs = 2000;
constexpr uintmax_t kMaxManifest = 4 * 1024 * 1024;
constexpr size_t kSignatureBytes = 384;
constexpr uintmax_t kMaxList = 4 * 1024 * 1024;
const char* const kRequired[] = {"shiori.exe", "shiori-updater.exe",
                                 "program-files.txt", "data/app.so"};

struct Failure {
  int code;
  std::string message;
};

class Handle {
 public:
  explicit Handle(HANDLE value = nullptr) : value_(value) {}
  ~Handle() { if (value_ && value_ != INVALID_HANDLE_VALUE) CloseHandle(value_); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  HANDLE get() const { return value_; }
 private:
  HANDLE value_;
};

fs::path workspace_for_log;

void Log(const std::string& message) {
  if (workspace_for_log.empty()) return;
  SYSTEMTIME now{};
  GetLocalTime(&now);
  char stamp[32];
  wsprintfA(stamp, "%04u-%02u-%02u %02u:%02u:%02u ", now.wYear, now.wMonth, now.wDay,
            now.wHour, now.wMinute, now.wSecond);
  std::ofstream log(workspace_for_log / L"updater.log", std::ios::binary | std::ios::app);
  log << stamp << message << '\n';
}

bool Quiet() {
  wchar_t value[4] = {};
  return GetEnvironmentVariableW(L"SHIORI_UPDATER_QUIET", value, 4) == 1 && value[0] == L'1';
}

void Notify(const wchar_t* message) {
  if (!Quiet()) {
    MessageBoxW(nullptr, message, L"Shiori", MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
  }
}

constexpr wchar_t kTimeoutMessage[] =
    L"Shiori 未能在规定时间内退出，更新已取消，程序文件没有改动。\n\n"
    L"Shiori did not exit in time. The update was cancelled and no program files were changed.";
constexpr wchar_t kRecoveryMessage[] =
    L"Shiori 更新未能完成，程序文件可能不完整。请从发布页下载完整的 Windows ZIP 重新解压覆盖。"
    L"书架和阅读数据保存在用户数据目录，不受影响。\n\n"
    L"The Shiori update could not be completed and program files may be incomplete. Download "
    L"the full Windows ZIP from the release page and extract it again. Your library and reading "
    L"data are stored separately and are not affected.";
constexpr wchar_t kLaunchMessage[] =
    L"未能重新启动 Shiori，请手动启动。\n\nShiori could not be restarted. Please start it manually.";

void WriteResult(const fs::path& workspace, int code, const std::string& detail) {
  Log("result " + std::to_string(code) + ": " + detail);
  const auto temporary = workspace / L"result.tmp";
  {
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    output << code << '\n' << detail << '\n';
    if (!output.good()) return;
  }
  MoveFileExW(temporary.c_str(), (workspace / L"result").c_str(),
              MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
}

int ReadResult(const fs::path& workspace) {
  std::ifstream input(workspace / L"result", std::ios::binary);
  int code = kNone;
  if (!(input >> code)) return kNone;
  return code;
}

std::string ReadBytes(const fs::path& path, uintmax_t limit, int code) {
  std::error_code error;
  const auto size = fs::file_size(path, error);
  if (error || size == 0 || size > limit) throw Failure{code, "Missing or oversized " + path.filename().u8string()};
  std::ifstream input(path, std::ios::binary);
  std::string data(static_cast<size_t>(size), '\0');
  input.read(data.data(), static_cast<std::streamsize>(size));
  if (!input.good() || input.peek() != std::char_traits<char>::eof()) {
    throw Failure{code, "Cannot read " + path.filename().u8string()};
  }
  return data;
}

std::vector<uint8_t> Modulus() {
  const std::string hex = SHIORI_UPDATE_MODULUS;
  std::vector<uint8_t> bytes;
  for (size_t i = 0; i + 1 < hex.size(); i += 2) {
    bytes.push_back(static_cast<uint8_t>(std::stoul(hex.substr(i, 2), nullptr, 16)));
  }
  return bytes;
}

bool Same(const std::wstring& a, const std::wstring& b) {
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL;
}

// Whole-lifetime ownership of the installation mutex that Apply/Recover also
// take (recursively on this thread), so a second updater reports busy.
class InstallLock {
 public:
  explicit InstallLock(const fs::path& install)
      : mutex_(CreateMutexW(nullptr, FALSE, InstallationMutexName(install).c_str())) {
    if (!mutex_.get()) throw Failure{kError, "Cannot create update mutex"};
    const auto wait = WaitForSingleObject(mutex_.get(), 0);
    if (wait != WAIT_OBJECT_0 && wait != WAIT_ABANDONED) throw Failure{kBusy, "Another updater is active"};
  }
  ~InstallLock() { ReleaseMutex(mutex_.get()); }
 private:
  Handle mutex_;
};

// The workspace is always <install>.update beside the installation.
void CheckPaths(const fs::path& workspace, const fs::path& install) {
  if (!workspace.is_absolute() || !install.is_absolute() || install.filename().empty() ||
      !Same(workspace.parent_path().wstring(), install.parent_path().wstring()) ||
      !Same(workspace.filename().wstring(), install.filename().wstring() + L".update")) {
    throw Failure{kError, "Unexpected workspace location"};
  }
}

// program-files.txt: UTF-8 relative paths, one per LF-terminated line.
std::set<std::string> ReadList(const fs::path& path, int code) {
  const auto data = ReadBytes(path, kMaxList, code);
  if (data.back() != '\n') throw Failure{code, "Malformed program file list"};
  std::set<std::string> names;
  size_t start = 0;
  for (auto end = data.find('\n'); end != std::string::npos; end = data.find('\n', start)) {
    auto name = data.substr(start, end - start);
    start = end + 1;
    try {
      ValidateRelativePath(name);
    } catch (const std::exception&) {
      throw Failure{code, "Unsafe program file list entry"};
    }
    if (!names.insert(std::move(name)).second) throw Failure{code, "Duplicate program file"};
  }
  return names;
}

// Binds the expanded payload to the signed manifest and describes the files
// currently installed, so Apply only ever replaces what this release shipped.
PreparedUpdate Prepare(const fs::path& workspace, const fs::path& install) {
  const auto trusted = Modulus();
  if (trusted.empty()) throw Failure{kUnsupported, "Development build has no update key"};
  const auto manifest = ReadBytes(workspace / L"update-manifest.json", kMaxManifest, kInvalid);
  const auto signature = ReadBytes(workspace / L"update-manifest.sig", kSignatureBytes, kInvalid);
  if (signature.size() != kSignatureBytes ||
      !shiori::VerifyManifestSignature(std::vector<uint8_t>(manifest.begin(), manifest.end()),
                                       std::vector<uint8_t>(signature.begin(), signature.end()),
                                       trusted)) {
    throw Failure{kInvalid, "Manifest signature rejected"};
  }
  WindowsRelease release;
  try {
    release = ReadWindowsRelease(manifest);
  } catch (const std::exception& error) {
    throw Failure{kInvalid, error.what()};
  }
  if (release.build <= static_cast<int64_t>(SHIORI_UPDATE_BUILD)) {
    throw Failure{kInvalid, "Release is not newer than the installation"};
  }
  Log("verified manifest " + release.tag + " build " + std::to_string(release.build));

  PreparedUpdate task{install, workspace, {}, {}};
  std::set<std::string> signed_names;
  const auto payload = workspace / L"payload";
  for (const auto& file : release.files) {
    try {
      ValidateRelativePath(file.path);
      const auto path = payload / fs::u8path(file.path);
      if (fs::file_size(path) != file.size || FileSha256(path) != file.sha256) {
        throw Failure{kInvalid, "Payload does not match manifest: " + file.path};
      }
    } catch (const std::exception&) {
      throw Failure{kInvalid, "Payload does not match manifest: " + file.path};
    }
    signed_names.insert(file.path);
    task.next.push_back({file.path, file.sha256});
  }
  for (const auto* name : kRequired) {
    if (!signed_names.count(name)) throw Failure{kInvalid, std::string("Release lacks ") + name};
  }
  if (ReadList(payload / L"program-files.txt", kInvalid) != signed_names) {
    throw Failure{kInvalid, "Release program list does not match manifest"};
  }

  const auto installed = install / L"program-files.txt";
  if (GetFileAttributesW(installed.c_str()) == INVALID_FILE_ATTRIBUTES) {
    throw Failure{kUnsupported, "Installation has no program file list"};
  }
  for (const auto& name : ReadList(installed, kUnsupported)) {
    try {
      task.current.push_back({name, FileSha256(install / fs::u8path(name))});
    } catch (const std::exception&) {
      throw Failure{kUnsupported, "Installed program file unavailable: " + name};
    }
  }
  return task;
}

bool FileId(const std::wstring& path, BY_HANDLE_FILE_INFORMATION& info) {
  Handle file(CreateFileW(path.c_str(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                          nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
  return file.get() != INVALID_HANDLE_VALUE && GetFileInformationByHandle(file.get(), &info);
}

// Another process started from this installation's shiori.exe.
bool OtherInstance(const fs::path& install, DWORD app) {
  BY_HANDLE_FILE_INFORMATION target{};
  if (!FileId((install / L"shiori.exe").wstring(), target)) return false;
  Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  if (snapshot.get() == INVALID_HANDLE_VALUE) throw Failure{kError, "Cannot list processes"};
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  for (auto more = Process32FirstW(snapshot.get(), &entry); more;
       more = Process32NextW(snapshot.get(), &entry)) {
    if (entry.th32ProcessID == app || entry.th32ProcessID == GetCurrentProcessId() ||
        !Same(entry.szExeFile, L"shiori.exe")) {
      continue;
    }
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID));
    if (!process.get()) continue;
    std::wstring image(32768, L'\0');
    DWORD size = static_cast<DWORD>(image.size());
    if (!QueryFullProcessImageNameW(process.get(), 0, image.data(), &size)) continue;
    image.resize(size);
    BY_HANDLE_FILE_INFORMATION info{};
    if (FileId(image, info) && info.dwVolumeSerialNumber == target.dwVolumeSerialNumber &&
        info.nFileIndexHigh == target.nFileIndexHigh && info.nFileIndexLow == target.nFileIndexLow) {
      return true;
    }
  }
  return false;
}

// Environmental checks with specific outcomes, then every engine precondition.
void Preflight(const PreparedUpdate& task, DWORD app) {
  if (GetDriveTypeW(task.install.root_path().c_str()) != DRIVE_FIXED) {
    throw Failure{kUnsupported, "Installation is not on a local fixed drive"};
  }
  uint64_t bytes = 0;
  std::set<std::wstring> directories{task.install.wstring()};
  for (const auto& file : task.current) {
    const auto path = task.install / fs::u8path(file.path);
    bytes += fs::file_size(path);
    const auto attributes = GetFileAttributesW(path.c_str());
    if (attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_READONLY)) {
      throw Failure{kStorage, "Read-only program file: " + file.path};
    }
    directories.insert(path.parent_path().wstring());
  }
  for (const auto& file : task.next) {
    bytes += fs::file_size(task.workspace / L"payload" / fs::u8path(file.path));
  }
  ULARGE_INTEGER free{};
  if (!GetDiskFreeSpaceExW(task.workspace.c_str(), &free, nullptr, nullptr) ||
      free.QuadPart <= bytes + 1024 * 1024) {
    throw Failure{kStorage, "Insufficient free space"};
  }
  for (const auto& directory : directories) {
    const auto probe = fs::path(directory) /
        (L".shiori-update-probe-" + std::to_wstring(GetCurrentProcessId()));
    Handle file(CreateFileW(probe.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_NEW,
                            FILE_ATTRIBUTE_TEMPORARY | FILE_FLAG_DELETE_ON_CLOSE, nullptr));
    if (file.get() == INVALID_HANDLE_VALUE) throw Failure{kStorage, "Installation is not writable"};
  }
  if (OtherInstance(task.install, app)) throw Failure{kInstances, "Another Shiori window is running"};
  try {
    Check(task);
  } catch (const std::exception& error) {
    throw Failure{kUnsupported, error.what()};
  }
}

void Relaunch(const fs::path& install) {
  bool started = false;
  try {
    started = LaunchApplication(install);
  } catch (const std::exception&) {
  }
  Log(started ? "relaunched" : "relaunch failed");
  if (!started) Notify(kLaunchMessage);
}

int CheckMode(const fs::path& workspace, const fs::path& install, DWORD app) {
  InstallLock lock(install);
  Preflight(Prepare(workspace, install), app);
  return kInstalled;
}

// After a recovery_required Apply: a few Recover attempts, since transient
// external locks usually clear within seconds; then report.
int Settle(const fs::path& workspace, const fs::path& install, const std::string& reason) {
  try {
    auto recovered = Recover(workspace, Log);
    for (int attempt = 0; attempt < kRecoverRetries && recovered.status == Status::recovery_required;
         ++attempt) {
      Log("recovery pending: " + recovered.detail);
      Sleep(kRecoverDelayMs);
      recovered = Recover(workspace, Log);
    }
    if (recovered.status == Status::installed) {
      WriteResult(workspace, kInstalled, recovered.detail);
      Relaunch(install);
      return kInstalled;
    }
    if (recovered.status == Status::rolled_back) {
      WriteResult(workspace, kRolledBack, reason);
      Relaunch(install);
      return kRolledBack;
    }
    WriteResult(workspace, kRecoveryRequired, reason + "; " + recovered.detail);
  } catch (const std::exception& error) {
    WriteResult(workspace, kRecoveryRequired, reason + "; " + error.what());
  }
  Notify(kRecoveryMessage);
  return kRecoveryRequired;
}

int ApplyMode(const fs::path& workspace, const fs::path& install, const wchar_t* handle_text) {
  InstallLock lock(install);
  wchar_t* end = nullptr;
  Handle parent(reinterpret_cast<HANDLE>(static_cast<uintptr_t>(wcstoull(handle_text, &end, 10))));
  if (!end || *end || !parent.get() || !GetProcessId(parent.get())) {
    throw Failure{kError, "Invalid application handle"};
  }
  Log("waiting for application exit");
  if (WaitForSingleObject(parent.get(), kExitTimeoutMs) != WAIT_OBJECT_0) {
    WriteResult(workspace, kTimeout, "Application did not exit");
    Notify(kTimeoutMessage);
    return kTimeout;
  }
  PreparedUpdate task;
  try {
    task = Prepare(workspace, install);
    Preflight(task, 0);
  } catch (const Failure& failure) {
    WriteResult(workspace, failure.code, failure.message);
    Relaunch(install);
    return failure.code;
  } catch (const std::exception& error) {
    WriteResult(workspace, kError, error.what());
    Relaunch(install);
    return kError;
  }
  Result result;
  try {
    result = Apply(task, nullptr, 0, Log);
  } catch (const std::exception& error) {
    WriteResult(workspace, kFailed, error.what());
    Relaunch(install);
    return kFailed;
  }
  switch (result.status) {
    case Status::installed:
      WriteResult(workspace, kInstalled, result.detail);
      return kInstalled;
    case Status::launch_failed:
      WriteResult(workspace, kLaunchFailed, result.detail);
      Notify(kLaunchMessage);
      return kLaunchFailed;
    case Status::rolled_back:
      WriteResult(workspace, kRolledBack, result.detail);
      Relaunch(install);
      return kRolledBack;
    case Status::recovery_required:
      break;
  }
  return Settle(workspace, install, result.detail);
}

int Recovered(Status status) {
  switch (status) {
    case Status::installed:
    case Status::launch_failed:
      return kInstalled;
    case Status::rolled_back:
      return kRolledBack;
    case Status::recovery_required:
      break;
  }
  return kRecoveryRequired;
}

int RecoverMode(const fs::path& workspace, const fs::path& install) {
  InstallLock lock(install);
  const auto plan = workspace / L"plan.bin";
  if (GetFileAttributesW(plan.c_str()) == INVALID_FILE_ATTRIBUTES) {
    // Refusals before any transaction leave only their result behind.
    const auto code = ReadResult(workspace);
    return code == kError || code == kFailed || code == kTimeout ||
                   (code >= kInstances && code <= kUnsupported)
               ? code
               : kNone;
  }
  const auto task = ReadTask(plan);
  if (InstallationMutexName(task.install) != InstallationMutexName(install)) {
    throw Failure{kError, "Transaction belongs to another installation"};
  }
  return Recovered(Recover(workspace, Log).status);
}

// Double-clicked from a workspace left in recovery_required.
int StandaloneMode() {
  std::wstring self(32768, L'\0');
  self.resize(GetModuleFileNameW(nullptr, self.data(), static_cast<DWORD>(self.size())));
  const auto workspace = fs::path(self).parent_path();
  workspace_for_log = workspace;
  const auto plan = workspace / L"plan.bin";
  if (GetFileAttributesW(plan.c_str()) == INVALID_FILE_ATTRIBUTES) return kNone;
  const auto install = ReadTask(plan).install;
  CheckPaths(workspace, install);
  int code = kRecoveryRequired;
  {
    InstallLock lock(install);
    code = Recovered(Recover(workspace, Log).status);
  }
  if (code == kRecoveryRequired) {
    Notify(kRecoveryMessage);
  } else {
    Relaunch(install);
  }
  return code;
}

int Run(int argc, wchar_t** argv) {
  if (argc == 1) return StandaloneMode();
  const std::wstring mode = argv[1];
  if (argc < 4) throw Failure{kError, "Unexpected arguments"};
  const fs::path workspace = fs::path(argv[2]).lexically_normal();
  const fs::path install = fs::path(argv[3]).lexically_normal();
  CheckPaths(workspace, install);
  workspace_for_log = workspace;
  if (mode == L"check" && argc == 5) {
    wchar_t* end = nullptr;
    const auto app = wcstoul(argv[4], &end, 10);
    if (!end || *end || !app) throw Failure{kError, "Invalid application process id"};
    return CheckMode(workspace, install, app);
  }
  if (mode == L"apply" && argc == 5) return ApplyMode(workspace, install, argv[4]);
  if (mode == L"recover" && argc == 4) return RecoverMode(workspace, install);
  throw Failure{kError, "Unexpected arguments"};
}
}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  int argc = 0;
  auto** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv) return kError;
  int code = kError;
  try {
    code = Run(argc, argv);
  } catch (const Failure& failure) {
    Log("refused " + std::to_string(failure.code) + ": " + failure.message);
    code = failure.code;
  } catch (const std::exception& error) {
    Log(std::string("error: ") + error.what());
  }
  LocalFree(argv);
  return code;
}
