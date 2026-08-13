cmake_minimum_required(VERSION 3.14)
project(BlockchainUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# Universal UI module: we write the .rep (the view contract) and the *Backend
# class only. REP_FILE runs repc; the *Interface / *Plugin glue
# (Q_PLUGIN_METADATA, initLogos wiring, QtRO registration, setBackend) is
# generated into generated_code/ and compiled automatically.
logos_module(
    NAME blockchain_ui
    REP_FILE src/BlockchainBackend.rep
    SOURCES
        src/BlockchainBackend.h
        src/BlockchainBackend.cpp
        src/AccountsModel.h
        src/AccountsModel.cpp
        src/BlockModel.h
        src/BlockModel.cpp
    INCLUDE_DIRS
        src
    FIND_PACKAGES
        Qt6Gui
    LINK_LIBRARIES
        Qt6::Gui
)
