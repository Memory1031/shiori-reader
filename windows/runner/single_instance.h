#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

// A per-user, session-local gate held until the native process finishes teardown.
class SingleInstance {
 public:
  enum class Result { primary, activated, failed };
  SingleInstance();
  ~SingleInstance();
  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;
  Result Acquire();
  static UINT ActivationMessage();
  static constexpr const wchar_t* kWindowProperty = L"Shiori.Reader.Instance.v1";

 private:
  HANDLE mutex_ = nullptr;
  bool owned_ = false;
};

#endif  // RUNNER_SINGLE_INSTANCE_H_
