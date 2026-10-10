#ifndef AUDIOPLAYERS_WINDOWS_PLATFORM_THREAD_DISPATCHER_H_
#define AUDIOPLAYERS_WINDOWS_PLATFORM_THREAD_DISPATCHER_H_

#include <windows.h>

#include <cassert>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <stdexcept>

namespace audioplayers_windows {

// Created and destroyed by the plugin on Flutter's platform thread. Worker
// threads only enqueue; no synchronous SendMessage or platform-thread wait.
class PlatformThreadDispatcher {
 public:
  using Task = std::function<void()>;

  PlatformThreadDispatcher() : state_(std::make_shared<State>()) {
    const auto instance = GetModuleHandleW(nullptr);
    WNDCLASSW window_class{};
    window_class.lpfnWndProc = WindowProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = kWindowClass;
    if (!RegisterClassW(&window_class) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      throw std::runtime_error("Cannot register audio event dispatcher");
    }
    state_->window = CreateWindowExW(0, kWindowClass, L"", 0, 0, 0, 0, 0,
                                    HWND_MESSAGE, nullptr, instance,
                                    state_.get());
    if (!state_->window) {
      throw std::runtime_error("Cannot create audio event dispatcher");
    }
  }

  ~PlatformThreadDispatcher() { Shutdown(); }
  PlatformThreadDispatcher(const PlatformThreadDispatcher&) = delete;
  PlatformThreadDispatcher& operator=(const PlatformThreadDispatcher&) = delete;

  bool RunsOnCurrentThread() const {
    return GetCurrentThreadId() == state_->platform_thread;
  }

  bool Post(Task task) {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (!state_->window) return false;
    state_->tasks.push_back(std::move(task));
    if (!PostMessageW(state_->window, kDispatchMessage, 0, 0)) {
      state_->tasks.pop_back();
      return false;
    }
    return true;
  }

  void Shutdown() {
    assert(RunsOnCurrentThread());
    HWND window;
    std::deque<Task> discarded;
    {
      std::lock_guard<std::mutex> lock(state_->mutex);
      window = state_->window;
      state_->window = nullptr;
      discarded.swap(state_->tasks);
    }
    if (window) DestroyWindow(window);
  }

 private:
  struct State : std::enable_shared_from_this<State> {
    const DWORD platform_thread = GetCurrentThreadId();
    HWND window = nullptr;
    std::mutex mutex;
    std::deque<Task> tasks;
  };

  static constexpr wchar_t kWindowClass[] =
      L"Shiori.AudioplayersPlatformThread";
  static constexpr UINT kDispatchMessage = WM_APP + 1;

  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam,
                                    LPARAM lparam) {
    if (message == WM_NCCREATE) {
      const auto create = reinterpret_cast<CREATESTRUCTW*>(lparam);
      SetWindowLongPtrW(window, GWLP_USERDATA,
                       reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    }
    auto* raw = reinterpret_cast<State*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == kDispatchMessage && raw) {
      // A dispatched callback may destroy its owner. Keep the queue state alive
      // until this window procedure returns, and stop after shutdown.
      const auto state = raw->shared_from_this();
      std::deque<Task> tasks;
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        tasks.swap(state->tasks);
      }
      for (auto& task : tasks) {
        {
          std::lock_guard<std::mutex> lock(state->mutex);
          if (!state->window) break;
        }
        task();
      }
      return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
  }

  std::shared_ptr<State> state_;
};

}  // namespace audioplayers_windows

#endif  // AUDIOPLAYERS_WINDOWS_PLATFORM_THREAD_DISPATCHER_H_
