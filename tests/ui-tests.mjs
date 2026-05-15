import { resolve } from "node:path";

// CI sets LOGOS_QT_MCP automatically; for interactive use:
//   nix build .#test-framework -o result-mcp
const root =
  process.env.LOGOS_QT_MCP ||
  new URL("../result-mcp", import.meta.url).pathname;
const { test, run } = await import(resolve(root, "test-framework/framework.mjs"));

// Smoke test: the blockchain UI module must load in the host
// (logos-standalone-app / logos-basecamp), connect to its process-isolated
// C++ backend over Qt Remote Objects, and render the QML view — even when the
// backend node module is not running yet (the node is started from this UI).
test("blockchain_ui: backend connects and config view renders", async (app) => {
  await app.waitFor(
    async () => {
      // Once the BlockchainBackend replica is Valid, the loading state is
      // replaced by the ConfigChoiceView. This static label proves the QML
      // (including the Logos.Theme / Logos.Controls design-system imports)
      // loaded and the backend replica connected.
      await app.expectTexts(["Choose how to set up your node config"]);
    },
    {
      timeout: 30000,
      interval: 1000,
      description: "blockchain UI to load and backend to connect",
    }
  );
});

test("blockchain_ui: config setup actions are visible", async (app) => {
  await app.expectTexts(["Generate config", "Set path to config"]);
});

run();
