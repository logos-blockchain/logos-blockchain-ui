{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    # Rev-pinned deliberately: the generated-view-plugin support this module now
    # depends on lives on logos-module-builder's feat/sdk-codegen-b4-qt-host-repoint
    # branch, not on its master, so a bare url would relock to master and drop it.
    logos-module-builder.url = "github:logos-co/logos-module-builder/c60d4a9cf32cb5281909e53159c9c4cfeb993847";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
