const delay = require('delay');
const { ethers } = require("hardhat");

// Need to be setted later:
// darkOracle — backend address
// oracle parameters — see setParams function in 

async function main() {
  // Need to be setted before production
  const darkOracle = ethers.constants.AddressZero
  const requestsPerFunding = 0
  const costPerRequest = 0
    
  // We get the contract to deploy
  const mock = await (await ethers.getContractFactory("MockToken")).deploy("Mock", "MCK", 18);
  const treasury = await (await ethers.getContractFactory("Treasury")).deploy();
  const trading = await (await ethers.getContractFactory("Trading")).deploy();
  const parifiPool = await (await ethers.getContractFactory("PoolParifi")).deploy(mock.address);
  const oracle = await (await ethers.getContractFactory("Oracle")).deploy();
  const factory = await (await ethers.getContractFactory("Factory")).deploy();
  const router = await (await ethers.getContractFactory("Router")).deploy();

  console.log("Deploy finished")
  console.log("Wait for configuration, please")

  await treasury.setRouter(router.address);
  await trading.setRouter(router.address);
  await parifiPool.setRouter(router.address);
  await oracle.setRouter(router.address);
  await oracle.setParams(requestsPerFunding, costPerRequest)
  await factory.setRouter(router.address);

  await router.setContracts(
    treasury.address,
    trading.address,
    parifiPool.address,
    oracle.address,
    darkOracle,
    factory.address
  )

  console.log("Configuration finished")
  console.log("Wait for verification, please")

  await delay(60000);
  try {
    await hre.run("verify:verify", {
      address: treasury.address,
    });
  } catch(error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: trading.address,
    });
  } catch(error) {
    console.error(error);
  } 
  try {
    await hre.run("verify:verify", {
      address: parifiPool.address,
      constructorArguments: [
        mock.address,
      ],
    });
  } catch(error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: oracle.address,
    });
  } catch(error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: factory.address,
    });
  } catch(error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: router.address,
    });
  } catch(error) {
    console.error(error);
  }

  console.log("Verification finished")

  console.log("Treasury deployed to:", treasury.address);
  console.log("Trading deployed to:", trading.address);
  console.log("Parifi Pool deployed to:", parifiPool.address);
  console.log("Oracle deployed to:", oracle.address);
  console.log("Factory deployed to:", factory.address);
  console.log("Router deployed to:", router.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
