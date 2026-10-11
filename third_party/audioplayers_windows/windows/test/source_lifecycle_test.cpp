#include "audio_player.h"

#include <chrono>
#include <iostream>
#include <thread>

using audioplayers_windows::PlatformThreadDispatcher;
using namespace std::chrono_literals;

namespace {

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
template <typename Condition>
void Await(Condition condition) {
  const auto deadline = std::chrono::steady_clock::now() + 5s;
  while (!condition()) {
    Check(std::chrono::steady_clock::now() < deadline, "Native task timed out");
    Pump();
    std::this_thread::sleep_for(1ms);
  }
  Pump();
}
std::vector<uint8_t> Wav() {
  std::vector<uint8_t> bytes(16044);
  auto word = [&](size_t at, const char* value) {
    for (size_t i = 0; i < 4; i++) bytes[at + i] = value[i];
  };
  auto number = [&](size_t at, uint32_t value, size_t count) {
    for (size_t i = 0; i < count; i++) bytes[at + i] = static_cast<uint8_t>(value >> (i * 8));
  };
  word(0, "RIFF"); word(8, "WAVE"); word(12, "fmt "); word(36, "data");
  number(4, 16036, 4); number(16, 16, 4); number(20, 1, 2);
  number(22, 1, 2); number(24, 8000, 4); number(28, 16000, 4);
  number(32, 2, 2); number(34, 16, 2); number(40, 16000, 4);
  return bytes;
}

struct Record {
  int prepared = 0;
  int errors = 0;
  std::vector<DWORD> threads;
};
class Sink : public flutter::EventSink<flutter::EncodableValue> {
 public:
  explicit Sink(Record& record) : record_(record) {}
 protected:
  void SuccessInternal(const flutter::EncodableValue* value) override {
    const auto& map = std::get<flutter::EncodableMap>(*value);
    const auto event = std::get<std::string>(map.at(flutter::EncodableValue("event")));
    if (event == "audio.onPrepared") ++record_.prepared;
    record_.threads.push_back(GetCurrentThreadId());
  }
  void ErrorInternal(const std::string&, const std::string&,
                     const flutter::EncodableValue*) override {
    ++record_.errors;
    record_.threads.push_back(GetCurrentThreadId());
  }
  void EndOfStreamInternal() override {}
 private:
  Record& record_;
};

struct Gate {
  std::promise<void> entered;
  std::promise<void> release;
  std::shared_future<void> released = release.get_future().share();
  std::promise<void> returned;
  std::weak_ptr<media::MFPlatformRef> resource;
};

void Lifetime(const std::string& test) {
  auto dispatcher = std::make_shared<PlatformThreadDispatcher>();
  Record record;
  auto handler = std::make_unique<EventStreamHandler<>>(dispatcher);
  handler->OnListen(nullptr, std::make_unique<Sink>(record));
  auto gate = std::make_shared<Gate>();
  const auto entered = gate->entered.get_future();
  auto returned = gate->returned.get_future();
  const auto platform_thread = GetCurrentThreadId();
  auto player = std::make_unique<AudioPlayer>(
      "source-lifetime", nullptr, handler.get(), dispatcher,
      [gate, platform_thread, test](const std::string& url,
                                   const std::vector<uint8_t>& bytes) {
        Check(GetCurrentThreadId() != platform_thread, "Resolver blocked the platform thread");
        if (url == "replacement" || test == "normal_prepare") {
          return ResolveAudioSource({}, Wav());
        }
        Check(test == "dispose_bytes" ? bytes == Wav() : url == "held",
              "Source inputs did not survive the caller");
        gate->entered.set_value();
        gate->released.wait();
        if (test == "dispose_error") {
          gate->returned.set_value();
          throw std::runtime_error("Delayed resolver failure");
        }
        auto source = ResolveAudioSource({}, Wav());
        gate->resource = source.platform;
        gate->returned.set_value();
        return source;
      });
  if (test == "normal_prepare") {
    player->SetSourceBytes(Wav());
    Await([&] { return record.prepared == 1 || record.errors != 0; });
    Check(record.prepared == 1 && record.errors == 0, "Valid WAV failed preparation");
    for (const auto thread : record.threads) {
      Check(thread == platform_thread, "Prepared callback left the platform thread");
    }
    player->Dispose();
    return;
  }
  if (test == "dispose_bytes") player->SetSourceBytes(Wav());
  else player->SetSourceUrl("held");
  Check(entered.wait_for(5s) == std::future_status::ready, "Resolver never entered");

  if (test == "replace_pending") {
    player->SetSourceUrl("replacement");
    Await([&] { return record.prepared == 1 || record.errors != 0; });
    Check(record.prepared == 1 && record.errors == 0, "Replacement source failed");
  } else if (test == "release_pending") {
    player->ReleaseMediaSource();
  } else {
    const auto started = std::chrono::steady_clock::now();
    player->Dispose();
    player.reset();
    Check(std::chrono::steady_clock::now() - started < 2s,
          "Dispose waited for the suspended resolver");
    handler.reset();
    if (test == "dispatcher_shutdown") dispatcher.reset();
  }
  gate->release.set_value();
  Check(returned.wait_for(5s) == std::future_status::ready, "Resolver never returned");
  if (test != "dispose_error") {
    Await([&] { return gate->resource.expired(); });
  } else {
    const auto weak = std::weak_ptr<Gate>(gate);
    gate.reset();
    Await([&] { return weak.expired(); });
  }
  Check(record.prepared == (test == "replace_pending" ? 1 : 0) && record.errors == 0,
        "Retired source installed media or emitted an event");
}

}  // namespace

int main(int argc, char** argv) {
  try {
    Check(argc == 2, "Pass a test name");
    THROW_IF_FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED));
    const auto uninitialize = wil::scope_exit([] { CoUninitialize(); });
    Lifetime(argv[1]);
    std::cout << argv[1] << ": passed" << std::endl;
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
}
