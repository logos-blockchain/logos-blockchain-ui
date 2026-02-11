{
  description = "Logos Blockchain UI - A Qt UI plugin for Logos Blockchain Module";

  inputs = {
    # Follow the same nixpkgs as logos-liblogos to ensure compatibility
    nixpkgs.follows = "logos-liblogos/nixpkgs";
    logos-cpp-sdk.url = "github:logos-co/logos-cpp-sdk";
    logos-liblogos.url = "github:logos-co/logos-liblogos";
    logos-blockchain-module.url = "github:logos-co/logos-blockchain-module";
    logos-capability-module.url = "github:logos-co/logos-capability-module";
    logos-design-system.url = "github:logos-co/logos-design-system";
    logos-design-system.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, logos-cpp-sdk, logos-liblogos, logos-blockchain-module, logos-capability-module, logos-design-system }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        pkgs = import nixpkgs { inherit system; };
        logosSdk = logos-cpp-sdk.packages.${system}.default;
        logosLiblogos = logos-liblogos.packages.${system}.default;
        logosBlockchainModule = logos-blockchain-module.packages.${system}.default;
        logosCapabilityModule = logos-capability-module.packages.${system}.default;
        logosDesignSystem = logos-design-system.packages.${system}.default;
      });
    in
    {
      packages = forAllSystems ({ pkgs, logosSdk, logosLiblogos, logosBlockchainModule, logosCapabilityModule, logosDesignSystem }: 
        let
          # Common configuration
          common = import ./nix/default.nix { 
            inherit pkgs logosSdk logosLiblogos; 
          };
          src = ./.;
          
          # Library package (default blockchain-module has lib + include via symlinkJoin)
          lib = import ./nix/lib.nix { 
            inherit pkgs common src logosBlockchainModule logosSdk; 
          };
          
          # App package
          app = import ./nix/app.nix { 
            inherit pkgs common src logosLiblogos logosSdk logosBlockchainModule logosCapabilityModule logosDesignSystem;
            logosBlockchainUI = lib;
          };
        in
        {
          # Individual outputs
          logos-blockchain-ui-lib = lib;
          app = app;
          lib = lib;

          # Default package
          default = lib;
        }
      );

      devShells = forAllSystems ({ pkgs, logosSdk, logosLiblogos, logosBlockchainModule, logosCapabilityModule, logosDesignSystem }: {
        default = pkgs.mkShell {
          nativeBuildInputs = [
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
          ];
          buildInputs = [
            pkgs.qt6.qtbase
            pkgs.qt6.qtremoteobjects
            pkgs.zstd
            pkgs.krb5
            pkgs.abseil-cpp
          ];
          
          shellHook = ''
            export LOGOS_CPP_SDK_ROOT="${logosSdk}"
            export LOGOS_LIBLOGOS_ROOT="${logosLiblogos}"
            export LOGOS_DESIGN_SYSTEM_ROOT="${logosDesignSystem}"
            echo "Logos Blockchain UI development environment"
            echo "LOGOS_CPP_SDK_ROOT: $LOGOS_CPP_SDK_ROOT"
            echo "LOGOS_LIBLOGOS_ROOT: $LOGOS_LIBLOGOS_ROOT"
          '';
        };
      });
    };
}
