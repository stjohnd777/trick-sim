add_library(cannon STATIC
    src/cannon_init.c
    src/cannon_analytic.c
    src/cannon_shutdown.c)

# Headers are referenced as "cannon/include/..." from the S_define.
target_include_directories(cannon PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/..")
target_link_libraries(cannon PUBLIC Trick::Trick)
