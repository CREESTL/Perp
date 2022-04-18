const { expect } = require("chai")
const { ethers } = require("hardhat")

describe("Testing the factory", async () => {
  let mockToken
  let factory

  before(async () => {
    [owner, user, cap, darkOracle] = await ethers.getSigners()

    const MockToken = await ethers.getContractFactory("MockToken")
    mockToken = await MockToken.deploy("Mock", "MCK", 18)

    const Factory = await ethers.getContractFactory("Factory")
    factory = await Factory.deploy()
  });

  it("should fail without router", async () => {
    await expect(factory.addToken(mockToken.address, 18, 100)).to.be.revertedWith("function call to a non-contract account")
  })

  describe ("Adding the router", async () => {
    let router
    
    before(async() => {
      const Router = await ethers.getContractFactory("Router");
      router = await Router.deploy();
      await factory.setRouter(router.address);
    })

    it("should correctly set router", async () => {
      expect((await factory.router()).toLowerCase()).to.be.equal(router.address.toLowerCase())
    })

    it("should fail without factory in router", async () => {
      await expect(factory.addToken(mockToken.address, 18, 100)).to.be.revertedWith("!ownerOrFactory")
    })

    describe("Setting the factory", async () => {
      before(async () => {
        // Using AddressZero because original contracts don't check if the addresses set
        await router.setContracts(
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          ethers.constants.AddressZero,
          factory.address
        );
      })

      it("should successfully set factory address in router", async() => {
        expect((await router.factory()).toLowerCase()).to.be.equal(factory.address.toLowerCase())
      })

      it("should successfully add token", async () => {
        await expect(factory.addToken(mockToken.address, 18, 100))
          .to.emit(factory, "TokenAdded").withArgs(
            mockToken.address,
            await router.getPool(mockToken.address),
            await router.getPoolRewards(mockToken.address),
            await router.getCapRewards(mockToken.address)
          )
        expect(await router.isSupportedCurrency(mockToken.address)).to.be.true
      })

      it("should fail to add already supported token", async () => {
        await expect(factory.addToken(mockToken.address, 18, 100)).to.be.revertedWith("!added")
      })
    })
  })
})