const { ethers } = require("hardhat");

// contract factory
async function getFactory() {
  const factory = await (await ethers.getContractFactory("Factory")).deploy();
  return factory;
}

function getKey(addr) {
  const key = ethers.utils.solidityKeccak256(
    ["address", "bytes32", "address", "bool"],
    [addr, productId, addressZero, isLong]
  );
  return key;
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

// address used for ether
const addressZero = ethers.constants.AddressZero;

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
