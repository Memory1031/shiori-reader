#include "audio_player.h"

#include <comdef.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <shlwapi.h>  // for SHCreateMemStream
#include <shobjidl.h>
#include <windows.h>

#include "audioplayers_helpers.h"

#define STR_LINK_TROUBLESHOOTING \
  "https://github.com/bluefireteam/audioplayers/blob/main/troubleshooting.md"
#undef GetCurrentTime

using namespace winrt;

PreparedAudioSource ResolveAudioSource(const std::string& url,
                                      const std::vector<uint8_t>& bytes) {
  PreparedAudioSource result;
  result.platform = std::make_shared<media::MFPlatformRef>();
  result.platform->Startup();
  winrt::com_ptr<IMFSourceResolver> resolver;
  THROW_IF_FAILED(MFCreateSourceResolver(resolver.put()));
  constexpr uint32_t flags = MF_RESOLUTION_MEDIASOURCE |
      MF_RESOLUTION_CONTENT_DOES_NOT_HAVE_TO_MATCH_EXTENSION_OR_MIME_TYPE |
      MF_RESOLUTION_READ;
  MF_OBJECT_TYPE type = {};
  if (!bytes.empty()) {
    winrt::com_ptr<IStream> memory;
    memory.attach(SHCreateMemStream(bytes.data(), static_cast<UINT>(bytes.size())));
    THROW_HR_IF(E_OUTOFMEMORY, !memory);
    winrt::com_ptr<IMFByteStream> stream;
    THROW_IF_FAILED(MFCreateMFByteStreamOnStream(memory.get(), stream.put()));
    THROW_IF_FAILED(resolver->CreateObjectFromByteStream(
        stream.get(), nullptr, flags, nullptr, &type,
        reinterpret_cast<IUnknown**>(result.source.put_void())));
  } else {
    THROW_IF_FAILED(resolver->CreateObjectFromURL(
        winrt::to_hstring(url).c_str(), flags, nullptr, &type,
        reinterpret_cast<IUnknown**>(result.source.put_void())));
  }
  return result;
}

AudioPlayer::AudioPlayer(
    std::string playerId,
    flutter::MethodChannel<flutter::EncodableValue>* methodChannel,
    EventStreamHandler<>* eventHandler,
    const std::shared_ptr<audioplayers_windows::PlatformThreadDispatcher>& dispatcher,
    SourceResolver resolver)
    : m_sourcePreparation(dispatcher->GetPoster()),
      m_sourceResolver(std::move(resolver)),
      _playerId(playerId),
      _methodChannel(methodChannel),
      _eventHandler(eventHandler) {
  m_mfPlatform.Startup();

  // Callbacks invoked by the media engine wrapper
  auto onError = m_sourcePreparation.Bind(
      [this](MF_MEDIA_ENGINE_ERR error, HRESULT hr) { OnMediaError(error, hr); });
  auto onBufferingStateChanged = m_sourcePreparation.Bind(
      [this](media::MediaEngineWrapper::BufferingState state) {
        OnMediaStateChange(state);
      });
  auto onPlaybackEndedCB = m_sourcePreparation.Bind([this] { OnPlaybackEnded(); });
  auto onSeekCompletedCB = m_sourcePreparation.Bind([this] { OnSeekCompleted(); });
  auto onLoadedCB = m_sourcePreparation.Bind([this] { SendInitialized(); });

  // Create and initialize the MediaEngineWrapper which manages media playback
  m_mediaEngineWrapper = winrt::make_self<media::MediaEngineWrapper>(
      onLoadedCB, onError, onBufferingStateChanged, onPlaybackEndedCB,
      onSeekCompletedCB);

  m_mediaEngineWrapper->Initialize();
}

AudioPlayer::~AudioPlayer() { Dispose(); }

