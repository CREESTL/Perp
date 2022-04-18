/**
 * @type import('hardhat/config').HardhatUserConfig
 */
require('@nomiclabs/hardhat-ethers');
require("@nomiclabs/hardhat-waffle");

require('solidity-coverage');
require('hardhat-gas-reporter');
// require("@nomiclabs/hardhat-etherscan");

module.exports = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true
    },
    rinkeby: {
      url: `https://eth-rinkeby.alchemyapi.io/v2/oRFHpW926CHVKUjXbSuD9oLG4EQLfS9u`,
      chainId: 4,
      gasPrice: 7000000000,
      accounts: {mnemonic: "escape asthma range van match denial settle maze daughter angle curve portion"}
    },
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
 