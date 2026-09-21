// Test-only process harness. Unsigned synthetic tasks must never be accepted by
// the release updater; this executable is not included in application bundles.
#include "../windows/update/update_transaction.h"

#include <iostream>
#include <stdexcept>

using namespace shiori::update;

int wmain(int argc, wchar_t** argv) {
  HANDLE parent = nullptr;
  HANDLE ready = nullptr;
  HANDLE proceed = nullptr;
  try {
    if (argc < 3) throw std::runtime_error("Expected mode and task/workspace");
    const bool apply = std::wstring(argv[1]) == L"apply";
    const bool recover = std::wstring(argv[1]) == L"recover";
    if (!apply && !recover) throw std::runtime_error("Unknown probe mode");
    const int base = apply ? 5 : 3;
    if (argc != base && argc != base + 3) throw std::runtime_error("Invalid probe arguments");
    Progress progress;
    if (argc == base + 3) {
      const auto checkpoint = fs::path(argv[base]).u8string();
      ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, argv[base + 1]);
      proceed = OpenEventW(SYNCHRONIZE, FALSE, argv[base + 2]);
      if (!ready || !proceed) throw std::runtime_error("Missing test barrier");
      progress = [=](const std::string& point) {
        if (point == checkpoint) {
          SetEvent(ready);
          if (WaitForSingleObject(proceed, 15000) != WAIT_OBJECT_0) {
            throw std::runtime_error("Test barrier timed out");
          }
        }
      };
    }
    Result result;
    if (apply) {
      const auto pid = std::stoul(argv[3]);
      if (pid) {
        parent = OpenProcess(SYNCHRONIZE, FALSE, pid);
        if (!parent) throw std::runtime_error("Cannot open parent process");
      }
      result = Apply(ReadTask(argv[2]), parent, std::stoul(argv[4]), progress);
    } else {
      result = Recover(argv[2], progress);
    }
    if (parent) CloseHandle(parent);
    if (ready) CloseHandle(ready);
    if (proceed) CloseHandle(proceed);
    std::cout << static_cast<int>(result.status) << ": " << result.detail << '\n';
    return static_cast<int>(result.status);
  } catch (const std::exception& error) {
    if (parent) CloseHandle(parent);
    if (ready) CloseHandle(ready);
    if (proceed) CloseHandle(proceed);
    std::cerr << error.what() << '\n';
    return 10;
  }
}
