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
