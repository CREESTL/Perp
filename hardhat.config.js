/**
 * @type import('hardhat/config').HardhatUserConfig
 */
//  require('dotenv').config();
//  const { REPORT_GAS } = process.env;
//  require('@nomiclabs/hardhat-ethers');
//  require("@nomiclabs/hardhat-waffle");
// //  require('solidity-coverage');
// //  require('hardhat-gas-reporter');
// //  require("@nomiclabs/hardhat-etherscan");
 
//  module.exports = {
//    gasReporter: {
//      enabled: REPORT_GAS === "true" ? true : false
//    },
//    solidity: {
//      version: "0.8.12",
//    },
//    networks: {
//     hardhat: {
//       allowUnlimitedContractSize: true
//     }
//   },
// }
// */
// require('dotenv').config();
const { REPORT_GAS } = process.env;
require('@nomiclabs/hardhat-ethers');
require("@nomiclabs/hardhat-waffle");

// require('solidity-coverage');
// require('hardhat-gas-reporter');
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
    enabled: REPORT_GAS === "true" ? true : false
  },
  solidity: {
    compilers: [{
      version: "0.8.12",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        }
      }
    }]
  }
};
 