{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    liblogos_blockchain_module.url = "github:logos-blockchain/logos-blockchain-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;

      # The blockchain module is a legacy Rust module that does not ship a
      # generated *_api.h header.  The logos-cpp-generator --general-only step
      # produces logos_sdk.h which #include's the missing header.  Create an
      # empty stub so compilation succeeds — we use the raw LogosAPIClient
      # interface directly instead of the generated type-safe wrappers.
      preConfigure = ''
        mkdir -p ./generated_code/include

        # The blockchain module is a legacy Rust module that does not ship a
        # generated *_api.h header.  Create a minimal stub so logos_sdk.h
        # compiles — we use the raw LogosAPIClient interface directly.
        for dir in ./generated_code/include ./generated_code; do
          if [ ! -f "$dir/liblogos_blockchain_module_api.h" ]; then
            cat > "$dir/liblogos_blockchain_module_api.h" << 'STUB'
        #pragma once
        #include "logos_api.h"
        class LiblogosBlockchainModule {
        public:
            explicit LiblogosBlockchainModule(LogosAPI*) {}
        };
        STUB
          fi
          if [ ! -f "$dir/liblogos_blockchain_module_api.cpp" ]; then
            echo "// Stub" > "$dir/liblogos_blockchain_module_api.cpp"
          fi
        done
      '';
    };
}
