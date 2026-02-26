# Builds the logos-blockchain-ui library
{ pkgs, common, src, logosBlockchainModule }:

pkgs.stdenv.mkDerivation {
  pname = "${common.pname}-lib";
  version = common.version;

  inherit src;
  inherit (common) buildInputs cmakeFlags meta env;
  nativeBuildInputs = common.nativeBuildInputs;

  # Library (Qt plugin), not an app — no Qt wrapper
  dontWrapQtApps = true;

  configurePhase = ''
    runHook preConfigure
    cmake -S . -B build \
      -GNinja \
      -DCMAKE_BUILD_TYPE=Release \
      ''${cmakeFlags}
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    cmake --build build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib
    if [ -f build/modules/blockchain_ui.dylib ]; then
      cp build/modules/blockchain_ui.dylib $out/lib/
    elif [ -f build/modules/blockchain_ui.so ]; then
      cp build/modules/blockchain_ui.so $out/lib/
    else
      echo "Error: No library file found in build/modules/"
      ls -la build/modules/ 2>/dev/null || true
      exit 1
    fi

    # Copy circuits from blockchain module so result/lib/circuits is available
    if [ -d "${logosBlockchainModule}/share/circuits" ]; then
      cp -r "${logosBlockchainModule}/share/circuits" $out/modules/
    fi

    runHook postInstall
  '';
}
