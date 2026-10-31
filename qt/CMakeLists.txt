find_package(Qt6 6.12.0 EXACT REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Concurrent)
qt_standard_project_setup(REQUIRES 6.12)

add_library(woody_core STATIC
    src/MemoryParser.cpp src/MemoryParser.h
    src/ReportStore.cpp src/ReportStore.h
    src/HdcClient.cpp src/HdcClient.h
    src/Report.cpp src/Report.h
    src/Backend.cpp src/Backend.h
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
endif()

qt_add_executable(Woody MACOSX_BUNDLE WIN32
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
qt_add_resources(Woody assets PREFIX /assets BASE "${PROJECT_SOURCE_DIR}/build" FILES "${PROJECT_SOURCE_DIR}/build/icon.png")
if(APPLE)
    target_sources(Woody PRIVATE "${PROJECT_SOURCE_DIR}/build/icon.icns")
    set_source_files_properties("${PROJECT_SOURCE_DIR}/build/icon.icns" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    set_target_properties(Woody PROPERTIES
        MACOSX_BUNDLE_GUI_IDENTIFIER "com.woody.harmony"
        MACOSX_BUNDLE_BUNDLE_NAME Woody
        MACOSX_BUNDLE_ICON_FILE icon.icns
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    )
endif()
install(TARGETS Woody BUNDLE DESTINATION . RUNTIME DESTINATION .)
if(WIN32)
    configure_file(resources/app.rc.in app.rc @ONLY)
    target_sources(Woody PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/app.rc")
    target_compile_options(woody_core PRIVATE /utf-8)
    target_compile_options(Woody PRIVATE /utf-8)
endif()
