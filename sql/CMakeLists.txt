cmake_minimum_required(VERSION 3.14)
project(SqlUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "Set LOGOS_MODULE_BUILDER_ROOT to build the SQL Explorer.")
endif()

logos_module(
    NAME sql_ui
    REP_FILE src/SqlBackend.rep
    SOURCES
        src/SqlPluginInterface.h
        src/SqlPlugin.h
        src/SqlPlugin.cpp
        src/SqlBackend.h
        src/SqlBackend.cpp
        src/QueryResultModel.h
        src/QueryResultModel.cpp
)
