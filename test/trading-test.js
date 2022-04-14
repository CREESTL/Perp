const { expect } = require("chai");
const { ethers } = require("hardhat");

// productId bytes32
const productId = ethers.utils.formatBytes32String("1")

// struct Product
const product = {
    maxLeverage: 5000000000,
    liquidationThreshold: 8000,
    fee: 0,
    interest: 535
}

const isLong = false

// address used for ether
const addressZero = ethers.constants.AddressZero

// margin size/leverage
const margin = ethers.utils.parseEther("1")

const size = ethers.BigNumber.from("5000000000")

// keccak256(abi.encodePacked(user, productId, currency, isLong))
function getKey(addr) {
    const key = ethers.utils.solidityKeccak256(["address", "bytes32", "address", "bool"], [
        addr,
        productId,
        addressZero,
        isLong
    ])
    return key
}

const stop = 10
const take = 1000


describe("Testing new methods for setting take profit and stop loss", () => {

    before(async () => {
        [owner, user, cap, darkOracle] = await ethers.getSigners()
    })

    beforeEach(async () => {
        /* 
         Steps are done for the submitOrder method. 
         This is necessary for the settleOrder method, in which the position is created. 
         We, in turn, need the position to check the submitStopOrder and submitTakeOrder methods 
        */

        // deploy contracts
        MockToken = await ethers.getContractFactory("MockToken")
        mockToken = await MockToken.deploy("Mock", "MCK", 18)
        await mockToken.deployed()

        Pool = await ethers.getContractFactory("Pool")
        pool = await Pool.deploy(addressZero)
        await pool.deployed()

        Trading = await ethers.getContractFactory("Trading")
        trading = await Trading.deploy()
        await trading.deployed()

        PoolCAP = await ethers.getContractFactory("PoolCAP")
        poolCAP = await PoolCAP.deploy(cap.address)
        await poolCAP.deployed()

        Oracle = await ethers.getContractFactory("Oracle")
        oracle = await Oracle.deploy()
        await oracle.deployed()

        Treasury = await ethers.getContractFactory("Treasury")
        treasury = await Treasury.deploy()
        await treasury.deployed()

        Router = await ethers.getContractFactory("Router")
        router = await Router.deploy()
        await router.deployed()

        // setting required addresses
        await router.setContracts(
            treasury.address,
            trading.address,
            poolCAP.address,
            oracle.address,
            darkOracle.address
        )

        await oracle.setRouter(router.address)

        await router.setPool(
            addressZero,
            pool.address
        )

        await pool.setRouter(router.address)

        await trading.setRouter(router.address)
        
        await trading.addProduct(
            productId,
            product
        )
        
        // create order
        await trading.connect(user).submitOrder(
            productId,
            addressZero,
            isLong,
            0, // ether is sent, so 0 is sent 
            size, 
            {value: margin},
        )

        // Order setup by darkOracle
        await oracle.connect(darkOracle).settleOrders(
            [user.address],
            [productId],
            [addressZero],
            [isLong],
            [100]
        )
    })

    xit("should check emit NewStopOrder event in method submitStopOrder", async () => {
        const key = getKey(user.address)

        await expect(trading.connect(user).submitStopOrder(
            productId,
            addressZero,
            isLong,
            stop
        )).to.emit(trading, "NewStopOrder").withArgs(
            key,
            user.address,
            productId,
            addressZero,
            isLong,
            stop
        )
    })

    xit("should check emit NewTakeOrder event in method submitTakeOrder", async () => {
        const key = getKey(user.address)

        await expect(trading.connect(user).submitTakeOrder(
            productId,
            addressZero,
            isLong,
            take
        )).to.emit(trading, "NewTakeOrder").withArgs(
            key,
            user.address,
            productId,
            addressZero,
            isLong,
            take
        )
    })

    xit("should check emit PositionStopOrder in method settleStopOrder", async () => {
        const key = getKey(user.address)

        let position1 = await trading.getPosition(
            user.address,
            addressZero,
            productId,
            isLong
        )

        console.log(position1)

        await oracle.connect(darkOracle).settleStopOrders(
            [user.address],
            [productId],
            [addressZero],
            [isLong],
            [stop]
        )
        
        let position2 = await trading.getPosition(
            user.address,
            addressZero,
            productId,
            isLong
        )
        console.log(position2)

        // await expect(oracle.connect(darkOracle).settleStopOrders(
        //     [user.address],
        //     [productId],
        //     [addressZero],
        //     [isLong],
        //     [stop]
        // )).to.emit(trading, "PositionStopUpdated").withArgs(
        //     key,
        //     user.address,
        //     productId,
        //     addressZero,
        //     isLong,
        //     stop
        // )
    })

    xit("should check emit PositionTakeOrder in method settleTakeOrder", async () => {
        let position1 = await trading.getPosition(
            user.address,
            addressZero,
            productId,
            isLong
        )

        console.log(position1)

        await oracle.connect(darkOracle).settleTakeOrders(
            [user.address],
            [productId],
            [addressZero],
            [isLong],
            [take]
        )
        
        let position2 = await trading.getPosition(
            user.address,
            addressZero,
            productId,
            isLong
        )
        console.log(position2)
    })

    xit("should check that it is impossible to add a stop loss for a closed position", async () => {
        // close order
        await trading.connect(user).submitCloseOrder(
            productId,
            addressZero,
            isLong,
            size
        )
        await oracle.connect(darkOracle).settleOrders(
            [user.address],
            [productId],
            [addressZero],
            [isLong],
            [100]
        )
        await expect(trading.connect(user).submitStopOrder(
            productId,
            addressZero,
            isLong,
            stop
        )).to.be.revertedWith("!position");
    })

    it("should check that it is impossible to add a take profit for a closed position", async () => {
        // close order
        await trading.connect(user).submitCloseOrder(
            productId,
            addressZero,
            isLong,
            size
        )
        await oracle.connect(darkOracle).settleOrders(
            [user.address],
            [productId],
            [addressZero],
            [isLong],
            [100]
        )
        await expect(trading.connect(user).submitTakeOrder(
            productId,
            addressZero,
            isLong,
            take
        )).to.be.revertedWith("!position");
    })

    xit("should check SettlementError event emit on error", async () => {
    
    })
})
