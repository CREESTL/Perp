const delay = require("delay");
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Need to be setted later:
// darkOracle — backend address
// oracle parameters — see setParams function in

const TEST_CONFIG = require("./deployedContractsOutput.json");

async function main() {
  // Need to be setted before production
  const darkOracle = ethers.constants.AddressZero;
  const requestsPerFunding = 0;
  const costPerRequest = 0;

  // We get the contract to deploy

  console.log("start of deployment");
  const mock = await (
    await ethers.getContractFactory("MockToken")
  ).deploy("Mock", "MCK", 18);
  console.log(mock.address);
  const treasury = await (await ethers.getContractFactory("Treasury")).deploy();
  const trading = await (await ethers.getContractFactory("Trading")).deploy();
  const parifiPool = await (
    await ethers.getContractFactory("PoolParifi")
  ).deploy(mock.address);
  const oracle = await (await ethers.getContractFactory("Oracle")).deploy();
  const factory = await (await ethers.getContractFactory("Factory")).deploy();
  const router = await (await ethers.getContractFactory("Router")).deploy();

  console.log("Deploy finished");
  console.log("Wait for configuration, please");

  let addresses = [
    ["mock", mock.address],
    ["treasury", treasury.address],
    ["trading", trading.address],
    ["parifiPool", parifiPool.address],
    ["oracle", oracle.address],
    ["factory", factory.address],
    ["router", router.address],
  ];

  // for (let i = 0; i < addresses.length; i++) {
  //   TEST_CONFIG.networks.rinkeby.addresses[i][0] = addresses[i][1];
  //   fs.writeFileSync(
  //     path.resolve(__dirname, "./deployedContractsOutput.json"),
  //     JSON.stringify(TEST_CONFIG, null, "    ")
  //   );
  // }

  TEST_CONFIG.networks.rinkeby.mock = mock.address;
  fs.writeFileSync(
    path.resolve(__dirname, "./deployedContractsOutput.json"),
    JSON.stringify(TEST_CONFIG, null, "    ")
  );

  TEST_CONFIG.networks.rinkeby.treasury = treasury.address;
  fs.writeFileSync(
    path.resolve(__dirname, "./deployedContractsOutput.json"),
    JSON.stringify(TEST_CONFIG, null, "    ")
  );

  TEST_CONFIG.networks.rinkeby.trading = trading.address;
  fs.writeFileSync(
    path.resolve(__dirname, "./deployedContractsOutput.json"),
    JSON.stringify(TEST_CONFIG, null, "    ")
  );
  TEST_CONFIG.networks.rinkeby.parifiPool = parifiPool.address;
  fs.writeFileSync(
    path.resolve(__dirname, "./deployedContractsOutput.json"),
    JSON.stringify(TEST_CONFIG, null, "    ")
  );
  TEST_CONFIG.networks.rinkeby.oracle = oracle.address;
  fs.writeFileSync(
    path.resolve(__dirname, "./deployedContractsOutput.json"),
    JSON.stringify(TEST_CONFIG, null, "    ")
  );
  TEST_CONFIG.networks.rinkeby.factory = factory.address;
  fs.writeFileSync(
    path.resolve(__dirname, "./deployedContractsOutput.json"),
    JSON.stringify(TEST_CONFIG, null, "    ")
  );
  TEST_CONFIG.networks.rinkeby.router = router.address;
  fs.writeFileSync(
    path.resolve(__dirname, "./deployedContractsOutput.json"),
    JSON.stringify(TEST_CONFIG, null, '  ')
  );

  await router.setContracts(
    treasury.address,
    trading.address,
    parifiPool.address,
    oracle.address,
    darkOracle,
    factory.address
  );

  await treasury.setRouter(router.address);
  await trading.setRouter(router.address);
  await parifiPool.setRouter(router.address);
  await oracle.setRouter(router.address);
  await oracle.setParams(requestsPerFunding, costPerRequest);
  await factory.setRouter(router.address);

  console.log("Configuration finished");
  console.log("Wait for verification, please");

  await delay(60000);
  try {
    await hre.run("verify:verify", {
      address: treasury.address,
    });
  } catch (error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: trading.address,
    });
  } catch (error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: parifiPool.address,
      constructorArguments: [mock.address],
    });
  } catch (error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: oracle.address,
    });
  } catch (error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: factory.address,
    });
  } catch (error) {
    console.error(error);
  }
  try {
    await hre.run("verify:verify", {
      address: router.address,
    });
  } catch (error) {
    console.error(error);
  }

  console.log("Verification finished");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
