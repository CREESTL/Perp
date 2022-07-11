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
    mockToken2 = await getMockToken();
    mockToken3 = await getMockToken();

    treasury = await getTreasury();
    trading = await getTrading();
    oracle = await getOracle();
    poolParifi = await getPoolParifi(parifi.address);

    factory = await getFactory();
  });

  it("should fail because not the owner", async () => {
    await expect(
      factory.connect(user).addToken(mockToken.address, 18, 100)
    ).to.be.revertedWith("!owner");
  });

  it("should fail without router", async () => {
    await expect(
      factory.addToken(mockToken.address, 18, 100)
    ).to.be.revertedWith("function call to a non-contract account");
  });

  it("should fail to set zero router", async () => {
    await expect(factory.setRouter(addressZero)).to.be.revertedWith("!router");
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
        await expect(factory.addToken(addressZero, 18, 100)).to.be.revertedWith(
          "!currency"
        );
      });

      it("should fail to add already supported token", async () => {
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("!poolExists");
      });

      it("should fail because parifi rewards already exist", async () => {
        // nullify pool for testing
        await router.setPool(mockToken.address, addressZero);
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("!parifiRewardsExists");
      });

      it("should fail because pool rewards already exist", async () => {
        // nullify parifi rewards for testing
        await router.setParifiRewards(mockToken.address, addressZero);
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("!poolRewardsExists");
      });

      it("should fail because currency was already added", async () => {
        // nullify pool rewards for testing
        await router.setPoolRewards(mockToken.address, addressZero);
        await expect(
          factory.addToken(mockToken.address, 18, 100)
        ).to.be.revertedWith("currencyAdded");
      });

      it("should check emit event in function setRouterForPoolAndRewards", async () => {
        const currency = mockToken2.address;
        await factory.addToken(currency, 18, 100);
        await expect(
          factory.setRouterForPoolAndRewards(currency, router.address)
        )
          .to.emit(factory, "SetRouterForPoolAndRewards")
          .withArgs(
            await router.getPool(currency),
            await router.getPoolRewards(currency),
            await router.getParifiRewards(currency)
          );
      });

      it("should check call setRouterForPoolAndRewards only owner", async () => {
        const currency = mockToken.address;
        await expect(
          factory
            .connect(user)
            .setRouterForPoolAndRewards(currency, router.address)
        ).to.be.revertedWith("!owner");
      });

      it("should correct set params for pool", async () => {
        const minDepositTime = 5000000000;
        const utilizationMultiplier = 8000;
        const maxParifi = ethers.constants.WeiPerEther;
        const withdrawFee = 535;

        const currency = mockToken3.address;
        await factory.addToken(currency, 18, 100);

        await expect(
          factory.setParamsPool(
            currency,
            minDepositTime,
            utilizationMultiplier,
            maxParifi,
            withdrawFee
          )
        )
          .to.emit(factory, "UpdateParams")
          .withArgs(
            minDepositTime,
            utilizationMultiplier,
            maxParifi,
            withdrawFee
          );
      });

      it("should check call setParamsPool only owner", async () => {
        const currency = mockToken.address;
        await expect(
          factory.connect(user).setParamsPool(currency, 0, 0, 0, 0)
        ).to.be.revertedWith("!owner");
      });

      it("should revert call setParamsPool", async () => {
        const currency = mockToken.address;
        await expect(factory.connect(user).setParamsPool(currency, 0, 0, 0, 0))
          .to.be.reverted;
      });

      it("should revert call setRouterForPoolAndRewards", async () => {
        const currency = mockToken.address;
        await expect(factory.connect(user).setRouterForPoolAndRewards(currency))
          .to.be.reverted;
      });
    });
  });
});
