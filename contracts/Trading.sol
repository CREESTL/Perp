// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";
import "./libraries/Address.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IPool.sol";

/// @title Creates orders for positions. Opens/inceases and closes/decreases positions. Settles orders.
///        Distributes trading fees
/// NOTE: All tokens amount have `decimals = 8` if other number is not explicitly set
contract Trading {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @dev Trading constants
    struct Product {
        // Set to 0 to deactivate product
        uint64 maxLeverage;
        // If the total price of the position decreases by this percentage against it's
        // initial price, the position gets liquidated.
        // In BPS (8000 = 80%)
        uint64 liquidationThreshold;
        // In SBPS (10^6). 0.5% = 5000. 0.025% = 250
        uint64 fee;
        // An additional payment for position
        // If the position is lost, then the user looses (PNL + interest) tokens
        // If the position if won, but PNL is less than interest, then the user looses (interest - PNL) tokens,
        // and, basically, it means that the position becomes a loss 
        // If the position is won and PNL is greater than interest, then the user wins (PNL - interest) tokens, 
        // and that is the only case when the PNL stays above zero and the user gets profit
        // For 360 days, in BPS. 5.35% = 535
        uint64 interest;
    }

    /// @dev One position
    struct Position {
        // The initial amount of tokens a user holds
        uint64 margin;
        // Nominal amount of the position
        // e.g. If margin is 2 USDT and leverage is 20, then size is 40 USDT
        uint64 size;
        // The time when position got settled
        uint64 timestamp;
        // The average price of tokens in position
        // Gets recalculated each time a position gets settled
        uint64 price;
        // The amount of tokens to reach to trigger stop-loss
        uint64 stop;
        // The amount of tokens to reach to trigger take-profit
        uint64 take;
    }

    /// @dev An order to open / close a position
    struct Order {
        // True if order is for closing a position. Otherwise, false
        bool isClose;
        uint64 size;
        uint64 margin;
    }

    /// @notice The address of the owner of the contract
    address public owner;
    /// @notice The address of the {Router} contract
    address public router;
    /// @notice The address of the {Treasury} contract
    address public treasury;
    /// @notice The address of the {Oracle} contract
    address public oracle;

    /// @dev Mapping from product IDs to products
    /// @dev The ID of the product can be any `bytes32` value. Generally, can be generated
    ///      using `keccak` over some string.
    mapping(bytes32 => Product) private products;
    /// @dev Maping from position keys to positions
    /// @dev Key = (currency,user,product,direction)
    mapping(bytes32 => Position) private positions;
    /// @dev Mapping from *POSITION* keys to orders
    ///      `positions` and `orders` have the same length and corresponding elements at
    ///       the same indexes
    mapping(bytes32 => Order) private orders;

    /// @dev Mapping from currency to the minimum margin in that currency
    mapping(address => uint256) minMargin;

    /// @dev Mapping from currency to the pending fee in that currency
    mapping(address => uint256) pendingFees;

    /// @dev In this contract the decimals of 8 is used for each token
    ///         instead of 18 (like in other contracts)
    uint256 public constant UNIT_DECIMALS = 8;
    uint256 public constant UNIT = 10 ** UNIT_DECIMALS;
    uint256 public constant PRICE_DECIMALS = 8;

    /// @dev Events

    /// @dev Indicates that a new order was created
    event NewOrder(
        bytes32 indexed key,
        address indexed user,
        bytes32 indexed productId,
        address currency,
        bool isLong,
        uint256 margin,
        uint256 size,
        // True if the order is created to close the position
        bool isClose
    );

    /// @dev Indicates that a new stop-loss order was created
    event NewStopOrder(
        bytes32 indexed key,
        address indexed user,
        bytes32 indexed productId,
        address currency,
        bool isLong,
        uint64 stop
    );

    /// @dev Indicates that a new take-profit order was created
    event NewTakeOrder(
        bytes32 indexed key,
        address indexed user,
        bytes32 indexed productId,
        address currency,
        bool isLong,
        uint64 take
    );

    /// @dev Indicates that a stop-loss limit of the position was updated
    event PositionStopUpdated(
        bytes32 indexed key,
        address indexed user,
        bytes32 indexed productId,
        address currency,
        bool isLong,
        uint64 stop
    );

    /// @dev Indicates that a take-profit limit of the position was updated
    event PositionTakeUpdated(
        bytes32 indexed key,
        address indexed user,
        bytes32 indexed productId,
        address currency,
        bool isLong,
        uint64 take
    );

    /// @dev Indicates that a position was updated after settlement
    event PositionUpdated(
        bytes32 indexed key,
        address indexed user,
        bytes32 indexed productId,
        address currency,
        bool isLong,
        uint256 margin,
        uint256 size,
        uint256 price,
        uint256 fee
    );

    /// @dev Indicates that a position was closed
    event ClosePosition(
        bytes32 indexed key,
        address indexed user,
        bytes32 indexed productId,
        address currency,
        bool isLong,
        uint256 price,
        uint256 margin,
        uint256 size,
        uint256 fee,
        int256 pnl,
        bool wasLiquidated
    );

    constructor() {
        owner = msg.sender;
    }

    /// @dev Governance methods

    /// @notice Sets the new owner of the contract
    /// @param newOwner The address of the new owner of the contract
    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Sets the new router used in the contract
    /// @param _router The address of the new router
    function setRouter(address _router) external onlyOwner {
        router = _router;
        treasury = IRouter(router).treasury();
        oracle = IRouter(router).oracle();
    }

    /// @notice Sets the minimum margin for the currency
    /// @param currency The address of the currency to change the margin for
    /// @param _minMargin The new minimum margin for the currency
    function setMinMargin(
        address currency,
        uint256 _minMargin
    ) external onlyOwner {
        minMargin[currency] = _minMargin;
    }

    /// @notice Adds a new product
    /// @param productId The ID to give to a new product
    /// @param _product The product to be added. Receives the given ID
    /// @dev This function should be called to add products *before* any other functions
    ///      that take `productID` as a parameter, e.g.:
    ///      1) addProduct(ID=1)
    ///      2) submitOrder(ID=1)
    function addProduct(
        bytes32 productId,
        Product memory _product
    ) external onlyOwner {
        Product memory product = products[productId];

        // There should be no such product yet in the list
        require(product.liquidationThreshold == 0, "!product-exists");
        // Threshold should be a positive number
        require(_product.liquidationThreshold > 0, "!liqThreshold");

        products[productId] = Product({
            maxLeverage: _product.maxLeverage,
            fee: _product.fee,
            interest: _product.interest,
            liquidationThreshold: _product.liquidationThreshold
        });
    }

    /// @notice Updates the product with a given ID
    /// @param productId The ID of the product to update
    /// @param _product The product that replaces the old product
    function updateProduct(
        bytes32 productId,
        Product memory _product
    ) external onlyOwner {
        Product storage product = products[productId];

        require(product.liquidationThreshold > 0, "!product-does-not-exist");

        product.maxLeverage = _product.maxLeverage;
        product.fee = _product.fee;
        product.interest = _product.interest;
        product.liquidationThreshold = _product.liquidationThreshold;
    }

    /// @dev Methods

    /// @notice Distributes fees to:
    ///         - Treasury contract
    ///         - Pool contract (for specific currency)
    ///         - Parify Pool contract (for project token staking)
    function distributeFees(address currency) external {
        uint256 pendingFee = pendingFees[currency];
        if (pendingFee > 0) {
            pendingFees[currency] = 0;
            _transferOut(currency, treasury, pendingFee);
            // This distributes fees to both pools
            ITreasury(treasury).notifyFeeReceived(
                currency,
                pendingFee * 10 ** (18 - UNIT_DECIMALS)
            );
        }
    }

    /// @notice Creates an order to open/increase a position
    /// @param productId The ID of the product to use
    /// @param currency The currency of the position
    ///        Zero address if using ether
    /// @param isLong True if position is a long one (aiming for currency price increasing over time)
    ///        False if position is a short one (aiming for currency price decreasing over time)
    /// @param margin The margin of the order (initial deposit)
    /// @param size The nominal amount of tokens in the order (not the same as margin)
    function submitOrder(
        bytes32 productId,
        address currency,
        bool isLong,
        uint256 margin,
        uint256 size
    ) external payable {
        // User can be sending either ether or other ERC20 tokens
        if (currency == address(0)) {
            margin = msg.value / 10 ** (18 - UNIT_DECIMALS);
        } else {
            require(IRouter(router).isSupportedCurrency(currency), "!currency");
        }

        require(margin > 0, "!margin");
        require(size > 0, "!size");

        // Get the ID (key) of the order and the order with that key
        bytes32 key = _getPositionKey(msg.sender, productId, currency, isLong);
        Order memory order = orders[key];
        require(order.size == 0, "!order"); // existing order

        // Get the product of that order
        Product memory product = products[productId];
        // Calculate fee for the order to be sumbitted
        uint256 fee = (size * product.fee) / 10 ** 6;

        // Make sure that caller provided enough native tokens to pay the fee
        if (currency == address(0)) {
            require(margin > fee, "!margin<fee");
            margin -= fee;
        }

        // Make sure that margin is greater than the smallest possible margin
        require(margin >= minMargin[currency], "!min-margin");

        // Calculate the leverage of the order
        // In more traditional form: size = margin * leverage
        // (UNIT used to correct decimals)
        uint256 leverage = (UNIT * size) / margin;
        require(leverage >= UNIT, "!leverage");
        require(leverage <= product.maxLeverage, "!max-leverage");

        // Update and check pool utlization
        _updateOpenInterest(currency, size, false);
        address pool = IRouter(router).getPool(currency);
        uint256 utilization = IPool(pool).getUtilization();
        require(utilization < 10 ** 4, "!utilization");

        // Place a new order in the list of other orders
        orders[key] = Order({
            isClose: false,
            size: uint64(size),
            margin: uint64(margin)
        });

        // Transfer ERC20 tokens to this contract if necessary
        if (currency != address(0)) {
            _transferIn(currency, margin + fee);
        }

        emit NewOrder(
            key,
            msg.sender,
            productId,
            currency,
            isLong,
            margin,
            size,
            false
        );
    }

    /// @notice Creates an order to close/decrease a position
    /// @param productId The ID of the product to use
    /// @param currency The currency of the position
    ///        Zero address if using ether
    /// @param isLong True if position is a long one (aiming for currency price increasing over time)
    ///        False if position is a short one (aiming for currency price decreasing over time)
    /// @param size The nominal amount of tokens in the order (not the same as margin)
    function submitCloseOrder(
        bytes32 productId,
        address currency,
        bool isLong,
        uint256 size
    ) external payable {
        require(size > 0, "!size");

        // Get the ID (key) of the order and the order with that key
        bytes32 key = _getPositionKey(msg.sender, productId, currency, isLong);
        Order memory order = orders[key];
        require(order.size == 0, "!order");
        // Get the position corresponding to the order and check if it's valid
        Position storage position = positions[key];
        require(position.margin > 0, "!position");

        // Size of the order can't be greater that the size of the position the order is suppose to close
        if (size > position.size) {
            size = position.size;
        }

        // Get the product of that order
        Product memory product = products[productId];
        // Calculate fee for the order to be sumbitted
        uint256 fee = (size * product.fee) / 10 ** 6;

        // Make sure that caller provided enough native tokens to pay the fee
        if (currency == address(0)) {
            uint256 fee_units = fee * 10 ** (18 - UNIT_DECIMALS);
            require(
                msg.value >= fee_units &&
                    msg.value <= (fee_units * (10 ** 6 + 1)) / 10 ** 6,
                "!fee"
            );
        }

        // Calculate the margin of the order (not the same as the margin of the position)
        uint256 margin = (size * uint256(position.margin)) /
            uint256(position.size);

        // Place a new order in the list of other orders
        orders[key] = Order({
            isClose: true,
            size: uint64(size),
            margin: uint64(margin)
        });

        // Transfer ERC20 tokens to this contract if necessary
        if (currency != address(0)) {
            _transferIn(currency, fee);
        }

        emit NewOrder(
            key,
            msg.sender,
            productId,
            currency,
            isLong,
            margin,
            size,
            true
        );
    }

    /// @param isLong True if position is long, otherwise - false

    /// @notice Creates an order to change a stop-loss value of the existing position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param stop Percent of price difference to trigger limit
    /// @dev It doesn't actually create an order, but rather emits and event that imitates
    ///      order creation
    /// @dev Stop-loss limit is set for the whole position at once. It doesn't change if position gets changed.
    function submitStopOrder(
        bytes32 productId,
        address currency,
        bool isLong,
        uint64 stop
    ) external {
        // Get the ID (key) of the position and the position with that key
        bytes32 key = _getPositionKey(msg.sender, productId, currency, isLong);
        // Position should exist
        require(positions[key].size > 0, "!position");
        // It's forbidden to set stop-loss and take-profit for the same currency at the same time
        require(positions[key].take == 0, "Take profit already set");
        // Stop-loss should be set below current position's price
        require(stop < positions[key].price, "stopTooBig");

        emit NewStopOrder(key, msg.sender, productId, currency, isLong, stop);
    }

    /// @notice Creates an order to change a take-profit value of the existing position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param take Percent of price difference to trigger limit
    /// @dev It doesn't actually create an order, but rather emits and event that imitates
    ///      order creation
    /// @dev Take-profit limit is set for the whole position at once. It doesn't change if position gets changed.
    function submitTakeOrder(
        bytes32 productId,
        address currency,
        bool isLong,
        uint64 take
    ) external {
        // Get the ID (key) of the order and the order with that key
        bytes32 key = _getPositionKey(msg.sender, productId, currency, isLong);

        // Position should exist
        require(positions[key].size > 0, "!position");
        // It's forbidden to set stop-loss and take-profit for the same currency at the same time
        require(positions[key].stop == 0, "Stop loss already set");
        // Take-profit should be set above current position's price
        require(positions[key].price < take, "takeTooSmall");

        emit NewTakeOrder(key, msg.sender, productId, currency, isLong, take);
    }

    /// @notice Allows user to cancel an open order
    /// @param productId The ID of the product to use
    /// @param currency The currency of the position
    /// @param isLong True if position is a long one (aiming for currency price increasing over time)
    ///        False if position is a short one (aiming for currency price decreasing over time)
    function cancelOrder(
        bytes32 productId,
        address currency,
        bool isLong
    ) external {
        // Get the ID (key) of the order and the order with that key
        bytes32 key = _getPositionKey(msg.sender, productId, currency, isLong);
        Order memory order = orders[key];
        require(order.size > 0, "!exists");

        // Get the product of that order
        Product memory product = products[productId];
        // Calculate fee for the order to be sumbitted
        uint256 fee = (order.size * product.fee) / 10 ** 6;

        // Update pool utilization
        _updateOpenInterest(currency, order.size, true);

        // Delete the order from the list
        delete orders[key];

        // Refund (margin + fee) to the caller
        uint256 marginPlusFee = order.margin + fee;
        _transferOut(currency, msg.sender, marginPlusFee);
    }

    /// @notice Sets stop loss for an existing position
    /// @param user The owner of position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param stop Percent of price difference to trigger limit
    /// @dev Should be called by the backend afer {submitStopOrder}
    function settleStopOrder(
        address user,
        bytes32 productId,
        address currency,
        bool isLong,
        uint64 stop
    ) external onlyOracle {
        // Get the ID (key) of the position and the position with that key
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        // Position should exist
        require(positions[key].size > 0, "!position");
        // It's forbidden to set stop-loss and take-profit for the same currency at the same time
        require(positions[key].take == 0, "Take profit already set");
        // Stop-loss should be set below current position's price
        require(stop < positions[key].price, "stopTooBig");

        // Set the stop-loss value
        positions[key].stop = stop;

        emit PositionStopUpdated(key, user, productId, currency, isLong, stop);
    }

    /// @notice Set take profit for an existing position
    /// @param user The owner of position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param take Percent of price difference to trigger limit
    /// @dev Should be called by the backend afer {submitTakeOrder}
    function settleTakeOrder(
        address user,
        bytes32 productId,
        address currency,
        bool isLong,
        uint64 take
    ) external onlyOracle {
        // Get the ID (key) of the position and the position with that key
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        // Position should exist
        require(positions[key].size > 0, "!position");
        // It's forbidden to set stop-loss and take-profit for the same currency at the same time
        require(positions[key].stop == 0, "Stop loss already set"); // Forbid to set both
        // Take-profit should be set above current position's price
        require(positions[key].price < take, "takeTooSmall");

        // Set the take-profit value
        positions[key].take = take;

        emit PositionTakeUpdated(key, user, productId, currency, isLong, take);
    }

    /// @notice Sets price for a newly submitted order
    /// @param user The owner of position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param price The price of the position from external source
    function settleOrder(
        address user,
        bytes32 productId,
        address currency,
        bool isLong,
        uint256 price
    ) public onlyOracle {
        // Get the ID (key) of the order(position) and the order with that key
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        Order storage order = orders[key];
        // Order should exist
        require(order.size > 0, "!exists");

        // Get the product of that order
        Product memory product = products[productId];
        // Calculate fee for the order to be settled
        uint256 fee = (order.size * product.fee) / 10 ** 6;
        pendingFees[currency] += fee;

        // Order is for closing the position
        if (order.isClose) {
            {
                // Settle the order right away
                (uint256 margin, uint256 size, int256 pnl) = _settleCloseOrder(
                    user,
                    productId,
                    currency,
                    isLong,
                    price
                );

                // Get the pool of the currency of the position (order)
                address pool = IRouter(router).getPool(currency);

                // If it's a loss, transfer loss to the pool of the currency
                if (pnl < 0) {
                    {
                        uint256 positivePnl = uint256(-1 * pnl);
                        _transferOut(currency, pool, positivePnl);
                        // If the loss is less than the initial user's deposit (margin), transfer
                        // what's left of the margin back to the user
                        if (positivePnl < margin) {
                            _transferOut(currency, user, margin - positivePnl);
                        }
                    }

                // If it's a win (profit), transfer the win amount from the pool to the user
                } else {
                    IPool(pool).creditUserProfit(
                        user,
                        uint256(pnl) * 10 ** (18 - UNIT_DECIMALS)
                    );
                    // Also give user his initial deposit (margin) back
                    _transferOut(currency, user, margin);
                }

                // Update the open interest of the pool
                _updateOpenInterest(currency, size, true);

                emit ClosePosition(
                    key,
                    user,
                    productId,
                    currency,
                    isLong,
                    price,
                    margin,
                    size,
                    fee,
                    pnl,
                    false
                );
            }
        // Order is for opening a position
        } else {
            // Validate the price
            price = _validatePrice(price);

            // Get the position with the same key as the order
            Position storage position = positions[key];

            // Each time a new order for the *same* position gets settled
            // the position's average price gets recalculated
            uint256 averagePrice = (uint256(position.size) *
                uint256(position.price) +
                uint256(order.size) *
                uint256(price)) /
                (uint256(position.size) + uint256(order.size));

            // Record the time the position was opened
            // It doesn't get updated if new orders for the same position get settled
            if (position.timestamp == 0) {
                position.timestamp = uint64(block.timestamp);
            }

            // Update values of the position according to values of the order
            position.size += uint64(order.size);
            position.margin += uint64(order.margin);
            position.price = uint64(averagePrice);

            // After settlement the order gets deleted
            delete orders[key];

            emit PositionUpdated(
                key,
                user,
                productId,
                currency,
                isLong,
                position.margin,
                position.size,
                position.price,
                fee
            );
        }
    }

    /// @dev Settles the order for closing/decreasong the position
    /// @param user The owner of position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param price The price of the position from external source
    /// @return The margin (order/position), the size (order/position), PNL (positive/negative)
    /// @dev The margin and the size of the order get returned if the position doesn't get luquidated
    /// @dev The margin and the size of the position get returned if the position gets luquidated
    function _settleCloseOrder(
        address user,
        bytes32 productId,
        address currency,
        bool isLong,
        uint256 price
    ) internal returns (uint256, uint256, int256) {
        // Get the ID (key) of the order and the order with that key
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        Order memory order = orders[key];
        uint256 size = order.size;
        uint256 margin = order.margin;

        // Get the position corresponding to the order
        Position storage position = positions[key];
        require(position.margin > 0, "!position");

        // Get the product corresponding to the order and the position
        Product memory product = products[productId];

        // Check that price is valid
        price = _validatePrice(price);

        // Calculcate the profit & loss of the position
        int256 pnl = getPnL(
            isLong,
            price,
            position.price,
            size,
            product.interest,
            position.timestamp
        );

        // Check if it's a liquidation
        if (
            pnl <=
            -1 *
                int256(
                    (uint256(position.margin) *
                        uint256(product.liquidationThreshold)) / 10 ** 4
                )
        ) {
            // If it is, PNL is a negative value (loss)
            pnl = -1 * int256(uint256(position.margin));
            // And now we consider the margin and size of the position - not the order
            margin = position.margin;
            size = position.size;
            // Also the position margin gets reset
            position.margin = 0;
        } else {
            // If it is not, position keeps existing but it's size and margin get decreased
            position.margin -= uint64(margin);
            position.size -= uint64(size);
        }

        // If after decreasing the margin is 0, that means that now position gets liquidated
        if (position.margin == 0) {
            delete positions[key];
        }

        // Order gets deleted after settlement
        delete orders[key];

        return (margin, size, pnl);
    }

    /// @notice Closes a position by the request from the backend
    /// @param user The owner of position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param price The price of the position from external source
    function settleLimit(
        address user,
        bytes32 productId,
        address currency,
        bool isLong,
        uint256 price
    ) external onlyOracle {
        // Get the ID (key) of the order and the order with that key
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        require(orders[key].size == 0, "orderExists");

        // Get the ID (key) of the position and the position with that key
        Position storage position = positions[key];
        require(positions[key].margin > 0, "!position");

        // Check that either a "take-profit" or "stop-loss" limit was reached
        require(
            // Stop-limit
            (price <= positions[key].stop) ||
                // Take-profit
                ((positions[key].take > 0) && (price >= positions[key].take)),
            "!limit"
        );

        // Get the product of that order
        Product storage product = products[productId];
        // Calculate fee for the order to be sumbitted
        uint64 fee = (position.size * product.fee) / 10 ** 6;
        // Subtract the fee from the original deposit (margin)
        require(position.margin >= fee, "feeTooLarge");
        position.margin -= fee;

        // Submit an order
        orders[key] = Order({
            isClose: true,
            size: position.size,
            margin: position.margin
        });

        // Settle an order
        settleOrder(user, productId, currency, isLong, price);
    }

    /// @notice Liquidates a position by the request from the backend
    /// @param user The owner of position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param price The price of the position from external source
    function liquidatePosition(
        address user,
        bytes32 productId,
        address currency,
        bool isLong,
        uint256 price
    ) external onlyOracle {
        // Get the ID (key) of the position and the position with that key
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        Position memory position = positions[key];
        // The position should exist
        if (position.margin == 0 || position.size == 0) {
            return;
        }

        // Get the product of that position
        Product storage product = products[productId];

        // Check that price is valid
        price = _validatePrice(price);

        // Get the PNL of the position
        int256 pnl = getPnL(
            isLong,
            price,
            position.price,
            position.size,
            product.interest,
            position.timestamp
        );

        // Calculate the amount by which the margin should decrease for the position
        // to get liquidated
        // It's a positive number
        uint256 threshold = (position.margin * product.liquidationThreshold) /
            10 ** 4;

        // If the loss if greater than the threshold,
        if (pnl <= -1 * int256(threshold)) {
            // Fix for reentrancy
            uint64 pSize = position.size;
            uint64 pMargin = position.margin;

            // Delete (liquidate) the position
            delete positions[key];

            // What's left of the margin
            // e.g. 100% - 80%(threshold) = 20%
            uint256 fee = pMargin - threshold;

            // Get the pool of the currency
            address pool = IRouter(router).getPool(currency);
            // Transfer the whole threshold to the currency pool
            _transferOut(currency, pool, threshold);

            // Update the open interest of the pool
            _updateOpenInterest(currency, pSize, true);

            // The fee gets added to the total amount of fees to pay later
            pendingFees[currency] += fee;

            emit ClosePosition(
                key,
                user,
                productId,
                currency,
                isLong,
                price,
                pMargin,
                pSize,
                fee,
                -1 * int256(uint256(pMargin)),
                true
            );
        }
    }

    /// @notice Transfers user's margin back to him and liquidates the position
    /// @param user The owner of position
    /// @param productId Position's product
    /// @param currency Deposited token
    /// @param isLong True if position is long, otherwise - false
    /// @param includeFee True if fee should be released with margin, otherwise - false
    function releaseMargin(
        address user,
        bytes32 productId,
        address currency,
        bool isLong,
        bool includeFee
    ) external onlyOwner {
        // Get the ID (key) of the position and the position with that key
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        Position storage position = positions[key];
        require(position.margin > 0, "!position");

        uint256 margin = position.margin;

        emit ClosePosition(
            key,
            user,
            productId,
            currency,
            isLong,
            position.price,
            margin,
            position.size,
            0,
            0,
            false
        );

        // Once the margin gets released, the order should be deleted
        delete orders[key];

        // If a fee should be withdrawn with the margin, calculate the fee
        // and add it to the margin
        if (includeFee) {
            Product memory product = products[productId];
            uint256 fee = (position.size * product.fee) / 10 ** 6;
            margin += fee;
        }

        // Update open interest of the pool
        _updateOpenInterest(currency, position.size, true);

        // Delete the position as well
        delete positions[key];

        // Trasfer the margin[+fee] to the user
        _transferOut(currency, user, margin);
    }

    /// @dev These functions allow this contract to receive ether
    fallback() external payable {}

    receive() external payable {}

    /// @dev Internal methods

    /// @dev Hash function to get a position (order) key from multiple parameters
    /// @param user The address of the user
    /// @param productId The ID of the product
    /// @param currency The address of the currency
    /// @param isLong True if position is long, otherwise - false
    /// @return The key of the position (of the order)
    function _getPositionKey(
        address user,
        bytes32 productId,
        address currency,
        bool isLong
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, productId, currency, isLong));
    }

    /// @dev Updates the open interest of the pool
    /// @param currency The currency which pool should be updated
    /// @param amount The amount by which the open interest should be changed
    /// @param isDecrease True if open interest should be decreased, otherwise - false
    function _updateOpenInterest(
        address currency,
        uint256 amount,
        bool isDecrease
    ) internal {
        address pool = IRouter(router).getPool(currency);
        IPool(pool).updateOpenInterest(
            amount * 10 ** (18 - UNIT_DECIMALS),
            isDecrease
        );
    }

    /// @dev Transfers currency from the caller to this contract
    /// @param currency The currency to transfer
    /// @param amount The amount of currency to transfer
    function _transferIn(address currency, uint256 amount) internal {
        // TODO Replace this kind of `if` conditions with `require`s and explisit error messages
        if (amount == 0 || currency == address(0)) return;
        // Correct decimals
        uint256 decimals = IRouter(router).getDecimals(currency);
        amount = (amount * (10 ** decimals)) / (10 ** UNIT_DECIMALS);
        IERC20(currency).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @dev Transfers currency from this contract to the provided address
    /// @param currency The currency to transfer
    /// @param to The address to transfer currency to
    /// @param amount The amount of currency to transfer
    function _transferOut(
        address currency,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0 || to == address(0)) return;
        // Correct decimals
        uint256 decimals = IRouter(router).getDecimals(currency);
        amount = (amount * (10 ** decimals)) / (10 ** UNIT_DECIMALS);
        if (currency == address(0)) {
            // Transfer native tokens
            payable(to).sendValue(amount);
        } else {
            // Transfer ERC20 tokens
            IERC20(currency).safeTransfer(to, amount);
        }
    }

    /// @dev Checks if price is valid and corrects price's decimals in necessary
    /// @dev price The price to check
    ///      (has decimals = 8)
    /// @return A price with correct decimals
    function _validatePrice(uint256 price) internal pure returns (uint256) {
        require(price > 0, "!price");
        return price * 10 ** (UNIT_DECIMALS - PRICE_DECIMALS);
    }

    /// @dev Getters

    /// @notice Returns the product with the provided ID
    /// @param productId The ID of the product to look for
    /// @return The product with the provided ID
    function getProduct(
        bytes32 productId
    ) external view returns (Product memory) {
        return products[productId];
    }

    /// @notice Returns the position with the provided ID
    /// @param user The owner of the position
    /// @param currency The currency of the position
    /// @param productId The ID of the position to look for
    /// @param isLong True if position is long, otherwise - false
    /// @return position The position with the provided ID
    function getPosition(
        address user,
        address currency,
        bytes32 productId,
        bool isLong
    ) external view returns (Position memory position) {
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        return positions[key];
    }

    /// @notice Returns the order with the provided ID
    /// @param user The owner of the order
    /// @param currency The currency of the order
    /// @param productId The ID of the order to look for
    /// @param isLong True if order is long, otherwise - false
    /// @return order The order with the provided ID
    function getOrder(
        address user,
        address currency,
        bytes32 productId,
        bool isLong
    ) external view returns (Order memory order) {
        bytes32 key = _getPositionKey(user, productId, currency, isLong);
        return orders[key];
    }

    /// @notice Returns the list of orders with provided keys
    /// @param keys The list of orders' keys
    /// @return _orders The list of orders with provided keys
    function getOrders(
        bytes32[] calldata keys
    ) external view returns (Order[] memory _orders) {
        uint256 length = keys.length;
        _orders = new Order[](length);
        for (uint256 i = 0; i < length; i++) {
            _orders[i] = orders[keys[i]];
        }
        return _orders;
    }

    /// @notice Returns the list of positions with provided keys
    /// @param keys The list of positions' keys
    /// @return _positions The list of positions with provided keys
    function getPositions(
        bytes32[] calldata keys
    ) external view returns (Position[] memory _positions) {
        uint256 length = keys.length;
        _positions = new Position[](length);
        for (uint256 i = 0; i < length; i++) {
            _positions[i] = positions[keys[i]];
        }
        return _positions;
    }

    /// @notice Returns the pending fee of the currency
    /// @param currency The currency of the pending fee
    /// @return The pending fee of the currency
    function getPendingFee(address currency) external view returns (uint256) {
        return pendingFees[currency] * 10 ** (18 - UNIT_DECIMALS);
    }

    /// @notice Returns the PNL (profit'n'loss) of the position
    /// @param isLong True if position is long, otherwise - false
    /// @param price The price of the position from external source
    /// @param positionPrice The price of the position from this contract
    /// @param size The nominal amount of tokens in the order (not the same as margin)
    /// @param interest The interest of the position (for 360 days)
    /// @param timestamp The time when position was settled
    /// @return _pnl The PNL of the position
    function getPnL(
        bool isLong,
        uint256 price,
        uint256 positionPrice,
        uint256 size,
        uint256 interest,
        uint256 timestamp
    ) public view returns (int256 _pnl) {
        // If true, it means that PNL is a loss, actually
        bool pnlIsNegative;
        uint256 pnl;

        if (isLong) {
            // If the position is long, PNL is positive if price increases
            if (price >= positionPrice) {
                pnl = (size * (price - positionPrice)) / positionPrice;
            } else {
                pnl = (size * (positionPrice - price)) / positionPrice;
                pnlIsNegative = true;
            }
        } else {
            // If the position is short, PNL is positive if price decreases
            if (price > positionPrice) {
                pnl = (size * (price - positionPrice)) / positionPrice;
                pnlIsNegative = true;
            } else {
                pnl = (size * (positionPrice - price)) / positionPrice;
            }
        }

        // Can only get PNL after 15 minutes since the position got settled
        if (block.timestamp >= timestamp + 15 minutes) {
            uint256 _interest = (size *
                interest *
                (block.timestamp - timestamp)) / (UNIT * 10 ** 4 * 360 days);

            if (pnlIsNegative) {
                pnl += _interest;
            } else if (pnl < _interest) {
                pnl = _interest - pnl;
                pnlIsNegative = true;
            } else {
                pnl -= _interest;
            }
        }

        if (pnlIsNegative) {
            _pnl = -1 * int256(pnl);
        } else {
            _pnl = int256(pnl);
        }

        return _pnl;
    }

    /// @dev Modifiers

    /// @dev Allows only the {Oracle} contract to call functions
    ///      Basically, the backend (a.k.a dark oracle) calls functions via {Oracle}
    modifier onlyOracle() {
        require(msg.sender == oracle, "!oracle");
        _;
    }

    /// @dev Allows only the owner of the contract to call functions
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
}
