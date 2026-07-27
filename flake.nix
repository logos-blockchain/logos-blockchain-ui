{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/0.2.4";
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module?ref=0.2.0";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
