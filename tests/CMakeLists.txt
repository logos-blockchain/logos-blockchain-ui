cmake_minimum_required(VERSION 3.14)
project(BlockchainUiTests LANGUAGES CXX)

include(LogosTest)

logos_test(
    NAME blockchain_ui_tests
    MODULE_SOURCES
        ../src/ReferralSigning.cpp
    TEST_SOURCES
        main.cpp
        test_referral_signing.cpp
    EXTRA_INCLUDES
        ${CMAKE_CURRENT_SOURCE_DIR}/../src
)

find_package(OpenSSL REQUIRED)
target_link_libraries(blockchain_ui_tests PRIVATE OpenSSL::Crypto)
