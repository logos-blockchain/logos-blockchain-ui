{
  description = "Blockchain UI plugin for the Logos application";

  # Pull pre-built artifacts from the self-hosted Logos Attic cache(Nix binary cache).
  nixConfig = {
    extra-substituters = [ "https://cache.nix.logos.co/public" ];
    extra-trusted-public-keys = [ "public:l4HrXgL4nw246+LBh2SOJyhz64BoGegOYLheT/iIAPU=" ];
  };

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
    # The host provides these controls; standalone QML tests need their source.
    logos-design-system = {
      url = "github:logos-co/logos-design-system";
      flake = false;
    };
    nix-bundle-lgx.url = "github:logos-co/nix-bundle-lgx";
    # TODO: drop the ref once logos-blockchain-module#83 (powConfigure) is merged.
    blockchain_module.url = "github:logos-blockchain/logos-blockchain-module";
    # TODO: use master after the SQL module and C bindings PRs merge.
    sql_module.url = "github:logos-blockchain/logos-blockchain-module/feat/logos-sql-module";
    sql_module.inputs.logos-module-builder.follows = "logos-module-builder";
    sql_module.inputs.logos-blockchain.url = "github:logos-blockchain/logos-blockchain/feat/logos-sql-c-bindings";
    # TODO(logos-co/logos-liblogos#219): here only to sample the node module's
    # CPU and memory. liblogos measures both already but exposes them to hosts
    # alone, so this app resolves the PID through modules_state and samples it
    # with the same library liblogos uses. Goes away with the input, the
    # external_libraries entry and EXTERNAL_LIBS in CMakeLists.txt.
    process-stats.url = "github:logos-co/process-stats";
  };

  outputs = inputs@{ logos-module-builder, ... }:
    let
      blockchainUi = logos-module-builder.lib.mkLogosQmlModule {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = inputs;

        externalLibInputs = {
          process_stats = inputs.process-stats;
        };
      };
      sqlUi = logos-module-builder.lib.mkLogosQmlModule {
        src = ./sql;
        configFile = ./sql/metadata.json;
        flakeInputs = inputs // {
          # The SQL module's packages and metadata live below the repository root.
          sql_module = inputs.sql_module.sql // { outPath = "${inputs.sql_module}/sql"; };
        };
      };
      nixpkgs = logos-module-builder.inputs.nixpkgs;
      # The QML builder runs Basecamp .mjs tests, not these C++/QML QtTest suites.
      sqlTests = system:
        let pkgs = import nixpkgs { inherit system; };
        in pkgs.stdenv.mkDerivation {
          pname = "sql-explorer-tests";
          version = "0.1.0";
          src = ./sql;
          nativeBuildInputs = [ pkgs.cmake ];
          buildInputs = [ pkgs.qt6.qtbase pkgs.qt6.qtremoteobjects pkgs.qt6.qtdeclarative pkgs.qt6.qtsvg ];
          dontWrapQtApps = true;
          cmakeDir = "../tests";
          doCheck = true;
          checkPhase = ''
            export QT_QPA_PLATFORM=offscreen
            export QT_QUICK_BACKEND=software
            export QT_QUICK_CONTROLS_STYLE=Basic
            export QML_IMPORT_PATH=${inputs.logos-design-system}/src/qml:${pkgs.qt6.qtdeclarative}/lib/qt-6/qml:${pkgs.qt6.qtbase}/lib/qt-6/qml
            ctest --output-on-failure
          '';
          installPhase = "mkdir -p $out; touch $out/passed";
        };
    in blockchainUi // {
      sql = sqlUi;
      packages = nixpkgs.lib.mapAttrs (system: packages: packages // {
        sql = sqlUi.packages.${system}.default;
        sql-lgx = sqlUi.packages.${system}.lgx;
        sql-install = sqlUi.packages.${system}.install;
        sql-unit-tests = sqlTests system;
      }) blockchainUi.packages;
      apps = nixpkgs.lib.mapAttrs (system: apps: apps // {
        sql = sqlUi.apps.${system}.default;
      }) blockchainUi.apps;
      devShells = nixpkgs.lib.mapAttrs (system: shells: shells // {
        sql = sqlUi.devShells.${system}.default;
      }) blockchainUi.devShells;
    };
}