// Called on the platform thread; the resolver owns independent worker inputs.
void AudioPlayer::SetSourceUrl(std::string url) {
  if (_url == url && _isInitialized) {
    OnPrepared(true);
  } else {
    _url = url;
    PrepareSource(std::move(url), {});
  }
}

void AudioPlayer::SetSourceBytes(std::vector<uint8_t> bytes) {
  _url.clear();
  PrepareSource({}, std::move(bytes));
}

void AudioPlayer::PrepareSource(std::string url, std::vector<uint8_t> bytes) {
  _isInitialized = false;
  m_sourcePreparation.Start(
      [resolve = m_sourceResolver, url = std::move(url), bytes = std::move(bytes)] {
        return resolve(url, bytes);
      },
      [this](PreparedAudioSource& result) {
        try {
          THROW_HR_IF(E_UNEXPECTED, !result.source);
          m_mediaEngineWrapper->SetMediaSource(result.source.get());
          result.installed = true;
        } catch (...) {
          SourceError(std::current_exception());
        }
      },
      [this](std::exception_ptr error) { SourceError(error); });
}

void AudioPlayer::SourceError(std::exception_ptr error) {
  try {
    std::rethrow_exception(error);
  } catch (const std::exception& ex) {
    OnError("WindowsAudioError", "Failed to set source. For troubleshooting, "
            "see: " STR_LINK_TROUBLESHOOTING, flutter::EncodableValue(ex.what()));
  } catch (...) {
    OnError("WindowsAudioError", "Failed to set source. For troubleshooting, "
            "see: " STR_LINK_TROUBLESHOOTING, flutter::EncodableValue("Unknown source error"));
  }
}

void AudioPlayer::OnMediaError(MF_MEDIA_ENGINE_ERR error, HRESULT hr) {
  LOG_HR_MSG(hr, "MediaEngine error (%d)", error);
  // TODO(Gustl22): adapt log message to dart error event, check stacktrace.
  if (this->_eventHandler) {
    _com_error err(hr);

    std::wstring wstr(err.ErrorMessage());

    int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, &wstr[0],
                                   (int)wstr.size(), NULL, 0, NULL, NULL);
    std::string ret = std::string(size, 0);
    WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, &wstr[0],
                        (int)wstr.size(), &ret[0], size, NULL, NULL);

    std::string message = "MediaEngine error";
    this->OnError(std::to_string(error), message, flutter::EncodableValue(ret));
  }
}

void AudioPlayer::OnError(const std::string& code,
                          const std::string& message,
                          const flutter::EncodableValue& details) {
  if (this->_eventHandler) {
    this->_eventHandler->Error(code, message, details);
  }
}

void AudioPlayer::OnMediaStateChange(
    media::MediaEngineWrapper::BufferingState bufferingState) {
  if (bufferingState !=
      media::MediaEngineWrapper::BufferingState::HAVE_NOTHING) {
    // TODO(Gustl22): add buffering state
  }
}

void AudioPlayer::OnPrepared(bool isPrepared) {
  if (this->_eventHandler) {
    this->_eventHandler->Success(std::make_unique<flutter::EncodableValue>(
        flutter::EncodableMap({{flutter::EncodableValue("event"),
                                flutter::EncodableValue("audio.onPrepared")},
                               {flutter::EncodableValue("value"),
                                flutter::EncodableValue(isPrepared)}})));
  }
}

void AudioPlayer::OnPlaybackEnded() {
  if (this->_eventHandler) {
    this->_eventHandler->Success(std::make_unique<flutter::EncodableValue>(
        flutter::EncodableMap({{flutter::EncodableValue("event"),
                                flutter::EncodableValue("audio.onComplete")},
                               {flutter::EncodableValue("value"),
                                flutter::EncodableValue(true)}})));
  }
  if (GetReleaseMode() == ReleaseMode::loop) {
    Play();
  } else {
    Stop();
  }
}

