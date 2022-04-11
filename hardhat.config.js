/**
 * @type import('hardhat/config').HardhatUserConfig
 */
 require('dotenv').config();
 const { REPORT_GAS } = process.env;
 require('@nomiclabs/hardhat-ethers');
 require('solidity-coverage');
 require('hardhat-gas-reporter');
 require("@nomiclabs/hardhat-etherscan");
 
 module.exports = {
   gasReporter: {
     enabled: REPORT_GAS === "true" ? true : false
   },
   solidity: "0.8.12",
 };
 