/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 require('@nomiclabs/hardhat-ethers');
 require("@nomiclabs/hardhat-waffle");
 require("@nomiclabs/hardhat-etherscan");
 
 require('solidity-coverage');
 require('hardhat-gas-reporter');
 require("dotenv").config()
 
 ALCHEMY_ID = process.env.ALCHEMY_KEY
 ETHERSCAN_ID = process.env.ETHERSCAN_ID
 PRIVATE_KEY = process.env.PRIVATE_KEY
 
 module.exports = {
   networks: {
     hardhat: {
       allowUnlimitedContractSize: false
     },
     rinkeby: {
       url: 'https://eth-rinkeby.alchemyapi.io/v2/' + ALCHEMY_ID,
       chainId: 4,
       gasPrice: 7000000000,
       accounts: [`0x${PRIVATE_KEY}`]
     },
   },
   etherscan: {
     apiKey: ETHERSCAN_ID
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
  