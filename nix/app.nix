# Builds the logos-blockchain-ui-app standalone application
{ pkgs, common, src, logosLiblogos, logosBlockchainModule, logosCapabilityModule, logosBlockchainUI, logosDesignSystem }:

pkgs.stdenv.mkDerivation rec {
  pname = "logos-blockchain-ui-app";
  version = common.version;
  
  inherit src;
  inherit (common) buildInputs meta;
  
  nativeBuildInputs = common.nativeBuildInputs ++ [ pkgs.patchelf pkgs.removeReferencesTo ];
  
  # Provide Qt/GL runtime paths so the wrapper can inject them
  qtLibPath = pkgs.lib.makeLibraryPath (
    [
      pkgs.qt6.qtbase
      pkgs.qt6.qtremoteobjects
      pkgs.zstd
      pkgs.krb5
      pkgs.zlib
      pkgs.glib
      pkgs.stdenv.cc.cc
      pkgs.freetype
      pkgs.fontconfig
    ]
    ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
      pkgs.libglvnd
      pkgs.mesa.drivers
      pkgs.xorg.libX11
      pkgs.xorg.libXext
      pkgs.xorg.libXrender
      pkgs.xorg.libXrandr
      pkgs.xorg.libXcursor
      pkgs.xorg.libXi
      pkgs.xorg.libXfixes
      pkgs.xorg.libxcb
    ]
  );
  qtPluginPath = "${pkgs.qt6.qtbase}/lib/qt-6/plugins";
  qmlImportPath = "${placeholder "out"}/lib:${pkgs.qt6.qtbase}/lib/qt-6/qml";
  
  # This is a GUI application, enable Qt wrapping
  dontWrapQtApps = false;
  
  # This is an aggregate runtime layout; avoid stripping to prevent hook errors
  dontStrip = true;
  
  # Ensure proper Qt environment setup via wrapper
  qtWrapperArgs = [
    "--prefix" "LD_LIBRARY_PATH" ":" qtLibPath
    "--prefix" "QT_PLUGIN_PATH" ":" qtPluginPath
    "--prefix" "QML2_IMPORT_PATH" ":" qmlImportPath
  ];
  
  preConfigure = ''
    runHook prePreConfigure
    export MACOSX_DEPLOYMENT_TARGET=12.0
    runHook postPreConfigure
  '';
  
  # Additional environment variables for Qt and RPATH cleanup
  preFixup = ''
    runHook prePreFixup
    
    # Set up Qt environment variables
    export QT_PLUGIN_PATH="${pkgs.qt6.qtbase}/lib/qt-6/plugins"
    export QML_IMPORT_PATH="${pkgs.qt6.qtbase}/lib/qt-6/qml"
    
    # Remove any remaining references to /build/ in binaries and set proper RPATH
    find $out -type f -executable -exec sh -c '
      if file "$1" | grep -q "ELF.*executable"; then
        # Use patchelf to clean up RPATH if it contains /build/
        if patchelf --print-rpath "$1" 2>/dev/null | grep -q "/build/"; then
          echo "Cleaning RPATH for $1"
          patchelf --remove-rpath "$1" 2>/dev/null || true
        fi
        # Set proper RPATH for the main binary
        if echo "$1" | grep -q "/logos-blockchain-ui-app$"; then
          echo "Setting RPATH for $1"
          patchelf --set-rpath "$out/lib" "$1" 2>/dev/null || true
        fi
      fi
    ' _ {} \;
    
    # Also clean up shared libraries
    find $out -name "*.so" -exec sh -c '
      if patchelf --print-rpath "$1" 2>/dev/null | grep -q "/build/"; then
        echo "Cleaning RPATH for $1"
        patchelf --remove-rpath "$1" 2>/dev/null || true
      fi
    ' _ {} \;
    
    runHook prePostFixup
  '';
  
  configurePhase = ''
    runHook preConfigure
    
    echo "Configuring logos-blockchain-ui-app..."

    test -d "${logosLiblogos}" || (echo "liblogos not found" && exit 1)
    test -d "${logosBlockchainModule}" || (echo "blockchain-module not found" && exit 1)
    test -d "${logosCapabilityModule}" || (echo "capability-module not found" && exit 1)
    test -d "${logosBlockchainUI}" || (echo "blockchain-ui not found" && exit 1)
    test -d "${logosDesignSystem}" || (echo "logos-design-system not found" && exit 1)
    
    cmake -S app -B build \
      -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 \
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=FALSE \
      -DCMAKE_INSTALL_RPATH="" \
      -DCMAKE_SKIP_BUILD_RPATH=TRUE \
      -DLOGOS_LIBLOGOS_ROOT=${logosLiblogos}
    
    runHook postConfigure
  '';
  
  buildPhase = ''
    runHook preBuild
    
    cmake --build build
    echo "logos-blockchain-ui-app built successfully!"
    
    runHook postBuild
  '';
  
  installPhase = ''
    runHook preInstall
    
    # Create output directories
    mkdir -p $out/bin $out/lib $out/modules
    
    # Install our app binary
    if [ -f "build/bin/logos-blockchain-ui-app" ]; then
      cp build/bin/logos-blockchain-ui-app "$out/bin/"
      echo "Installed logos-blockchain-ui-app binary"
    fi
    
    # Copy the core binaries from liblogos
    if [ -f "${logosLiblogos}/bin/logoscore" ]; then
      cp -L "${logosLiblogos}/bin/logoscore" "$out/bin/"
      echo "Installed logoscore binary"
    fi
    if [ -f "${logosLiblogos}/bin/logos_host" ]; then
      cp -L "${logosLiblogos}/bin/logos_host" "$out/bin/"
      echo "Installed logos_host binary"
    fi
    
    # Copy required shared libraries from liblogos
    if ls "${logosLiblogos}/lib/"liblogos_core.* >/dev/null 2>&1; then
      cp -L "${logosLiblogos}/lib/"liblogos_core.* "$out/lib/" || true
    fi
    
    # Determine platform-specific plugin extension
    OS_EXT="so"
    case "$(uname -s)" in
      Darwin) OS_EXT="dylib";;
      Linux) OS_EXT="so";;
      MINGW*|MSYS*|CYGWIN*) OS_EXT="dll";;
    esac

    # Copy module plugins into the modules directory
    if [ -f "${logosCapabilityModule}/lib/capability_module_plugin.$OS_EXT" ]; then
      cp -L "${logosCapabilityModule}/lib/capability_module_plugin.$OS_EXT" "$out/modules/"
    fi
    if [ -f "${logosBlockchainModule}/lib/liblogos-blockchain-module.$OS_EXT" ]; then
      cp -L "${logosBlockchainModule}/lib/liblogos-blockchain-module.$OS_EXT" "$out/modules/"
    fi
    
    # Copy liblogos_blockchain library to modules directory (needed by blockchain module)
    if [ -f "${logosBlockchainModule}/lib/liblogos_blockchain.$OS_EXT" ]; then
      cp -L "${logosBlockchainModule}/lib/liblogos_blockchain.$OS_EXT" "$out/modules/"
    fi

    # Copy blockchain_ui Qt plugin to root directory (not modules, as it's loaded differently)
    if [ -f "${logosBlockchainUI}/lib/blockchain_ui.$OS_EXT" ]; then
      cp -L "${logosBlockchainUI}/lib/blockchain_ui.$OS_EXT" "$out/"
    fi

    # Copy design system QML modules (Logos.Theme, Logos.Controls) for runtime
    if [ -d "${logosDesignSystem}/lib/Logos/Theme" ]; then
      mkdir -p "$out/lib/Logos"
      cp -R "${logosDesignSystem}/lib/Logos/Theme" "$out/lib/Logos/"
      echo "Copied Logos.Theme to lib/Logos/Theme/"
    fi
    if [ -d "${logosDesignSystem}/lib/Logos/Controls" ]; then
      mkdir -p "$out/lib/Logos"
      cp -R "${logosDesignSystem}/lib/Logos/Controls" "$out/lib/Logos/"
      echo "Copied Logos.Controls to lib/Logos/Controls/"
    fi

    cat > $out/README.txt <<EOF
Logos Blockchain UI App
=======================
liblogos: ${logosLiblogos}
blockchain-module: ${logosBlockchainModule}
capability-module: ${logosCapabilityModule}
blockchain-ui: ${logosBlockchainUI}
design-system: ${logosDesignSystem}

Layout:
  bin/logos-blockchain-ui-app
  lib/
  modules/
  blockchain_ui.$OS_EXT
EOF
    
    runHook postInstall
  '';
}
