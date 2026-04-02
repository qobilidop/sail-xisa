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
# The test Sail file is compiled together with model/main.sail (which $includes
# all other model files). The test defines a Sail main() which Sail wraps.
function(add_sail_test TEST_NAME TEST_SAIL)
    # Sail's -o flag appends .c to the given name, so -o foo produces foo.c
    set(SAIL_OUT_STEM "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}")
    set(TEST_C "${SAIL_OUT_STEM}.c")
    set(TEST_EXE "${CMAKE_CURRENT_BINARY_DIR}/${TEST_NAME}")

    # Step 1: Sail -> C
    # model/main.sail $includes all model files, so we only pass it + the test file.
    add_custom_command(
        OUTPUT ${TEST_C}
        COMMAND ${SAIL} -c
            ${CMAKE_SOURCE_DIR}/model/main.sail
            ${CMAKE_SOURCE_DIR}/${TEST_SAIL}
            -o ${SAIL_OUT_STEM}
        DEPENDS ${MODEL_SAIL_FILES} ${CMAKE_SOURCE_DIR}/${TEST_SAIL}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        COMMENT "Compiling Sail test ${TEST_NAME} to C..."
    )

    # Step 2: C -> executable
    # Link against Sail runtime and dependencies.
    add_executable(${TEST_NAME}
        ${TEST_C}
        ${SAIL_DIR}/lib/sail.c
        ${SAIL_DIR}/lib/rts.c
        ${SAIL_DIR}/lib/elf.c
        ${SAIL_DIR}/lib/sail_failure.c
    )
    target_include_directories(${TEST_NAME} PRIVATE ${SAIL_DIR}/lib)
    target_link_libraries(${TEST_NAME} PRIVATE gmp z)
    target_compile_options(${TEST_NAME} PRIVATE -O2)

    # Step 3: Register with CTest
    add_test(NAME ${TEST_NAME} COMMAND ${TEST_NAME})
endfunction()

add_sail_test(test_nop test/parser/test_nop.sail)
add_sail_test(test_halt test/parser/test_halt.sail)
add_sail_test(test_mov test/parser/test_mov.sail)
add_sail_test(test_ext test/parser/test_ext.sail)
add_sail_test(test_add test/parser/test_add.sail)
add_sail_test(test_sub test/parser/test_sub.sail)
add_sail_test(test_and test/parser/test_and.sail)
add_sail_test(test_or test/parser/test_or.sail)
add_sail_test(test_cmp test/parser/test_cmp.sail)
add_sail_test(test_cnct test/parser/test_cnct.sail)
add_sail_test(test_br test/parser/test_br.sail)
add_sail_test(test_brbtst test/parser/test_brbtst.sail)
add_sail_test(test_integration test/parser/test_integration.sail)
add_sail_test(test_ext_edge test/parser/test_ext_edge.sail)
add_sail_test(test_program test/parser/test_program.sail)
add_sail_test(test_stc test/parser/test_stc.sail)
add_sail_test(test_sth test/parser/test_sth.sail)
add_sail_test(test_st test/parser/test_st.sail)
add_sail_test(test_extmap_movmap test/parser/test_extmap_movmap.sail)
add_sail_test(test_movl_movr test/parser/test_movl_movr.sail)
add_sail_test(test_nxtp test/parser/test_nxtp.sail)
add_sail_test(test_compound test/parser/test_compound.sail)
add_sail_test(test_pseek test/parser/test_pseek.sail)
add_sail_test(test_encoding test/parser/test_encoding.sail)

# MAP ISA tests
add_sail_test(test_map_nop_halt test/map/test_nop_halt.sail)
add_sail_test(test_map_mov test/map/test_mov.sail)
add_sail_test(test_map_add test/map/test_add.sail)
