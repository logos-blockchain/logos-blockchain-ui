{
  description = "Blockchain UI plugin for the Logos application";

  # Pull pre-built artifacts from the self-hosted Logos Attic cache(Nix binary cache).
  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    # TODO: back to the default branch once logos-co/logos-module-builder#284
    # (excludeSystems) is merged.
    logos-module-builder.url = "github:logos-co/logos-module-builder/feat/systems-opt-out";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module?ref=0.3.4";
    # TODO(logos-co/logos-liblogos#219): here only to sample the node module's
    # CPU and memory. liblogos measures both already but exposes them to hosts
    # alone, so this app resolves the PID through modules_state and samples it
    # with the same library liblogos uses. Goes away with the input, the
    # external_libraries entry and EXTERNAL_LIBS in CMakeLists.txt.
    process-stats.url = "github:logos-co/process-stats";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;

      # This module does not cross-build to Windows.
      excludeSystems = [ "x86_64-windows" ];

      externalLibInputs = {
        process_stats = inputs.process-stats;
      };
    };
}
