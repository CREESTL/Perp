const { ethers } = require("hardhat");

// address used for ether
const addressZero = ethers.constants.AddressZero;


// deploy contracts
async function getFactory() {
  const factory = await (await ethers.getContractFactory("Factory")).deploy();
  return factory;
}

async function getPool(addressOwner) {
  const pool = await (
    await ethers.getContractFactory("Pool")
  ).deploy(addressOwner, addressZero);
  return pool;
}

async function getTrading() {
  const trading = await (await ethers.getContractFactory("Trading")).deploy();
  return trading;
}

async function getPoolParifi(parifiAddress) {
  const poolParifi = await (
    await ethers.getContractFactory("PoolParifi")
  ).deploy(parifiAddress);
  return poolParifi;
}

async function getOracle() {
  const oracle = await (await ethers.getContractFactory("Oracle")).deploy();
  return oracle;
}

async function getTreasury() {
  const treasury = await (await ethers.getContractFactory("Treasury")).deploy();
  return treasury;
}

async function getRouter() {
  const router = await (await ethers.getContractFactory("Router")).deploy();
  return router;
}

function getKey(addr) {
  const key = ethers.utils.solidityKeccak256(
    ["address", "bytes32", "address", "bool"],
    [addr, productId, addressZero, isLong]
  );
  return key;
}

async function getMockToken() {
  const mockToken = await (
    await ethers.getContractFactory("MockToken")
  ).deploy("Mock", "MCK", 18);
  return mockToken;
}

// productId bytes32
const productId = ethers.utils.formatBytes32String("1");

// struct Product
const product = {
  maxLeverage: 5000000000,
  liquidationThreshold: 8000,
  fee: 0,
  interest: 535,
};

const isLong = false;

// margin size/leverage
const margin = ethers.utils.parseEther("1");

const size = ethers.BigNumber.from("5000000000");

// keccak256(abi.encodePacked(user, productId, currency, isLong))
function getKey(addr) {
  const key = ethers.utils.solidityKeccak256(
    ["address", "bytes32", "address", "bool"],
    [addr, productId, addressZero, isLong]
  );
  return key;
}

const stop = 100;
const take = 1000;

module.exports = {
  getFactory,
  getMockToken,
  getRouter,
  getPool,
  getTrading,
  getPoolParifi,
  getOracle,
  getTreasury,
  getKey,
  productId,
  product,
  isLong,
  addressZero,
  margin,
  size,
  stop,
  take,
};
