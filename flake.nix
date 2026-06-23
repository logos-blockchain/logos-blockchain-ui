{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/38ddf92c1f240f4e420d300a1fbabb1609d5db01";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    liblogos_blockchain_module.url = "github:logos-blockchain/logos-blockchain-module/4c8df124929c6e86d21e2f0db50a99dedee901b3";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
