{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder/38ddf92c1f240f4e420d300a1fbabb1609d5db01";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    # v0.0.3
    liblogos_blockchain_module.url = "github:logos-blockchain/logos-blockchain-module/b9d71177125a760526a5df7948c4e0a67a1716ac";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
