cmake_minimum_required(VERSION 3.16)
project(SqlExplorerTests LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
enable_testing()
find_package(Qt6 REQUIRED COMPONENTS Core Test RemoteObjects QuickTest Qml)

add_executable(sql-explorer-tests
    test_explorer.cpp
    ../src/SqlBackend.cpp
    ../src/QueryResultModel.cpp
)
qt6_add_repc_sources(sql-explorer-tests ../src/SqlBackend.rep)
target_include_directories(sql-explorer-tests PRIVATE mocks ../src ${CMAKE_CURRENT_BINARY_DIR})
target_link_libraries(sql-explorer-tests PRIVATE Qt6::Core Qt6::Test Qt6::RemoteObjects)
add_test(NAME sql-explorer-tests COMMAND sql-explorer-tests)

add_executable(sql-explorer-qml-tests qml_test_main.cpp ../src/QueryResultModel.cpp)
target_include_directories(sql-explorer-qml-tests PRIVATE ../src)
target_link_libraries(sql-explorer-qml-tests PRIVATE Qt6::QuickTest Qt6::Qml)
target_compile_definitions(sql-explorer-qml-tests PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
add_test(NAME sql-explorer-qml-tests COMMAND sql-explorer-qml-tests)
