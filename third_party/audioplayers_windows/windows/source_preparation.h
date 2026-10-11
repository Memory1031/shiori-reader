#pragma once

#include "platform_thread_dispatcher.h"

#include <atomic>
#include <exception>
#include <stdexcept>
#include <thread>
#include <type_traits>
#include <objbase.h>

namespace audioplayers_windows {

// A source resolver can outlive its player (including a Dart prepared timeout).
// Only independent resolver inputs/results cross that lifetime. Completion and
// media callbacks access the player exclusively through a live platform ticket.
class SourcePreparation {
 public:
  explicit SourcePreparation(PlatformThreadDispatcher::Poster post)
      : post_(std::move(post)), state_(std::make_shared<State>()) {}
  ~SourcePreparation() { Retire(); }

  void Cancel() {
    assert(GetCurrentThreadId() == platform_thread_);
    if (state_) ++state_->generation;
  }

  void Retire() {
    Cancel();
    state_.reset();
  }

  template <typename Prepare, typename Complete, typename Failure>
  void Start(Prepare prepare, Complete complete, Failure failure) {
    Cancel();
    if (!state_) return;
    const auto generation = state_->generation.load();
    const auto weak = std::weak_ptr<State>(state_);
    std::thread([post = post_, weak, generation,
                 prepare = std::move(prepare), complete = std::move(complete),
                 failure = std::move(failure)]() mutable {
      try {
        Apartment apartment;
        if (FAILED(apartment.status)) {
          throw std::runtime_error("Cannot initialize source resolver apartment");
        }
        using Result = std::invoke_result_t<Prepare>;
        const auto result = std::make_shared<Result>(prepare());
        post([weak, generation, result, complete = std::move(complete)]() mutable {
          if (Current(weak, generation)) complete(*result);
        });
      } catch (...) {
        const auto error = std::current_exception();
        post([weak, generation, error, failure = std::move(failure)]() mutable {
          if (Current(weak, generation)) failure(error);
        });
      }
    }).detach();
  }

  template <typename Callback>
  auto Bind(Callback callback) const {
    const auto weak = std::weak_ptr<State>(state_);
    return [weak, post = post_, callback](auto... arguments) {
      const auto state = weak.lock();
      if (!state) return;
      const auto generation = state->generation.load();
      post([weak, generation, callback, arguments...] {
        if (Current(weak, generation)) callback(arguments...);
      });
    };
  }

 private:
  struct Apartment {
    const HRESULT status = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    ~Apartment() {
      if (SUCCEEDED(status)) CoUninitialize();
    }
  };
  struct State {
    std::atomic<uint64_t> generation{0};
  };
  static bool Current(const std::weak_ptr<State>& weak, uint64_t generation) {
    const auto state = weak.lock();
    return state && state->generation == generation;
  }
  const DWORD platform_thread_ = GetCurrentThreadId();
  PlatformThreadDispatcher::Poster post_;
  std::shared_ptr<State> state_;
};

}  // namespace audioplayers_windows
