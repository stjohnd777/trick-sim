cmake_minimum_required(VERSION 3.25)
project(SIM_cannon_analytic LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
find_package(Trick 25 REQUIRED)

add_subdirectory(models/cannon)

trick_add_simulation(S_main
    S_DEFINE S_define
    MODELS cannon)
