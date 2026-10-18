cmake_minimum_required(VERSION 3.15)
project(shiori_window_placement_test LANGUAGES CXX)
if(NOT WIN32 OR NOT EXISTS "${FLUTTER_ENGINE}/flutter_windows.dll.lib")
  message(FATAL_ERROR "Windows and FLUTTER_ENGINE from the pinned Flutter SDK are required")
endif()
add_executable(window_placement_test window_placement_test.cpp
  ../window_placement.cpp ../win32_window.cpp)
target_compile_features(window_placement_test PRIVATE cxx_std_17)
target_compile_definitions(window_placement_test PRIVATE NOMINMAX UNICODE _UNICODE)
target_include_directories(window_placement_test PRIVATE .. "${FLUTTER_ENGINE}")
target_link_libraries(window_placement_test PRIVATE
  "${FLUTTER_ENGINE}/flutter_windows.dll.lib" dwmapi advapi32 user32)
target_compile_options(window_placement_test PRIVATE /W4 /WX /wd4100 /EHsc)
add_custom_command(TARGET window_placement_test POST_BUILD COMMAND ${CMAKE_COMMAND}
  -E copy_if_different "${FLUTTER_ENGINE}/flutter_windows.dll"
  "$<TARGET_FILE_DIR:window_placement_test>")
enable_testing()
add_test(NAME geometry COMMAND window_placement_test geometry)
add_test(NAME native_lifecycle COMMAND window_placement_test lifecycle)
