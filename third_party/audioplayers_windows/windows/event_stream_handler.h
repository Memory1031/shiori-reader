#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>

#include <atomic>

#include "platform_thread_dispatcher.h"

using namespace flutter;

template <typename T = EncodableValue>
class EventStreamHandler : public StreamHandler<T> {
 public:
  explicit EventStreamHandler(
      std::shared_ptr<audioplayers_windows::PlatformThreadDispatcher> dispatcher)
      : dispatcher_(std::move(dispatcher)), state_(std::make_shared<State>()) {}

  virtual ~EventStreamHandler() = default;

  void Success(std::unique_ptr<T> _data) {
    const auto generation = state_->generation.load();
    const auto data = std::shared_ptr<T>(std::move(_data));
    const auto weak = std::weak_ptr<State>(state_);
    dispatcher_->Post([weak, generation, data] {
      if (const auto state = weak.lock();
          state && state->generation == generation && state->sink) {
        state->sink->Success(*data);
      }
    });
  }

  void Error(const std::string& error_code,
             const std::string& error_message,
             const T& error_details) {
    const auto generation = state_->generation.load();
    const auto weak = std::weak_ptr<State>(state_);
    dispatcher_->Post([weak, generation, error_code, error_message,
                       error_details] {
      if (const auto state = weak.lock();
          state && state->generation == generation && state->sink) {
        state->sink->Error(error_code, error_message, error_details);
      }
    });
  }

 protected:
  std::unique_ptr<StreamHandlerError<T>> OnListenInternal(
      const T* arguments,
      std::unique_ptr<EventSink<T>>&& events) override {
    assert(dispatcher_->RunsOnCurrentThread());
    state_->generation++;
    state_->sink = std::move(events);
    return nullptr;
  }

  std::unique_ptr<StreamHandlerError<T>> OnCancelInternal(
      const T* arguments) override {
    assert(dispatcher_->RunsOnCurrentThread());
    state_->generation++;
    state_->sink.reset();
    return nullptr;
  }

 private:
  struct State {
    std::atomic<uint64_t> generation{0};
    std::unique_ptr<EventSink<T>> sink;
  };
  const std::shared_ptr<audioplayers_windows::PlatformThreadDispatcher>
      dispatcher_;
  const std::shared_ptr<State> state_;
};
