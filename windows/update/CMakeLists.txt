cmake_minimum_required(VERSION 3.19)
project(shiori_updater LANGUAGES CXX)

# The updater trusts only the key and build embedded here from build-info.json,
# which tool/update_manifest.py identity writes for release builds. Development
# builds have no key, so their updater refuses every release.
set(BUILD_INFO "${CMAKE_CURRENT_SOURCE_DIR}/../../assets/release/build-info.json")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${BUILD_INFO}")
file(READ "${BUILD_INFO}" SHIORI_BUILD_INFO)
string(JSON SHIORI_UPDATE_MODULUS ERROR_VARIABLE SHIORI_NO_KEY
  GET "${SHIORI_BUILD_INFO}" publicKey modulus)
if(SHIORI_NO_KEY)
  set(SHIORI_UPDATE_MODULUS "")
  set(SHIORI_UPDATE_BUILD 0)
else()
  string(JSON SHIORI_UPDATE_BUILD GET "${SHIORI_BUILD_INFO}" identity build)
  string(LENGTH "${SHIORI_UPDATE_MODULUS}" SHIORI_MODULUS_LENGTH)
  if(NOT SHIORI_MODULUS_LENGTH EQUAL 768 OR NOT SHIORI_UPDATE_MODULUS MATCHES "^[89a-f][0-9a-f]*$"
     OR NOT SHIORI_UPDATE_BUILD MATCHES "^[1-9][0-9]*$")
    message(FATAL_ERROR "Invalid update trust in ${BUILD_INFO}")
  endif()
endif()

add_executable(shiori-updater WIN32
  "updater_main.cpp"
  "release_manifest.cpp"
  "update_transaction.cpp"
  "manifest_signature.cpp"
)
# Not APPLY_STANDARD_SETTINGS: the updater relies on C++ exceptions. It runs
# from the workspace, away from the bundled CRT DLLs, so it links the CRT statically.
target_compile_features(shiori-updater PRIVATE cxx_std_17)
target_compile_options(shiori-updater PRIVATE /W4 /WX /EHsc /utf-8)
target_compile_definitions(shiori-updater PRIVATE NOMINMAX
  "SHIORI_UPDATE_MODULUS=\"${SHIORI_UPDATE_MODULUS}\""
  "SHIORI_UPDATE_BUILD=${SHIORI_UPDATE_BUILD}")
set_property(TARGET shiori-updater PROPERTY MSVC_RUNTIME_LIBRARY
  "MultiThreaded$<$<CONFIG:Debug>:Debug>")
target_link_options(shiori-updater PRIVATE "/MANIFESTUAC:level='asInvoker' uiAccess='false'")
target_link_libraries(shiori-updater PRIVATE bcrypt user32 shell32)
