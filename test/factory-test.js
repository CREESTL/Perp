const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  addressZero,
  getFactory,
  getMockToken,
  getTreasury,
  getTrading,
  getOracle,
  getPoolParifi,
} = require("./utils.js");

describe("Testing the factory", async () => {
  let mockToken;
  let factory;

  before(async () => {
    [owner, user, parifi, darkOracle] = await ethers.getSigners();

    mockToken = await getMockToken();
    treasury = await getTreasury();
    trading = await getTrading();
    oracle = await getOracle();
    poolParifi = await getPoolParifi(parifi.address);

    factory = await getFactory();
  });

  it("should fail because not the owner", async() => {
    await expect(
      factory.connect(user).addToken(mockToken.address, 18, 100)
    ).to.be.revertedWith("!owner");
  })

  it("should fail without router", async () => {
    await expect(
      factory.addToken(mockToken.address, 18, 100)
    ).to.be.revertedWith("function call to a non-contract account");
  });

  it('should fail to set zero router', async() => {
    await expect(factory.setRouter(addressZero)).to.be.revertedWith("!router");
  })

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
          poolParifi.address,
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
            await router.getParifiRewards(mockToken.address)
          );
        expect(await router.isSupportedCurrency(mockToken.address)).to.be.true;
      });

      it("should fail to add zero token", async () => {
        await expect(
          factory.addToken(addressZero, 18, 100)
        ).to.be.revertedWith("!currency");
      });

      it("should fail to add already supported token", async () => {
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("!poolExists");
      });

      it("should fail because parifi rewards already exist", async() => {
        // nullify pool for testing
        await router.setPool(mockToken.address, addressZero);
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("!parifiRewardsExists");
      })

      it("should fail because pool rewards already exist", async() => {
        // nullify parifi rewards for testing
        await router.setParifiRewards(mockToken.address, addressZero);
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("!poolRewardsExists");
      })

      it("should fail because currency was already added", async() => {
        // nullify pool rewards for testing
        await router.setPoolRewards(mockToken.address, addressZero);
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("currencyAdded");
      })
    });
  });
});
