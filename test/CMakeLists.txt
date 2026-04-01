# Test targets will be added as we implement instructions.
# Each test is a Sail file compiled to a C executable.
#
# Usage:
#   cmake --build build
#   ctest --test-dir build

# Helper function: compile a Sail test to a C executable and register it with CTest.
#
# Arguments:
#   TEST_NAME  - name for the test (used as executable name and CTest label)
#   TEST_SAIL  - path to the test .sail file
#
# The test Sail file is compiled together with all model files.
# Sail generates C, which is compiled with gcc and linked against libgmp and the Sail runtime.
function(add_sail_test TEST_NAME TEST_SAIL)
    set(TEST_C "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}.c")
    set(TEST_EXE "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}")

    # Step 1: Sail -> C
    add_custom_command(
        OUTPUT ${TEST_C}
        COMMAND ${SAIL} -c ${MODEL_SAIL_FILES} ${CMAKE_SOURCE_DIR}/${TEST_SAIL} -o ${TEST_C}
        DEPENDS ${MODEL_SAIL_FILES} ${CMAKE_SOURCE_DIR}/${TEST_SAIL}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        COMMENT "Compiling Sail test ${TEST_NAME} to C..."
    )

    # Step 2: C -> executable
    add_executable(${TEST_NAME} ${TEST_C} ${SAIL_DIR}/lib/sail.c)
    target_include_directories(${TEST_NAME} PRIVATE ${SAIL_DIR}/lib)
    target_link_libraries(${TEST_NAME} PRIVATE gmp z)
    target_compile_options(${TEST_NAME} PRIVATE -O2)

    # Step 3: Register with CTest
    add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
endfunction()
