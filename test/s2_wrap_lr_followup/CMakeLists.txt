add_definitions(-DTEST_MULTICAST_TX)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-undef -Wno-unused-parameter -ggdb")

# S2_wrap.c contains -Wconversion hits in ZIP_Router_logging.h macros that
# predate this test; suppress them here so we don't block the build.
set_source_files_properties(
  ${CMAKE_SOURCE_DIR}/src/transport/S2_wrap.c
  PROPERTIES COMPILE_FLAGS "-Wno-conversion"
)

add_unity_test(NAME test_s2wrap_lr_followup
  FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/test_s2wrap_lr_followup.c
    ${CMAKE_SOURCE_DIR}/src/transport/S2_wrap.c
    ${CMAKE_SOURCE_DIR}/src/utls/zgw_nodemask.c
    ${CMAKE_SOURCE_DIR}/contiki/core/lib/assert.c
)

target_include_directories(test_s2wrap_lr_followup PRIVATE
  ${CMAKE_SOURCE_DIR}/libs2/include
  ${CMAKE_SOURCE_DIR}/src/analyzer
  ${CMAKE_SOURCE_DIR}/contiki/core/lib
)
