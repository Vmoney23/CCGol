cmake_minimum_required(VERSION 3.3)
project(CCGol)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")

set(SOURCE_FILES
    game_of_life/src/pgmIO.c
    game_of_life/src/pgmIO.h
    lib_i2c/api/i2c.h
    lib_logging/api/debug_print.h
    lib_logging/src/debug_printf.c
    lib_xassert/api/xassert.h)

add_executable(CCGol ${SOURCE_FILES})