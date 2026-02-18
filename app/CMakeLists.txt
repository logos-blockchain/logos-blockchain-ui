cmake_minimum_required(VERSION 3.16)
project(LogosBlockchainUIApp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

# Find Qt packages
find_package(QT NAMES Qt6 Qt5 REQUIRED COMPONENTS Core Widgets)
find_package(Qt${QT_VERSION_MAJOR} REQUIRED COMPONENTS Core Widgets)

# Find logos-liblogos
if(NOT DEFINED LOGOS_LIBLOGOS_ROOT)
    message(FATAL_ERROR "LOGOS_LIBLOGOS_ROOT must be defined")
endif()

message(STATUS "Using logos-liblogos at: ${LOGOS_LIBLOGOS_ROOT}")

# Include and link directories (app only uses logos_core from liblogos, not the SDK)
include_directories(
    ${LOGOS_LIBLOGOS_ROOT}/include
)

link_directories(
    ${LOGOS_LIBLOGOS_ROOT}/lib
)

# Set output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Create the executable
add_executable(logos-blockchain-ui-app
    main.cpp
    mainwindow.cpp
    mainwindow.h
)

# Link libraries
target_link_libraries(logos-blockchain-ui-app PRIVATE
    Qt${QT_VERSION_MAJOR}::Core
    Qt${QT_VERSION_MAJOR}::Widgets
    logos_core
)

# Set RPATH settings for the executable
if(APPLE)
    set_target_properties(logos-blockchain-ui-app PROPERTIES
        INSTALL_RPATH "@executable_path/../lib"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
elseif(UNIX)
    set_target_properties(logos-blockchain-ui-app PROPERTIES
        INSTALL_RPATH "$ORIGIN/../lib"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
endif()

# Install rules
install(TARGETS logos-blockchain-ui-app
    RUNTIME DESTINATION bin
)
