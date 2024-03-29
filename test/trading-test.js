const { expect } = require("chai");
const { ethers } = require("hardhat");
const {
  getFactory,
  getPool,
  getRouter,
  getMockToken,
  getPoolParifi,
  getTrading,
  getTreasury,
  getOracle,
  getKey,
  productId,
  product,
  isLong,
  addressZero,
  margin,
  size,
  stop,
  take,
} = require("./utils.js");
const PRICE = "100";

describe("Testing new methods for setting take profit and stop loss", () => {
  let owner;
  let user;
  let parifi;
  let darkOracle;

  before(async () => {
    [owner, user, darkOracle] = await ethers.getSigners();
    parifi = await getMockToken();
    key = getKey(user.address);
  });

  beforeEach(async () => {
    /* 
         Steps are done for the submitOrder method. 
         This is necessary for the settleOrder method, in which the position is created. 
         We, in turn, need the position to check the submitStopOrder and submitTakeOrder methods 
        */

    // deploy contracts
    factory = await getFactory();
    oracle = await getOracle();
    pool = await getPool();
    poolParifi = await getPoolParifi(parifi.address);
    trading = await getTrading();
    treasury = await getTreasury();
    router = await getRouter();

    // setting required addresses
    await router.setContracts(
      treasury.address,
      trading.address,
      poolParifi.address,
      oracle.address,
      darkOracle.address,
      factory.address
    );

    await oracle.setRouter(router.address);

    await router.setPool(addressZero, pool.address);

    await pool.setRouter(router.address);

    await trading.setRouter(router.address);

    await trading.addProduct(productId, product);

    await poolParifi.setRouter(router.address);

    // create order
    await trading.connect(user).submitOrder(
      productId,
      addressZero,
      isLong,
      0, // ether is sent, so 0 is sent
      size,
      { value: margin }
    );

    // Order setup by darkOracle
    await oracle
      .connect(darkOracle)
      .settleOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [PRICE]
      );
  });

  it("should deposit to parifi pool", async () => {
    await parifi.mint("1000000000000000000");
    await parifi.increaseAllowance(poolParifi.address, "1000000000000000000");
    await poolParifi.deposit("1000000000000000000");
  });

  it("should check emit NewStopOrder event in method submitStopOrder", async () => {
    await expect(
      trading
        .connect(user)
        .submitStopOrder(productId, addressZero, isLong, stop)
    )
      .to.emit(trading, "NewStopOrder")
      .withArgs(key, user.address, productId, addressZero, isLong, stop);
  });

  it("should check emit NewTakeOrder event in method submitTakeOrder", async () => {
    await expect(
      trading
        .connect(user)
        .submitTakeOrder(productId, addressZero, isLong, take)
    )
      .to.emit(trading, "NewTakeOrder")
      .withArgs(key, user.address, productId, addressZero, isLong, take);
  });

  it("should check emit PositionStopOrder in method settleStopOrder", async () => {
    const position1 = await trading.getPosition(
      user.address,
      addressZero,
      productId,
      isLong
    );

    expect(position1.stop).to.equal(0);

    // create position[key].stop
    await oracle
      .connect(darkOracle)
      .settleStopOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [stop]
      );

    const position2 = await trading.getPosition(
      user.address,
      addressZero,
      productId,
      isLong
    );
    expect(position2.stop).to.equal(stop);

    await expect(
      oracle
        .connect(darkOracle)
        .settleStopOrders(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [stop]
        )
    )
      .to.emit(trading, "PositionStopUpdated")
      .withArgs(key, user.address, productId, addressZero, isLong, stop);
  });

  it("should check emit PositionTakeOrder in method settleTakeOrder", async () => {
    const position1 = await trading.getPosition(
      user.address,
      addressZero,
      productId,
      isLong
    );

    expect(position1.take).to.equal(0);

    // create position[key].take
    await oracle
      .connect(darkOracle)
      .settleTakeOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [take]
      );

    const position2 = await trading.getPosition(
      user.address,
      addressZero,
      productId,
      isLong
    );

    expect(position2.take).to.equal(take);

    await expect(
      oracle
        .connect(darkOracle)
        .settleTakeOrders(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [take]
        )
    )
      .to.emit(trading, "PositionTakeUpdated")
      .withArgs(key, user.address, productId, addressZero, isLong, take);
  });

  it("should check that it is impossible to add a stop loss for a closed position", async () => {
    const product = await trading.getProduct(productId);
    const fee = size.mul(product.fee).mul(10 ** 4); // Magic with decimals

    // close order
    await trading
      .connect(user)
      .submitCloseOrder(productId, addressZero, isLong, size, { value: fee });
    await oracle
      .connect(darkOracle)
      .settleOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [PRICE]
      );
    await expect(
      trading
        .connect(user)
        .submitStopOrder(productId, addressZero, isLong, stop)
    ).to.be.revertedWith("!position");
  });

  it("should check that it is impossible to add a take profit for a closed position", async () => {
    const product = await trading.getProduct(productId);
    const fee = size.mul(product.fee).mul(10 ** 4); // Magic with decimals

    // close order
    await trading
      .connect(user)
      .submitCloseOrder(productId, addressZero, isLong, size, { value: fee });
    await oracle
      .connect(darkOracle)
      .settleOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [PRICE]
      );
    await expect(
      trading
        .connect(user)
        .submitTakeOrder(productId, addressZero, isLong, take)
    ).to.be.revertedWith("!position");
  });

  it("should check SettlementError event emit on error in function settleStopOrders", async () => {
    await expect(
      oracle.connect(darkOracle).settleStopOrders(
        [user.address],
        [productId],
        [owner.address], // invalid address
        [isLong],
        [stop]
      )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(
        user.address,
        owner.address,
        productId,
        isLong,
        "!position" // is error
      );
  });

  it("should check SettlementError event emit on error in function settleTakeOrders", async () => {
    await expect(
      oracle.connect(darkOracle).settleTakeOrders(
        [user.address],
        [productId],
        [owner.address], // invalid address
        [isLong],
        [take]
      )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(
        user.address,
        owner.address,
        productId,
        isLong,
        "!position" // is error
      );
  });

  it("should fail to set stop when it's too big", async () => {
    await expect(
      trading
        .connect(user)
        .submitStopOrder(productId, addressZero, isLong, PRICE + 1)
    ).to.be.revertedWith("stopTooBig");

    await expect(
      oracle
        .connect(darkOracle)
        .settleStopOrders(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [PRICE + 1]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(user.address, addressZero, productId, isLong, "stopTooBig");
  });

  it("should fail to set take when it's too small", async () => {
    await expect(
      trading
        .connect(user)
        .submitTakeOrder(productId, addressZero, isLong, PRICE - 1)
    ).to.be.revertedWith("takeTooSmall");

    await expect(
      oracle
        .connect(darkOracle)
        .settleTakeOrders(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [PRICE - 1]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(user.address, addressZero, productId, isLong, "takeTooSmall");
  });

  it("should check that it is impossible to set Take if Stop already set", async () => {
    await oracle
      .connect(darkOracle)
      .settleStopOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [stop]
      );

    await expect(
      trading
        .connect(user)
        .submitTakeOrder(productId, addressZero, isLong, take)
    ).to.be.revertedWith("Stop loss already set");

    await expect(
      oracle
        .connect(darkOracle)
        .settleTakeOrders(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [take]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(
        user.address,
        addressZero,
        productId,
        isLong,
        "Stop loss already set"
      );
  });

  it("should check that it is impossible to set Stop if Take already set", async () => {
    await oracle
      .connect(darkOracle)
      .settleTakeOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [take]
      );

    await expect(
      trading
        .connect(user)
        .submitStopOrder(productId, addressZero, isLong, stop)
    ).to.be.revertedWith("Take profit already set");

    await expect(
      oracle
        .connect(darkOracle)
        .settleStopOrders(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [stop]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(
        user.address,
        addressZero,
        productId,
        isLong,
        "Take profit already set"
      );
  });

  it("should fail to call settleLimits because not darkOracle", async () => {
    await expect(
      oracle.settleLimits(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [PRICE]
      )
    ).to.be.revertedWith("!dark-oracle");
  });

  it("should check emit event SettlementError if productid is invalid", async () => {
    const invalidProductId =
      ethers.utils.formatBytes32String("invalid product");
    await expect(
      oracle
        .connect(darkOracle)
        .settleLimits(
          [user.address],
          [invalidProductId],
          [addressZero],
          [isLong],
          [take]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(
        user.address,
        addressZero,
        invalidProductId,
        isLong,
        "!position"
      );
  });

  it("should check emit event SettlementError if order exists", async () => {
    const newProductId = ethers.utils.formatBytes32String("new product");
    await trading.addProduct(newProductId, product);
    await trading.connect(user).submitOrder(
      newProductId,
      addressZero,
      isLong,
      0, // ether is sent, so 0 is sent
      size,
      { value: margin }
    );

    await expect(
      oracle
        .connect(darkOracle)
        .settleLimits(
          [user.address],
          [newProductId],
          [addressZero],
          [isLong],
          [PRICE]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(user.address, addressZero, newProductId, isLong, "orderExists");
  });

  it("should fail if price do not trigger stop", async () => {
    await oracle
      .connect(darkOracle)
      .settleStopOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [stop]
      );

    await expect(
      oracle
        .connect(darkOracle)
        .settleLimits(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [PRICE]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(user.address, addressZero, productId, isLong, "!limit");
  });

  it("should fail if price do not trigger take", async () => {
    // Take not set yet
    await expect(
      oracle
        .connect(darkOracle)
        .settleLimits(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [PRICE]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(user.address, addressZero, productId, isLong, "!limit");

    await oracle
      .connect(darkOracle)
      .settleTakeOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [take]
      );

    await expect(
      oracle
        .connect(darkOracle)
        .settleLimits(
          [user.address],
          [productId],
          [addressZero],
          [isLong],
          [PRICE]
        )
    )
      .to.emit(oracle, "SettlementError")
      .withArgs(user.address, addressZero, productId, isLong, "!limit");
  });

  it("should successfully settle limit", async () => {
    const positionBefore = await trading.getPosition(
      user.address,
      addressZero,
      productId,
      isLong
    );
    const fee = positionBefore.size.mul(product.fee).div(10 ** 6);

    // Need to set limit before it will be triggered
    await oracle
      .connect(darkOracle)
      .settleTakeOrders(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [take]
      );

    await oracle
      .connect(darkOracle)
      .settleLimits(
        [user.address],
        [productId],
        [addressZero],
        [isLong],
        [take]
      );

    let event = (await trading.queryFilter("ClosePosition"))[0].args;

    expect(fee).to.be.equal(event.fee);
    expect(positionBefore.margin).to.be.equal(event.margin.add(event.fee));

    const positionAfter = await trading.getPosition(
      user.address,
      addressZero,
      productId,
      isLong
    );

    expect(positionAfter.size).to.be.equal(0);
  });
});
