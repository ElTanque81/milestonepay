require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

// Optional: compile offline with the bundled solc-js (set USE_LOCAL_SOLC=1)
if (process.env.USE_LOCAL_SOLC === "1") {
  const { subtask } = require("hardhat/config");
  const { TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD } = require("hardhat/builtin-tasks/task-names");
  subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD, async () => {
    const solc = require("solc");
    return {
      compilerPath: require.resolve("solc/soljson.js"),
      isSolcJs: true,
      version: solc.version().split("+")[0],
      longVersion: solc.version(),
    };
  });
}

const { PORTALDOT_RPC_URL, PORTALDOT_CHAIN_ID, PRIVATE_KEY } = process.env;

module.exports = {
  solidity: {
    version: "0.8.24",
    settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: "paris" },
  },
  networks: {
    portaldot: {
      url: PORTALDOT_RPC_URL || "https://test-evm-rpc-v3.portaldot.dev",
      chainId: Number(PORTALDOT_CHAIN_ID || 420420777),
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],
    },
  },
};
