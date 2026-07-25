cmake_minimum_required(VERSION 3.22.1)

project(resq_llama LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT ANDROID_ABI STREQUAL "arm64-v8a")
    message(FATAL_ERROR "resQ local inference supports arm64-v8a only")
endif()

set(GGML_SYSTEM_ARCH ARM)
set(GGML_CPU_KLEIDIAI ON)
set(GGML_OPENMP ON)

set(LLAMA_SRC "${CMAKE_CURRENT_LIST_DIR}/llama.cpp")
add_subdirectory("${LLAMA_SRC}" llama-build)

# Use the upstream Android JNI implementation so chat templates and token
# generation stay aligned with the bundled llama.cpp revision.
add_library(ai-chat SHARED
    "${LLAMA_SRC}/examples/llama.android/lib/src/main/cpp/ai_chat.cpp")

target_compile_definitions(ai-chat PRIVATE
    GGML_SYSTEM_ARCH=${GGML_SYSTEM_ARCH}
    GGML_CPU_KLEIDIAI=$<BOOL:${GGML_CPU_KLEIDIAI}>
    GGML_OPENMP=$<BOOL:${GGML_OPENMP}>)

target_include_directories(ai-chat PRIVATE
    "${LLAMA_SRC}"
    "${LLAMA_SRC}/common"
    "${LLAMA_SRC}/include"
    "${LLAMA_SRC}/ggml/include"
    "${LLAMA_SRC}/ggml/src"
    "${LLAMA_SRC}/examples/llama.android/lib/src/main/cpp")

target_link_libraries(ai-chat
    llama
    llama-common
    android
    log)
