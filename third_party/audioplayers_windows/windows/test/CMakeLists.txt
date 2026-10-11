cmake_minimum_required(VERSION 3.15)
project(audioplayers_event_stream_test LANGUAGES CXX)

if(NOT WIN32)
  message(FATAL_ERROR "Audio platform-thread tests require Windows")
endif()
if(NOT EXISTS "${FLUTTER_WRAPPER_INCLUDE}/flutter/event_channel.h")
  message(FATAL_ERROR "Set FLUTTER_WRAPPER_INCLUDE to Flutter's generated client-wrapper include directory")
endif()

add_executable(audioplayers_event_stream_test event_stream_handler_test.cpp)
target_compile_features(audioplayers_event_stream_test PRIVATE cxx_std_17)
target_compile_definitions(audioplayers_event_stream_test PRIVATE NOMINMAX)
target_include_directories(audioplayers_event_stream_test PRIVATE
  ".." "${FLUTTER_WRAPPER_INCLUDE}")
target_link_libraries(audioplayers_event_stream_test PRIVATE user32)
if(MSVC)
  target_compile_options(audioplayers_event_stream_test PRIVATE /W4 /WX /wd4100 /EHsc)
endif()

enable_testing()
foreach(case worker_events cancel_relisten handler_destroy shutdown owners reentrant_shutdown)
  add_test(NAME ${case} COMMAND audioplayers_event_stream_test ${case})
endforeach()

if(DEFINED AUDIOPLAYER_WINDOWS_BUILD)
  get_filename_component(FLUTTER_EPHEMERAL "${FLUTTER_WRAPPER_INCLUDE}/../.." ABSOLUTE)
  add_executable(audioplayers_source_lifecycle_test
    source_lifecycle_test.cpp ../audio_player.cpp ../MediaEngineWrapper.cpp
    ../MediaEngineExtension.cpp)
  target_compile_features(audioplayers_source_lifecycle_test PRIVATE cxx_std_17)
  target_compile_definitions(audioplayers_source_lifecycle_test PRIVATE NOMINMAX UNICODE _UNICODE)
  target_include_directories(audioplayers_source_lifecycle_test PRIVATE
    ".." "${FLUTTER_WRAPPER_INCLUDE}" "${FLUTTER_EPHEMERAL}"
    "${AUDIOPLAYER_WINDOWS_BUILD}/packages/Microsoft.Windows.ImplementationLibrary/include")
  target_link_libraries(audioplayers_source_lifecycle_test PRIVATE
    "${AUDIOPLAYER_WINDOWS_BUILD}/flutter/$<CONFIG>/flutter_wrapper_plugin.lib"
    "${FLUTTER_EPHEMERAL}/flutter_windows.dll.lib"
    mfplat windowsapp shlwapi user32)
  if(MSVC)
    target_compile_options(audioplayers_source_lifecycle_test PRIVATE /W4 /WX /wd4100 /EHsc)
  endif()
  add_custom_command(TARGET audioplayers_source_lifecycle_test POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FLUTTER_EPHEMERAL}/flutter_windows.dll" "$<TARGET_FILE_DIR:audioplayers_source_lifecycle_test>")
  foreach(case dispose_url dispose_bytes dispose_error release_pending replace_pending dispatcher_shutdown normal_prepare)
    add_test(NAME ${case} COMMAND audioplayers_source_lifecycle_test ${case})
    set_tests_properties(${case} PROPERTIES TIMEOUT 20)
  endforeach()
endif()
