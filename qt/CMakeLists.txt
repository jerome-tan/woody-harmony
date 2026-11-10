find_package(Qt6 6.12.0 EXACT REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Concurrent)
qt_standard_project_setup(REQUIRES 6.12)

add_library(woody_core STATIC
    src/MemoryParser.cpp src/MemoryParser.h
    src/ReportStore.cpp src/ReportStore.h
    src/HdcClient.cpp src/HdcClient.h
    src/Report.cpp src/Report.h
    src/Backend.cpp src/Backend.h src/DeviceMonitor.h
)
target_link_libraries(woody_core PUBLIC Qt6::Core Qt6::Gui Qt6::Concurrent)
target_include_directories(woody_core PUBLIC src)

if(BUILD_TESTING)
    find_package(Qt6 6.12.0 EXACT REQUIRED COMPONENTS Test)
    qt_add_executable(woody_core_test tests/CoreTest.cpp)
    target_link_libraries(woody_core_test PRIVATE woody_core Qt6::Test)
    add_test(NAME woody_core COMMAND woody_core_test)
    qt_add_executable(woody_fake_hdc tests/FakeHdc.cpp)
    target_link_libraries(woody_fake_hdc PRIVATE Qt6::Core)
    qt_add_executable(woody_backend_test tests/BackendTest.cpp)
    target_link_libraries(woody_backend_test PRIVATE woody_core Qt6::Test)
    add_dependencies(woody_backend_test woody_fake_hdc)
    add_test(NAME woody_backend COMMAND woody_backend_test)
    qt_add_executable(woody_image_test tests/ComparisonImageTest.cpp
        src/ComparisonImageExporter.cpp src/ComparisonImageExporter.h
        src/MemoryPlot.cpp src/MemoryPlot.h)
    target_link_libraries(woody_image_test PRIVATE woody_core Qt6::Test Qt6::Quick)
    if(WIN32)
        target_compile_options(woody_image_test PRIVATE /utf-8)
    endif()
    add_test(NAME woody_image COMMAND woody_image_test)
    set_tests_properties(woody_image PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    if(APPLE OR WIN32)
        qt_add_executable(woody_device_monitor_test tests/DeviceMonitorTest.cpp)
        target_link_libraries(woody_device_monitor_test PRIVATE woody_core Qt6::Test)
        add_test(NAME woody_device_monitor COMMAND woody_device_monitor_test)
        set_tests_properties(woody_device_monitor PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    endif()
endif()

qt_add_executable(Woody MACOSX_BUNDLE WIN32
    src/ComparisonImageExporter.cpp src/ComparisonImageExporter.h
    src/main.cpp src/MemoryPlot.cpp src/MemoryPlot.h src/SnapshotPlot.cpp src/SnapshotPlot.h
    tests/UiAutomation.cpp tests/UiAutomation.h
)
target_link_libraries(Woody PRIVATE woody_core Qt6::Quick Qt6::QuickControls2)
execute_process(COMMAND git rev-parse --short=12 HEAD WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}" OUTPUT_VARIABLE WOODY_COMMIT OUTPUT_STRIP_TRAILING_WHITESPACE)
target_compile_definitions(Woody PRIVATE WOODY_VERSION="${PROJECT_VERSION}" WOODY_COMMIT="${WOODY_COMMIT}")
file(GLOB WOODY_QML CONFIGURE_DEPENDS "qml/*.qml" "qml/*.js")
foreach(qml_file IN LISTS WOODY_QML)
    get_filename_component(qml_name "${qml_file}" NAME)
    set_source_files_properties("${qml_file}" PROPERTIES QT_RESOURCE_ALIAS "${qml_name}")
endforeach()
qt_add_qml_module(Woody URI Woody VERSION 1.0 RESOURCE_PREFIX /qt/qml QML_FILES ${WOODY_QML})
qt_add_resources(Woody assets PREFIX /assets BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources" FILES "${CMAKE_CURRENT_SOURCE_DIR}/resources/icon.png")
file(GLOB WOODY_ICONS CONFIGURE_DEPENDS "assets/icons/*.svg")
qt_add_resources(Woody icons PREFIX /icons BASE "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons" FILES ${WOODY_ICONS})
qt_add_resources(Woody brand PREFIX /assets BASE "${CMAKE_CURRENT_SOURCE_DIR}/resources" FILES "${CMAKE_CURRENT_SOURCE_DIR}/resources/icon-win.png")
if(APPLE)
    enable_language(OBJCXX)
    set_property(TARGET woody_core PROPERTY OBJCXX_STANDARD 20)
    target_sources(woody_core PRIVATE src/PlatformWindow_mac.mm src/DeviceMonitor_mac.mm)
    target_sources(Woody PRIVATE tests/UiAutomation_mac.mm)
    target_link_libraries(woody_core PUBLIC "-framework AppKit" "-framework IOKit")
    target_sources(Woody PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/resources/icon.icns")
    set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/resources/icon.icns" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    set_target_properties(Woody PROPERTIES
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.woody.harmony"
        MACOSX_BUNDLE_BUNDLE_NAME Woody
        MACOSX_BUNDLE_ICON_FILE icon.icns
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    )
else()
    target_sources(woody_core PRIVATE src/PlatformWindow.cpp)
    if(WIN32)
        target_sources(woody_core PRIVATE src/DeviceMonitor_win.cpp)
        target_compile_definitions(woody_core PRIVATE _WIN32_WINNT=0x0A00 WINVER=0x0A00)
        target_link_libraries(woody_core PUBLIC Cfgmgr32 PowrProf)
    else()
        target_sources(woody_core PRIVATE src/DeviceMonitor.cpp)
    endif()
endif()
install(TARGETS Woody BUNDLE DESTINATION . RUNTIME DESTINATION .)
if(WIN32)
    configure_file(resources/app.rc.in app.rc @ONLY)
    target_sources(Woody PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/app.rc")
    target_compile_options(woody_core PRIVATE /utf-8)
    target_compile_options(Woody PRIVATE /utf-8)
endif()
