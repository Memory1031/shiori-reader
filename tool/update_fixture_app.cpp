// A tiny real Windows process, deliberately independent of Shiori/user data.
#include <windows.h>

#include <fstream>
#include <string>

#ifndef FIXTURE_VERSION
#error FIXTURE_VERSION must be defined
#endif

int wmain(int argc, wchar_t** argv) {
  if (argc == 3) {
    HANDLE ready = OpenEventW(EVENT_MODIFY_STATE, FALSE, argv[1]);
    HANDLE stop = OpenEventW(SYNCHRONIZE, FALSE, argv[2]);
    if (!ready || !stop) return 3;
    SetEvent(ready);
    const auto wait = WaitForSingleObject(stop, 15000);
    CloseHandle(ready);
    CloseHandle(stop);
    return wait == WAIT_OBJECT_0 ? 0 : 4;
  }
  std::ifstream data("runtime.bin");
  std::string version;
  data >> version;
  if (version != std::to_string(FIXTURE_VERSION)) return 5;
  std::ofstream result("launched.txt");
  result << FIXTURE_VERSION;
  return result.good() ? 0 : 6;
}
