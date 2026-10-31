# Compiling and linking lives here; build.py assembles and signs the bundle on the Mac.
set(NP_MODEL_SOURCES NPFoundation.mm NPGame.mm NPStore.mm NPLauncher.mm)
set(NP_UI_SOURCES NPTheme.mm NPArtwork.mm NPLibraryController.mm NPLibraryPage.mm NPBackupsPage.mm
    NPPerformancePage.mm NPControllersPage.mm NPSidebarViewController.mm NPDetailViewController.mm
    NPWindowController.mm NPAppDelegate.mm)
set(NP_FRAMEWORKS "-framework Cocoa" "-framework Security" "-framework UniformTypeIdentifiers"
    "-framework AVFoundation" "-framework CoreMedia" "-framework QuartzCore")

function(np_target target)
    target_include_directories(${target} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_compile_options(${target} PRIVATE -fobjc-arc -Wall -Wextra -Werror -Wno-unused-parameter)
    target_link_libraries(${target} PRIVATE ${NP_FRAMEWORKS})
    # The cppbuild image has a private libc++: link it statically so the bundle stays one
    # executable that imports system libraries only. Native builds use the system's.
    if(EXISTS /opt/macos/lib/libc++.a)
        target_link_options(${target} PRIVATE -nostdlib++ /opt/macos/lib/libc++.a)
    endif()
endfunction()

add_executable(NativePlay main.mm ${NP_MODEL_SOURCES} ${NP_UI_SOURCES})
np_target(NativePlay)
target_link_options(NativePlay PRIVATE -Wl,-dead_strip)

add_executable(np-render-icon render_icon.mm NPTheme.mm)
np_target(np-render-icon)

# Tests. Undefined behavior traps here, with no sanitizer runtime to ship or install.
add_executable(np-backend-tests tests/backend_tests.mm ${NP_MODEL_SOURCES})
np_target(np-backend-tests)
target_compile_options(np-backend-tests PRIVATE -fsanitize=undefined -fsanitize-trap=undefined)
target_link_options(np-backend-tests PRIVATE -fsanitize=undefined -fsanitize-trap=undefined)

add_executable(np-ui-tests tests/ui_tests.mm ${NP_MODEL_SOURCES} ${NP_UI_SOURCES})
np_target(np-ui-tests)

add_executable(np-launch-check tests/launch_check.mm ${NP_MODEL_SOURCES})
np_target(np-launch-check)

add_executable(np-fixture tests/fixture.c)
target_compile_options(np-fixture PRIVATE -Wall -Wextra -Werror)

add_executable(np-managed-fixture tests/managed_fixture.mm)
np_target(np-managed-fixture)

add_executable(np-game-mode-fixture tests/game_mode_fixture.mm)
np_target(np-game-mode-fixture)
target_link_libraries(np-game-mode-fixture PRIVATE "-framework Metal" "-framework QuartzCore")
