{
  description = "Blockchain UI plugin for the Logos application";

  # Pull pre-built artifacts from the self-hosted Logos Attic cache(Nix binary cache).
  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    # Pinned to logos-blockchain-module#112 (Blend core APIs); back to master once it merges.
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module/cc12da54be08e3db05ce0ce09c29a9c90daf8694";
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

      externalLibInputs = {
        process_stats = inputs.process-stats;
      };
    };
}