void AudioPlayer::OnDurationUpdate() {
  auto duration = m_mediaEngineWrapper->GetDuration();
  if (this->_eventHandler) {
    this->_eventHandler->Success(
        std::make_unique<flutter::EncodableValue>(flutter::EncodableMap(
            {{flutter::EncodableValue("event"),
              flutter::EncodableValue("audio.onDuration")},
             {flutter::EncodableValue("value"),
              isnan(duration)
                  ? flutter::EncodableValue(std::monostate{})
                  : flutter::EncodableValue(ConvertSecondsToMs(duration))}})));
  }
}

void AudioPlayer::OnSeekCompleted() {
  if (this->_eventHandler) {
    this->_eventHandler->Success(
        std::make_unique<flutter::EncodableValue>(flutter::EncodableMap(
            {{flutter::EncodableValue("event"),
              flutter::EncodableValue("audio.onSeekComplete")},
             {flutter::EncodableValue("value"),
              flutter::EncodableValue(true)}})));
  }
}

void AudioPlayer::OnLog(const std::string& message) {
  this->_eventHandler->Success(std::make_unique<flutter::EncodableValue>(
      flutter::EncodableMap({{flutter::EncodableValue("event"),
                              flutter::EncodableValue("audio.onLog")},
                             {flutter::EncodableValue("value"),
                              flutter::EncodableValue(message)}})));
}

void AudioPlayer::SendInitialized() {
  if (!this->_isInitialized) {
    this->_isInitialized = true;
    OnPrepared(true);
    OnDurationUpdate();
  }
}

void AudioPlayer::ReleaseMediaSource() {
  m_sourcePreparation.Cancel();
  if (_isInitialized) {
    m_mediaEngineWrapper->Pause();
  }
  m_mediaEngineWrapper->ReleaseMediaSource();
  _url.clear();
  _isInitialized = false;
}

void AudioPlayer::Dispose() {
  if (m_disposed) return;
  m_disposed = true;
  m_sourcePreparation.Retire();
  ReleaseMediaSource();
  m_mediaEngineWrapper->Shutdown();
  _methodChannel = nullptr;
  _eventHandler = nullptr;
}

void AudioPlayer::SetReleaseMode(ReleaseMode releaseMode) {
  m_mediaEngineWrapper->SetLooping(releaseMode == ReleaseMode::loop);
  _releaseMode = releaseMode;
}

ReleaseMode AudioPlayer::GetReleaseMode() {
  return _releaseMode;
}

void AudioPlayer::SetVolume(double volume) {
  if (volume > 1) {
    volume = 1;
  } else if (volume < 0) {
    volume = 0;
  }
  m_mediaEngineWrapper->SetVolume((float)volume);
}

void AudioPlayer::SetPlaybackSpeed(double playbackSpeed) {
  m_mediaEngineWrapper->SetPlaybackRate(playbackSpeed);
}

void AudioPlayer::SetBalance(double balance) {
  m_mediaEngineWrapper->SetBalance(balance);
}

void AudioPlayer::Play() {
  m_mediaEngineWrapper->StartPlayingFrom(m_mediaEngineWrapper->GetMediaTime());
  OnDurationUpdate();
}

void AudioPlayer::Pause() {
  m_mediaEngineWrapper->Pause();
}

void AudioPlayer::Stop() {
  Pause();
  if (GetReleaseMode() == ReleaseMode::release) {
    ReleaseMediaSource();
  } else {
    SeekTo(0);
  }
}

void AudioPlayer::Resume() {
  m_mediaEngineWrapper->Resume();
  OnDurationUpdate();
}

double AudioPlayer::GetPosition() {
  if (!_isInitialized) {
    return std::numeric_limits<double>::quiet_NaN();
  }
  return m_mediaEngineWrapper->GetMediaTime();
}

double AudioPlayer::GetDuration() {
  return m_mediaEngineWrapper->GetDuration();
}

void AudioPlayer::SeekTo(double seek) {
  m_mediaEngineWrapper->SeekTo(seek);
}
