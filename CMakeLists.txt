cmake_minimum_required(VERSION 3.25)
# Native tools only. Each game is built by its own Python pipeline from the player's files.
set(CMAKE_OSX_DEPLOYMENT_TARGET 26.0 CACHE STRING "Minimum macOS version" FORCE)
project(MacNativeGamesTools LANGUAGES C OBJC CXX OBJCXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_subdirectory(tools/native-play)

add_executable(jamboree-launcher games/jamboree/app/launcher.c)
target_compile_options(jamboree-launcher PRIVATE -Wall -Wextra -Werror)
