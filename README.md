# logos-blockchain-ui-new

A Qt UI plugin for the Logos Blockchain Module, providing a graphical interface to control and monitor the Logos blockchain node.

## Features

- Start/Stop blockchain node
- Configure node parameters (config path, deployment)
- Check wallet balances
- Monitor node status and information

## How to Build

### Using Nix (Recommended)

#### Build Complete UI Plugin

```bash
# Build everything (default)
nix build

# Or explicitly
nix build '.#default'
```

The result will include:
- `/lib/blockchain_ui.dylib` (or `.so` on Linux) - The Blockchain UI plugin

#### Build Individual Components

```bash
# Build only the library (plugin)
nix build '.#lib'

# Build the standalone Qt application
nix build '.#app'
```

#### Development Shell

```bash
# Enter development shell with all dependencies
nix develop
```

**Note:** In zsh, you need to quote the target (e.g., `'.#default'`) to prevent glob expansion.

If you don't have flakes enabled globally, add experimental flags:

```bash
nix build --extra-experimental-features 'nix-command flakes'
```

The compiled artifacts can be found at `result/`

#### Running the Standalone App

After building the app with `nix build '.#app'`, you can run it:

```bash
# Run the standalone Qt application
./result/bin/logos-blockchain-ui-app
```

The app will automatically load the required modules (capability_module, liblogos_blockchain_module) and the blockchain_ui Qt plugin. All dependencies are bundled in the Nix store layout.

#### Nix Organization

The nix build system is organized into modular files in the `/nix` directory:
- `nix/default.nix` - Common configuration (dependencies, flags, metadata)
- `nix/lib.nix` - UI plugin compilation
- `nix/app.nix` - Standalone Qt application compilation

## Output Structure

When built with Nix:

**Library build (`nix build '.#lib'`):**
```
result/
└── lib/
    └── blockchain_ui.dylib    # Logos Blockchain UI plugin
```

**App build (`nix build '.#app'`):**
```
result/
├── bin/
│   ├── logos-blockchain-ui-app    # Standalone Qt application
│   ├── logos_host                 # Logos host executable (for plugins)
│   └── logoscore                  # Logos core executable
├── lib/
│   ├── liblogos_core.dylib        # Logos core library
│   ├── liblogos_sdk.dylib         # Logos SDK library
│   └── Logos/DesignSystem/        # QML design system
├── modules/
│   ├── capability_module_plugin.dylib
│   ├── liblogos_blockchain_module.dylib
│   └── liblogos_blockchain.dylib
└── blockchain_ui.dylib            # Qt plugin (loaded by app)
```

## Configuration

### Blockchain Node Configuration

The blockchain node can be configured in two ways:

1. **Via UI**: Enter the config path in the "Config Path" field
2. **Via Environment Variable**: Set `LB_CONFIG_PATH` to your configuration file path

Example configuration file can be found in the logos-blockchain-module repository at `config/node_config.yaml`.

### QML Hot Reload

During development, you can enable QML hot reload by setting an environment variable:
```bash
export BLOCKCHAIN_UI_QML_PATH=/path/to/logos-blockchain-ui/src/qml
```
This allows you to edit the QML file and see changes by reloading the plugin without recompiling.