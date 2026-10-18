#include "single_instance.h"

#include <sddl.h>
#include <string>
#include <vector>

namespace {
std::wstring MutexName() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return {};
  DWORD size = 0;
  GetTokenInformation(token, TokenUser, nullptr, 0, &size);
  std::vector<BYTE> storage(size);
  const bool read = GetTokenInformation(token, TokenUser, storage.data(), size, &size);
  CloseHandle(token);
  if (!read) return {};
  LPWSTR sid = nullptr;
  if (!ConvertSidToStringSidW(reinterpret_cast<TOKEN_USER*>(storage.data())->User.Sid, &sid)) {
    return {};
  }
  const std::wstring name = std::wstring(L"Local\\Shiori.Reader.Application.") + sid;
  LocalFree(sid);
  return name;
}

BOOL CALLBACK FindInstance(HWND window, LPARAM context) {
  if (GetPropW(window, SingleInstance::kWindowProperty)) {
    *reinterpret_cast<HWND*>(context) = window;
    return FALSE;
  }
  return TRUE;
}
}  // namespace

SingleInstance::SingleInstance() = default;
SingleInstance::~SingleInstance() {
  if (owned_) ReleaseMutex(mutex_);
  if (mutex_) CloseHandle(mutex_);
}

UINT SingleInstance::ActivationMessage() {
  static const UINT message = RegisterWindowMessageW(L"Shiori.Reader.Activate.v1");
  return message;
}

SingleInstance::Result SingleInstance::Acquire() {
  const auto name = MutexName();
  if (name.empty() || !ActivationMessage()) return Result::failed;
  mutex_ = CreateMutexW(nullptr, FALSE, name.c_str());
  if (!mutex_) return Result::failed;
  const ULONGLONG deadline = GetTickCount64() + 15000;
  do {
    const DWORD wait = WaitForSingleObject(mutex_, 0);
    if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
      owned_ = true;
      return Result::primary;
    }
    if (wait != WAIT_TIMEOUT) return Result::failed;
    HWND window = nullptr;
    EnumWindows(FindInstance, reinterpret_cast<LPARAM>(&window));
    if (window) {
      DWORD process = 0;
      GetWindowThreadProcessId(window, &process);
      // A user launch may grant the existing process foreground permission.
      AllowSetForegroundWindow(process);
      DWORD_PTR response = 0;
      if (SendMessageTimeoutW(window, ActivationMessage(), 0, 0,
                              SMTO_ABORTIFHUNG | SMTO_BLOCK, 200, &response) &&
          response == 1) {
        return Result::activated;
      }
    }
    // The first process may still be creating its window or finishing shutdown.
    Sleep(25);
  } while (GetTickCount64() < deadline);
  // Never create a second engine when the live owner cannot answer.
  return Result::failed;
}
