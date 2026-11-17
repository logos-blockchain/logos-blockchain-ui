cmake_minimum_required(VERSION 3.14)
project(BlockchainUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" METADATA_JSON)
string(JSON MODULE_NAME GET ${METADATA_JSON} name)

logos_module(
    NAME ${MODULE_NAME}
    REP_FILE src/BlockchainBackend.rep
    SOURCES
        src/BlockchainBackend.h
        src/BlockchainBackend.cpp
        src/AccountsModel.h
        src/AccountsModel.cpp
        src/BlockModel.h
        src/BlockModel.cpp
        src/ClaimLedger.h
        src/ClaimLedger.cpp
        src/ClaimsModel.h
        src/ClaimsModel.cpp
    INCLUDE_DIRS
        src
    # TODO(logos-co/logos-liblogos#219): only for the node module's CPU and
    # memory figures — the library behind liblogos's own host-side stats, used
    # here because those stats are not exposed to modules. Goes with the flake
    # input and the metadata.json entry when that lands.
    EXTERNAL_LIBS
        process_stats
    FIND_PACKAGES
        Qt6Gui
    LINK_LIBRARIES
        Qt6::Gui
)
