cmake_minimum_required(VERSION 3.20)
project(sail-xisa LANGUAGES C)

# Find the Sail compiler
find_program(SAIL sail REQUIRED)
message(STATUS "Found Sail: ${SAIL}")

# Find the Sail library directory (for C runtime headers and sources)
# SAIL_DIR should be set in the environment (set in our Dockerfile)
if(DEFINED ENV{SAIL_DIR})
    set(SAIL_DIR $ENV{SAIL_DIR})
else()
    message(FATAL_ERROR "SAIL_DIR environment variable not set. Cannot find Sail runtime.")
endif()
message(STATUS "Sail directory: ${SAIL_DIR}")

# Collect all model Sail files
file(GLOB_RECURSE MODEL_SAIL_FILES "${CMAKE_SOURCE_DIR}/model/*.sail")

# The main entry point includes all model files via $include.
set(MODEL_MAIN "${CMAKE_SOURCE_DIR}/model/main.sail")

# Target: type-check the model (fast, no C compilation)
# Use model/main.sail which $includes everything in the right order.
add_custom_target(check
    COMMAND ${SAIL} --just-check ${MODEL_MAIN}
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    COMMENT "Type-checking Sail model..."
    SOURCES ${MODEL_SAIL_FILES}
)

# Enable testing
enable_testing()
add_subdirectory(test)
