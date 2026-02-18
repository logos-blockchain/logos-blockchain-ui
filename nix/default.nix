# Common build configuration shared across all packages
{ pkgs, logosSdk, logosLiblogos }:

{
  pname = "logos-blockchain-ui";
  version = "1.0.0";
  
  # Common native build inputs
  nativeBuildInputs = [ 
    pkgs.cmake 
    pkgs.ninja 
    pkgs.pkg-config
    pkgs.qt6.wrapQtAppsHook
  ];
  
  # Common runtime dependencies
  buildInputs = [ 
    pkgs.qt6.qtbase 
    pkgs.qt6.qtremoteobjects 
    pkgs.zstd
    pkgs.krb5
    pkgs.abseil-cpp
  ];
  
  # Common CMake flags
  cmakeFlags = [ 
    "-GNinja"
    "-DLOGOS_CPP_SDK_ROOT=${logosSdk}"
    "-DLOGOS_LIBLOGOS_ROOT=${logosLiblogos}"
  ];
  
  env = {
    LOGOS_LIBLOGOS_ROOT = "${logosLiblogos}";
  };
  
  # Metadata
  meta = with pkgs.lib; {
    description = "Logos Blockchain UI - A Qt UI plugin for Logos Blockchain Module";
    platforms = platforms.unix;
  };
}
