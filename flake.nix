{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/38ddf92c1f240f4e420d300a1fbabb1609d5db01";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    liblogos_blockchain_module.url = "github:logos-blockchain/logos-blockchain-module/ab733aa7074cf1992f605c203c3d6a7923602705";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
