#include "event_stream_handler.h"

#include <iostream>
#include <string>
#include <thread>
#include <vector>

using audioplayers_windows::PlatformThreadDispatcher;

namespace {

struct Record {
  std::vector<std::string> events;
  std::vector<DWORD> threads;
  int destroyed = 0;
};

class RecordingSink : public flutter::EventSink<std::string> {
 public:
  explicit RecordingSink(Record& record) : record_(record) {}
  ~RecordingSink() override { record_.destroyed++; }

 protected:
  void SuccessInternal(const std::string* value) override {
    record_.events.push_back(*value);
    record_.threads.push_back(GetCurrentThreadId());
  }
  void ErrorInternal(const std::string& code, const std::string& message,
                     const std::string* details) override {
    record_.events.push_back(code + ":" + message + ":" + *details);
    record_.threads.push_back(GetCurrentThreadId());
  }
  void EndOfStreamInternal() override {}

 private:
  Record& record_;
};

void Check(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}

void Pump() {
  MSG message;
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
}

void WorkerEvents() {
  const auto platform_thread = GetCurrentThreadId();
  const auto dispatcher = std::make_shared<PlatformThreadDispatcher>();
  Record record;
  EventStreamHandler<std::string> handler(dispatcher);
  handler.OnListen(nullptr, std::make_unique<RecordingSink>(record));
  std::thread worker([&] {
    for (int i = 0; i < 64; i++) {
      handler.Success(std::make_unique<std::string>(std::to_string(i)));
    }
    const std::string details = "copied worker details";
    handler.Error("decode", "failed", details);
  });
  worker.join();
  Check(record.events.empty(), "Worker sent an event before platform dispatch");
  handler.Success(std::make_unique<std::string>("platform"));
  Pump();
  Check(record.events.size() == 66, "An event was lost");
  for (int i = 0; i < 64; i++) {
    Check(record.events[i] == std::to_string(i), "Event order changed");
  }
  Check(record.events[64] == "decode:failed:copied worker details",
        "Error details did not survive worker return");
  Check(record.events[65] == "platform", "Platform event overtook worker events");
  for (const auto thread : record.threads) {
    Check(thread == platform_thread, "Event sink ran on a non-platform thread");
  }
}

void CancelRelisten() {
  const auto dispatcher = std::make_shared<PlatformThreadDispatcher>();
  Record old_record, new_record;
  EventStreamHandler<std::string> handler(dispatcher);
  handler.OnListen(nullptr, std::make_unique<RecordingSink>(old_record));
  std::thread worker([&] {
    handler.Success(std::make_unique<std::string>("old"));
    handler.Error("old", "error", "details");
  });
  worker.join();
  handler.OnCancel(nullptr);
  Check(old_record.destroyed == 1, "Cancelled sink leaked");
  handler.OnListen(nullptr, std::make_unique<RecordingSink>(new_record));
  handler.Success(std::make_unique<std::string>("new"));
  Pump();
  Check(old_record.events.empty(), "Cancelled subscription received an event");
  Check(new_record.events == std::vector<std::string>{"new"},
        "Old queued events reached the new subscription");
}

void HandlerDestroy() {
  const auto dispatcher = std::make_shared<PlatformThreadDispatcher>();
  Record record;
  {
    EventStreamHandler<std::string> handler(dispatcher);
    handler.OnListen(nullptr, std::make_unique<RecordingSink>(record));
    std::thread worker([&] {
      handler.Success(std::make_unique<std::string>("late"));
    });
    worker.join();
  }
  Pump();
  Check(record.events.empty(), "Destroyed handler received an event");
  Check(record.destroyed == 1, "Destroyed handler retained its sink");
}

void Shutdown() {
  const auto dispatcher = std::make_shared<PlatformThreadDispatcher>();
  bool called = false;
  auto payload = std::make_shared<int>(42);
  const auto weak = std::weak_ptr<int>(payload);
  dispatcher->Post([payload, &called] { called = true; });
  payload.reset();
  dispatcher->Shutdown();
  Check(weak.expired(), "Shutdown retained queued payloads");
  Check(!dispatcher->Post([&called] { called = true; }),
        "Shutdown dispatcher accepted work");
  Pump();
  Check(!called, "A task ran after dispatcher shutdown");
}

void Owners() {
  const auto first = std::make_shared<PlatformThreadDispatcher>();
  const auto second = std::make_shared<PlatformThreadDispatcher>();
  int a = 0, b = 0;
  std::thread worker([&] {
    first->Post([&] { a++; });
    second->Post([&] { b++; });
  });
  worker.join();
  first->Shutdown();
  Pump();
  Check(a == 0 && b == 1, "Dispatchers shared queues or shutdown ownership");
}

void ReentrantShutdown() {
  const auto dispatcher = std::make_shared<PlatformThreadDispatcher>();
  int called = 0;
  dispatcher->Post([&] { dispatcher->Shutdown(); });
  dispatcher->Post([&] { called++; });
  Pump();
  Check(called == 0, "Draining continued after reentrant shutdown");
}

}  // namespace

int main(int argc, char** argv) {
  try {
    Check(argc == 2, "Pass a test name");
    const std::string test = argv[1];
    if (test == "worker_events") WorkerEvents();
    else if (test == "cancel_relisten") CancelRelisten();
    else if (test == "handler_destroy") HandlerDestroy();
    else if (test == "shutdown") Shutdown();
    else if (test == "owners") Owners();
    else if (test == "reentrant_shutdown") ReentrantShutdown();
    else throw std::runtime_error("Unknown test");
    std::cout << test << ": passed" << std::endl;
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
}
