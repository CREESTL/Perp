/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@nomiclabs/hardhat-ethers');
require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");

require('solidity-coverage');
require('hardhat-gas-reporter');

const mnemonic = fs.readFileSync('.secret').toString().trim();

module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: false
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/${process.env.ALCHEMY_ID}`,
      chainId: 4,
      gasPrice: 7000000000,
      accounts: {mnemonic: mnemonic}
    },
  },
  etherscan: {
    apiKey: `${process.env.ETHERSCAN_ID}`
  },
  gasReporter: {
    enabled: false,
  },
  solidity: {
    compilers: [{
      version: "0.8.0",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }]
  }
};
 