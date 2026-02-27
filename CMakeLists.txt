cmake_minimum_required(VERSION 3.16)
project(BlockchainUIPlugin VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Allow override from environment or command line
if(NOT DEFINED LOGOS_LIBLOGOS_ROOT)
    set(_parent_liblogos "${CMAKE_SOURCE_DIR}/../logos-liblogos")
    set(_use_vendor ${LOGOS_BLOCKCHAIN_UI_USE_VENDOR})
    if(NOT _use_vendor)
        if(NOT EXISTS "${_parent_liblogos}/interface.h")
            set(_use_vendor ON)
        endif()
    endif()
    if(_use_vendor)
        set(LOGOS_LIBLOGOS_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-liblogos")
    else()
        set(LOGOS_LIBLOGOS_ROOT "${_parent_liblogos}")
    endif()
endif()

if(NOT DEFINED LOGOS_CPP_SDK_ROOT)
    set(_parent_cpp_sdk "${CMAKE_SOURCE_DIR}/../logos-cpp-sdk")
    set(_use_vendor ${LOGOS_BLOCKCHAIN_UI_USE_VENDOR})
    if(NOT _use_vendor)
        if(NOT EXISTS "${_parent_cpp_sdk}/cpp/logos_api.h")
            set(_use_vendor ON)
        endif()
    endif()
    if(_use_vendor)
        set(LOGOS_CPP_SDK_ROOT "${CMAKE_SOURCE_DIR}/vendor/logos-cpp-sdk")
    else()
        set(LOGOS_CPP_SDK_ROOT "${_parent_cpp_sdk}")
    endif()
endif()

# Check if dependencies are available (support both source and installed layouts)
set(_liblogos_found FALSE)
if(EXISTS "${LOGOS_LIBLOGOS_ROOT}/interface.h")
    set(_liblogos_found TRUE)
    set(_liblogos_is_source TRUE)
elseif(EXISTS "${LOGOS_LIBLOGOS_ROOT}/include/interface.h")
    set(_liblogos_found TRUE)
    set(_liblogos_is_source FALSE)
endif()

set(_cpp_sdk_found FALSE)
if(EXISTS "${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.h")
    set(_cpp_sdk_found TRUE)
    set(_cpp_sdk_is_source TRUE)
elseif(EXISTS "${LOGOS_CPP_SDK_ROOT}/include/cpp/logos_api.h")
    set(_cpp_sdk_found TRUE)
    set(_cpp_sdk_is_source FALSE)
endif()

if(NOT _liblogos_found)
    message(FATAL_ERROR "logos-liblogos not found at ${LOGOS_LIBLOGOS_ROOT}. "
                        "Set LOGOS_LIBLOGOS_ROOT or run git submodule update --init --recursive.")
endif()

if(NOT _cpp_sdk_found)
    message(FATAL_ERROR "logos-cpp-sdk not found at ${LOGOS_CPP_SDK_ROOT}. "
                        "Set LOGOS_CPP_SDK_ROOT or run git submodule update --init --recursive.")
endif()

# Find Qt packages
find_package(Qt6 REQUIRED COMPONENTS Core Widgets RemoteObjects Quick QuickWidgets)

# Try to find the component-interfaces package first
find_package(component-interfaces QUIET)

# If not found, use the local interfaces folder
if(NOT component-interfaces_FOUND)
    # Include the local interfaces directory
    include_directories(${CMAKE_CURRENT_SOURCE_DIR}/interfaces)
    
    # Create a component-interfaces library
    add_library(component-interfaces INTERFACE)
    target_include_directories(component-interfaces INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/interfaces)
endif()

# Source files
set(SOURCES
    src/AccountsModel.cpp
    src/AccountsModel.h
    src/BlockchainPlugin.cpp
    src/BlockchainPlugin.h
    src/BlockchainBackend.cpp
    src/BlockchainBackend.h
    src/LogModel.cpp
    src/LogModel.h
    src/blockchain_resources.qrc
)

# Add SDK sources (only if source layout, installed layout uses the library)
if(_cpp_sdk_is_source)
    list(APPEND SOURCES
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_client.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_client.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_consumer.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_consumer.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_provider.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/logos_api_provider.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/token_manager.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/token_manager.h
        ${LOGOS_CPP_SDK_ROOT}/cpp/module_proxy.cpp
        ${LOGOS_CPP_SDK_ROOT}/cpp/module_proxy.h
    )
endif()

# Create the plugin library
add_library(blockchain_ui SHARED ${SOURCES})

# Set output name without lib prefix
set_target_properties(blockchain_ui PROPERTIES
    PREFIX ""
    OUTPUT_NAME "blockchain_ui"
)

# Include directories
target_include_directories(blockchain_ui PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_BINARY_DIR}
)

# Add include directories based on layout type
if(_liblogos_is_source)
    target_include_directories(blockchain_ui PRIVATE ${LOGOS_LIBLOGOS_ROOT})
else()
    target_include_directories(blockchain_ui PRIVATE ${LOGOS_LIBLOGOS_ROOT}/include)
endif()

if(_cpp_sdk_is_source)
    target_include_directories(blockchain_ui PRIVATE 
        ${LOGOS_CPP_SDK_ROOT}/cpp
    )
else()
    target_include_directories(blockchain_ui PRIVATE 
        ${LOGOS_CPP_SDK_ROOT}/include
        ${LOGOS_CPP_SDK_ROOT}/include/cpp
        ${LOGOS_CPP_SDK_ROOT}/include/core
    )
endif()

# Link against libraries
target_link_libraries(blockchain_ui PRIVATE 
    Qt6::Core
    Qt6::Widgets
    Qt6::RemoteObjects
    Qt6::Quick
    Qt6::QuickWidgets
    component-interfaces
)

# When using installed SDK layout (e.g. Nix), link the pre-built SDK library
if(NOT _cpp_sdk_is_source)
    find_library(LOGOS_SDK_LIB logos_sdk PATHS ${LOGOS_CPP_SDK_ROOT}/lib NO_DEFAULT_PATH)
    if(LOGOS_SDK_LIB)
        target_link_libraries(blockchain_ui PRIVATE ${LOGOS_SDK_LIB})
    else()
        message(FATAL_ERROR "logos_sdk library not found in ${LOGOS_CPP_SDK_ROOT}/lib - required when using installed SDK layout")
    endif()
endif()

# Link against Abseil libraries if found
find_package(absl QUIET)
if(absl_FOUND)
    target_link_libraries(blockchain_ui PRIVATE
        absl::base
        absl::strings
        absl::log
        absl::check
    )
endif()

# Set common properties for both platforms
set_target_properties(blockchain_ui PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/modules"  # For Windows .dll
    BUILD_WITH_INSTALL_RPATH TRUE
    SKIP_BUILD_RPATH FALSE)

if(APPLE)
    # macOS specific settings
    set_target_properties(blockchain_ui PROPERTIES
        INSTALL_RPATH "@loader_path"
        INSTALL_NAME_DIR "@rpath"
        BUILD_WITH_INSTALL_NAME_DIR TRUE)
    
    add_custom_command(TARGET blockchain_ui POST_BUILD
        COMMAND install_name_tool -id "@rpath/blockchain_ui.dylib" $<TARGET_FILE:blockchain_ui>
        COMMENT "Updating library paths for macOS"
    )
else()
    # Linux specific settings
    set_target_properties(blockchain_ui PROPERTIES
        INSTALL_RPATH "$ORIGIN"
        INSTALL_RPATH_USE_LINK_PATH FALSE)
endif()

install(TARGETS blockchain_ui
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
    RUNTIME DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}/logos/modules
)

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/metadata.json
    DESTINATION ${CMAKE_INSTALL_DATADIR}/logos-blockchain-ui
)

# Print status messages
message(STATUS "Blockchain UI Plugin configured successfully")
