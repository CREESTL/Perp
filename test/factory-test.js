const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  getFactory,
  getMockToken,
  getTreasury,
  getTrading,
  getOracle,
  getPoolCAP,
} = require("./utils.js");

describe("Testing the factory", async () => {
  let mockToken;
  let factory;

  before(async () => {
    [owner, user, cap, darkOracle] = await ethers.getSigners();

    mockToken = await getMockToken();
    treasury = await getTreasury();
    trading = await getTrading();
    oracle = await getOracle();
    poolCAP = await getPoolCAP(cap.address);

    factory = await getFactory();
  });

  it("should fail without router", async () => {
    await expect(
      factory.addToken(mockToken.address, 18, 100)
    ).to.be.revertedWith("function call to a non-contract account");
  });

  describe("Adding the router", async () => {
    let router;

    before(async () => {
      const Router = await ethers.getContractFactory("Router");
      router = await Router.deploy();
      await factory.setRouter(router.address);
    });

    it("should correctly set router", async () => {
      expect((await factory.router()).toLowerCase()).to.be.equal(
        router.address.toLowerCase()
      );
    });

    it("should fail without factory in router", async () => {
      await expect(
        factory.addToken(mockToken.address, 18, 100)
      ).to.be.revertedWith("!ownerOrFactory");
    });

    describe("Setting the factory", async () => {
      before(async () => {
        await router.setContracts(
          treasury.address,
          trading.address,
          poolCAP.address,
          oracle.address,
          darkOracle.address,
          factory.address
        );
      });

      it("should successfully set factory address in router", async () => {
        expect((await router.factory()).toLowerCase()).to.be.equal(
          factory.address.toLowerCase()
        );
      });

      it("should successfully add token", async () => {
        await expect(factory.addToken(mockToken.address, 18, 100))
          .to.emit(factory, "TokenAdded")
          .withArgs(
            mockToken.address,
            await router.getPool(mockToken.address),
            await router.getPoolRewards(mockToken.address),
            await router.getCapRewards(mockToken.address)
          );
        expect(await router.isSupportedCurrency(mockToken.address)).to.be.true;
      });

      it("should fail to add already supported token", async () => {
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("!poolExists");
      });
    });
  });
});
