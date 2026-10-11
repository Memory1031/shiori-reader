#pragma once

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#undef GetCurrentTime

#include <shobjidl.h>
#include <unknwn.h>
#include <winrt/Windows.Foundation.Collections.h>

#include "winrt/Windows.System.h"

// Include prior to C++/WinRT Headers
#include <wil/cppwinrt.h>

// Windows Implementation Library
#include <wil/resource.h>
#include <wil/result_macros.h>

// MediaFoundation headers
#include <Audioclient.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfmediaengine.h>

// STL headers
#include <wincodec.h>

#include <functional>
#include <future>
#include <map>
#include <memory>
#include <sstream>
#include <string>

#include "MediaEngineWrapper.h"
#include "MediaFoundationHelpers.h"
#include "event_stream_handler.h"
#include "source_preparation.h"

using namespace winrt;

enum ReleaseMode { stop, release, loop };

struct PreparedAudioSource {
  // Keep Media Foundation alive until an uninstalled result is discarded.
  std::shared_ptr<media::MFPlatformRef> platform;
  winrt::com_ptr<IMFMediaSource> source;
  bool installed = false;
  PreparedAudioSource() = default;
  PreparedAudioSource(PreparedAudioSource&&) = default;
  ~PreparedAudioSource() {
    if (source && !installed) source->Shutdown();
  }
};
PreparedAudioSource ResolveAudioSource(const std::string& url,
                                      const std::vector<uint8_t>& bytes);

static std::unordered_map<std::string, ReleaseMode> const releaseModeMap = {
    {"ReleaseMode.stop", ReleaseMode::stop},
    {"ReleaseMode.release", ReleaseMode::release},
    {"ReleaseMode.loop", ReleaseMode::loop}};

class AudioPlayer {
 public:
  using SourceResolver = std::function<PreparedAudioSource(
      const std::string&, const std::vector<uint8_t>&)>;
  AudioPlayer(std::string playerId,
              flutter::MethodChannel<flutter::EncodableValue>* methodChannel,
              EventStreamHandler<>* eventHandler,
              const std::shared_ptr<audioplayers_windows::PlatformThreadDispatcher>& dispatcher,
              SourceResolver resolver = ResolveAudioSource);

  void Dispose();

  void ReleaseMediaSource();

  void SetReleaseMode(ReleaseMode releaseMode);

  void SetVolume(double volume);

  void SetPlaybackSpeed(double playbackSpeed);

  void SetBalance(double balance);

  void Play();

  void Pause();

  void Stop();

  void Resume();

  ReleaseMode GetReleaseMode();

  double GetPosition();

  double GetDuration();

  void SeekTo(double seek);

  void SetSourceBytes(std::vector<uint8_t> bytes);

  void SetSourceUrl(std::string url);

  void OnLog(const std::string& message);

  void OnError(const std::string& code,
               const std::string& message,
               const flutter::EncodableValue& details);

  virtual ~AudioPlayer();

 private:
  // Media members
  media::MFPlatformRef m_mfPlatform;
  winrt::com_ptr<media::MediaEngineWrapper> m_mediaEngineWrapper;
  audioplayers_windows::SourcePreparation m_sourcePreparation;
  const SourceResolver m_sourceResolver;
  bool m_disposed = false;
  void PrepareSource(std::string url, std::vector<uint8_t> bytes);
  void SourceError(std::exception_ptr error);

  bool _isInitialized = false;
  ReleaseMode _releaseMode = ReleaseMode::release;
  std::string _url{};

  void SendInitialized();

  void OnMediaError(MF_MEDIA_ENGINE_ERR error, HRESULT hr);

  void OnMediaStateChange(
      media::MediaEngineWrapper::BufferingState bufferingState);

  void OnPlaybackEnded();

  void OnDurationUpdate();

  void OnSeekCompleted();

  void OnPrepared(bool isPrepared);

  std::string _playerId;

  flutter::MethodChannel<flutter::EncodableValue>* _methodChannel;

  EventStreamHandler<>* _eventHandler;
};
