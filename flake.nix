{
  description = "Blockchain UI plugin for the Logos application";

  inputs = {
    # Promoted to direct inputs so they can be overridden with one --override-input each.
    logos-cpp-sdk.url             = "github:logos-co/logos-cpp-sdk";
    logos-module.url              = "github:logos-co/logos-module";
    logos-liblogos.url            = "github:logos-co/logos-liblogos";
    logos-capability-module.url   = "github:logos-co/logos-capability-module";
    logos-package-manager.url     = "github:logos-co/logos-package-manager";
    process-stats.url             = "github:logos-co/process-stats";
    logos-view-module-runtime.url = "github:logos-co/logos-view-module-runtime";
    logos-standalone-app.url      = "github:logos-co/logos-standalone-app";
    logos-plugin-qt.url           = "github:logos-co/logos-plugin-qt";

    nix-bundle-lgx.url            = "github:logos-co/nix-bundle-lgx";

    # All nixpkgs in the closure must come from logos-cpp-sdk's logos-nix to keep one Qt.
    nixpkgs.follows = "logos-cpp-sdk/logos-nix/nixpkgs";

    # ── Force every direct input's nixpkgs to the unified one ──
    logos-module.inputs.nixpkgs.follows              = "nixpkgs";
    logos-liblogos.inputs.nixpkgs.follows            = "nixpkgs";
    logos-capability-module.inputs.nixpkgs.follows   = "nixpkgs";
    logos-package-manager.inputs.nixpkgs.follows     = "nixpkgs";
    process-stats.inputs.nixpkgs.follows             = "nixpkgs";
    logos-view-module-runtime.inputs.nixpkgs.follows = "nixpkgs";
    logos-standalone-app.inputs.nixpkgs.follows      = "nixpkgs";
    logos-plugin-qt.inputs.nixpkgs.follows           = "nixpkgs";
    nix-bundle-lgx.inputs.nixpkgs.follows            = "nixpkgs";
    logos-module-builder.inputs.nixpkgs.follows      = "nixpkgs";

    # ── logos-module-builder: rewire its logos-* deps to our top-level pins ──
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    logos-module-builder.inputs.logos-cpp-sdk.follows         = "logos-cpp-sdk";
    logos-module-builder.inputs.logos-module.follows          = "logos-module";
    logos-module-builder.inputs.logos-plugin-qt.follows       = "logos-plugin-qt";
    logos-module-builder.inputs.logos-plugin-core.follows     = "logos-plugin-qt";
    logos-module-builder.inputs.logos-standalone-app.follows  = "logos-standalone-app";
    logos-module-builder.inputs.nix-bundle-lgx.follows        = "nix-bundle-lgx";

    # ── logos-standalone-app: rewire its logos-* deps too ──
    logos-standalone-app.inputs.logos-cpp-sdk.follows             = "logos-cpp-sdk";
    logos-standalone-app.inputs.logos-liblogos.follows            = "logos-liblogos";
    logos-standalone-app.inputs.logos-capability-module.follows   = "logos-capability-module";
    logos-standalone-app.inputs.logos-view-module-runtime.follows = "logos-view-module-runtime";
    logos-standalone-app.inputs.nix-bundle-lgx.follows            = "nix-bundle-lgx";

    # ── logos-liblogos: rewire its logos-* deps ──
    logos-liblogos.inputs.logos-cpp-sdk.follows           = "logos-cpp-sdk";
    logos-liblogos.inputs.logos-module.follows            = "logos-module";
    logos-liblogos.inputs.logos-capability-module.follows = "logos-capability-module";
    logos-liblogos.inputs.logos-package-manager.follows   = "logos-package-manager";
    logos-liblogos.inputs.process-stats.follows           = "process-stats";

    logos-capability-module.inputs.logos-cpp-sdk.follows = "logos-cpp-sdk";
    logos-capability-module.inputs.logos-module.follows  = "logos-module";

    logos-plugin-qt.inputs.logos-module.follows = "logos-module";

    liblogos_blockchain_module.url = "github:logos-blockchain/logos-blockchain-module/09eda0211df54b45d88d912aea28498d427ddada";
    liblogos_blockchain_module.inputs.logos-module-builder.follows = "logos-module-builder";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    logos-module-builder.lib.mkLogosQmlModule {
      src = ./.;
      configFile = ./metadata.json;
      flakeInputs = inputs;
    };
}
