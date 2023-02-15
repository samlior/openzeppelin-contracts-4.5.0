/// ENVVAR
// - CI:                output gas report to file instead of stdout
// - COVERAGE:          enable coverage report
// - ENABLE_GAS_REPORT: enable gas report
// - COMPILE_MODE:      production modes enables optimizations (default: development)
// - COMPILE_VERSION:   compiler version (default: 0.8.9)
// - COINMARKETCAP:     coinmarkercat api key for USD value in gas report

const fs = require("fs");
const path = require("path");
const argv = require("yargs/yargs")()
  .env("")
  .options({
    ci: {
      type: "boolean",
      default: false,
    },
    coverage: {
      type: "boolean",
      default: false,
    },
    gas: {
      alias: "enableGasReport",
      type: "boolean",
      default: false,
    },
    mode: {
      alias: "compileMode",
      type: "string",
      choices: ["production", "development"],
      default: "development",
    },
    compiler: {
      alias: "compileVersion",
      type: "string",
      default: "0.8.4",
    },
    coinmarketcap: {
      alias: "coinmarketcapApiKey",
      type: "string",
    },
  }).argv;

require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-etherscan");

if (argv.enableGasReport) {
  require("hardhat-gas-reporter");
}

for (const f of fs.readdirSync(path.join(__dirname, "hardhat"))) {
  require(path.join(__dirname, "hardhat", f));
}

const withOptimizations = argv.enableGasReport || argv.compileMode === "production";

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    version: argv.compiler,
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      blockGasLimit: 10000000,
      allowUnlimitedContractSize: !withOptimizations,
    },
    avax: {
      url: "https://api.avax.network/ext/bc/C/rpc",
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
    },
    arb: {
      url: "https://arb1.arbitrum.io/rpc",
    },
  },
  gasReporter: {
    currency: "USD",
    outputFile: argv.ci ? "gas-report.txt" : undefined,
    coinmarketcap: argv.coinmarketcap,
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
    customChains: [
      {
        network: "avax",
        chainId: 43114,
        urls: {
          apiURL: "https://api.snowtrace.io/api",
          browserURL: "https://snowtrace.io",
        },
      },
      {
        network: "bsc",
        chainId: 56,
        urls: {
          apiURL: "https://api.bscscan.com/api",
          browserURL: "https://bscscan.com/",
        },
      },
      {
        network: "arb",
        chainId: 42161,
        urls: {
          apiURL: "https://api.arbiscan.io/api",
          browserURL: "https://arbiscan.io/",
        },
      },
    ],
  },
};

if (argv.coverage) {
  require("solidity-coverage");
  module.exports.networks.hardhat.initialBaseFeePerGas = 0;
}
