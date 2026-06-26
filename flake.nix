{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/92ef691ea72844134f6c68fb447d37f855fc9690";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    # v0.0.3
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module?ref=0.1.3-rc.13";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
