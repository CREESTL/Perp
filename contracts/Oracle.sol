// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ITrading.sol";

/// @title Settles orders on-chain after off-chain confirmation
/// @dev Connects with the backend for position settlement
contract Oracle {
    /// @notice The address of the owner of the contract
    address public owner;
    /// @notice The address of the {Router} contract
    address public router;
    /// @notice The address of the backend
    address public darkOracle;
    /// @notice The address of the {Treasury} contract
    address public treasury;
    /// @notice The address of the {Trading} contract
    address public trading;
    /// @notice The number of requests that can be processes before next payment to the oracle
    /// @dev If `requestsPerFunding` requests were processed the treasury transfers funds to the oracle
    ///      the services are stopped (paused)
    uint256 public requestsPerFunding = 100;
    /// @notice The default cost of a single request is 0.0006 ETH
    uint256 public costPerRequest = 6 * 10 ** 14;
    /// @notice Conter for requests processes sinse the funding
    uint256 public requestsSinceFunding;

    /// @notice Indicates that an error occured while settling the position request
    event SettlementError(
        address indexed user,
        address currency,
        bytes32 productId,
        bool isLong,
        string reason
    );

    constructor() {
        owner = msg.sender;
    }

    /// @dev Governance methods

    /// @notice Sets the address of the owner of the contract
    /// @param newOwner The address of a the new owner
    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Sets the address of the router to use
    /// @dev Gets addresses of {Trading}, {Treasury} and backend from the router
    ///      and initializes values using them
    /// @param _router The address of the router to use
    function setRouter(address _router) external onlyOwner {
        router = _router;
        trading = IRouter(router).trading();
        treasury = IRouter(router).treasury();
        darkOracle = IRouter(router).darkOracle();
    }

    /// @notice Sets the number of requests waiting for funding
    ///         and the cost of a sigle request
    /// @param _requestsPerFunding The number of requests waiting for funding
    /// @param _costPerRequest The cost of a single request
    function setParams(
        uint256 _requestsPerFunding,
        uint256 _costPerRequest
    ) external onlyOwner {
        requestsPerFunding = _requestsPerFunding;
        costPerRequest = _costPerRequest;
    }

    /// @dev Methods

    /// @notice Settles stop-loss positions based on orders of multiple users
    /// @param users Batch of positions' owners
    /// @param productIds Batch of positions' products
    /// @param currencies Batch of positions' tokens
    /// @param directions Batch of positions' directions
    /// @param stops Batch of positions' stops
    function settleStopOrders(
        address[] calldata users,
        bytes32[] calldata productIds,
        address[] calldata currencies,
        bool[] calldata directions,
        uint64[] calldata stops
    ) external onlyDarkOracle {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            bytes32 productId = productIds[i];
            address currency = currencies[i];
            bool isLong = directions[i];

            try
                ITrading(trading).settleStopOrder(
                    user,
                    productId,
                    currency,
                    isLong,
                    stops[i]
                )
            {} catch Error(string memory reason) {
                emit SettlementError(user, currency, productId, isLong, reason);
            }
        }
    }

    /// @notice Settles take-profit positions based on orders of multiple users
    /// @param users Batch of positions' owners
    /// @param productIds Batch of positions' products
    /// @param currencies Batch of positions' tokens
    /// @param directions Batch of positions' directions
    /// @param takes Batch of positions' takes
    function settleTakeOrders(
        address[] calldata users,
        bytes32[] calldata productIds,
        address[] calldata currencies,
        bool[] calldata directions,
        uint64[] calldata takes
    ) external onlyDarkOracle {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            bytes32 productId = productIds[i];
            address currency = currencies[i];
            bool isLong = directions[i];

            try
                ITrading(trading).settleTakeOrder(
                    user,
                    productId,
                    currency,
                    isLong,
                    takes[i]
                )
            {} catch Error(string memory reason) {
                emit SettlementError(user, currency, productId, isLong, reason);
            }
        }
    }

    /// @notice Settles standard positions based on orders of multiple users
    /// @param users Batch of positions' owners
    /// @param productIds Batch of positions' products
    /// @param currencies Batch of positions' tokens
    /// @param directions Batch of positions' directions
    /// @param prices Batch of positions' prices
    function settleOrders(
        address[] calldata users,
        bytes32[] calldata productIds,
        address[] calldata currencies,
        bool[] calldata directions,
        uint256[] calldata prices
    ) external onlyDarkOracle {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            address currency = currencies[i];
            bytes32 productId = productIds[i];
            bool isLong = directions[i];

            try
                ITrading(trading).settleOrder(
                    user,
                    productId,
                    currency,
                    isLong,
                    prices[i]
                )
            {} catch Error(string memory reason) {
                emit SettlementError(user, currency, productId, isLong, reason);
            }
        }

        _tallyOracleRequests(users.length);
    }

    /// @notice Closes positions and settles limits
    /// @param users Batch of positions' owners
    /// @param productIds Batch of positions' products
    /// @param currencies Batch of positions' tokens
    /// @param directions Batch of positions' directions
    /// @param prices Batch of closing prices
    function settleLimits(
        address[] calldata users,
        bytes32[] calldata productIds,
        address[] calldata currencies,
        bool[] calldata directions,
        uint256[] calldata prices
    ) external onlyDarkOracle {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            address currency = currencies[i];
            bytes32 productId = productIds[i];
            bool isLong = directions[i];

            try
                ITrading(trading).settleLimit(
                    user,
                    productId,
                    currency,
                    isLong,
                    prices[i]
                )
            {} catch Error(string memory reason) {
                emit SettlementError(user, currency, productId, isLong, reason);
            }
        }

        _tallyOracleRequests(users.length);
    }

    /// @notice Liquidates positions of multiple users
    /// @param users Batch of positions' owners
    /// @param productIds Batch of positions' products
    /// @param currencies Batch of positions' tokens
    /// @param directions Batch of positions' directions
    /// @param prices Batch of closing prices
    function liquidatePositions(
        address[] calldata users,
        bytes32[] calldata productIds,
        address[] calldata currencies,
        bool[] calldata directions,
        uint256[] calldata prices
    ) external onlyDarkOracle {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            bytes32 productId = productIds[i];
            address currency = currencies[i];
            bool isLong = directions[i];
            ITrading(trading).liquidatePosition(
                user,
                productId,
                currency,
                isLong,
                prices[i]
            );
        }
        _tallyOracleRequests(users.length);
    }

    /// @dev Sends funds to the backend if the number of processed requests
    ///      is greater than the initial provided number of requests
    function _tallyOracleRequests(uint256 newRequests) internal {
        if (newRequests == 0) return;
        requestsSinceFunding += newRequests;
        if (requestsSinceFunding >= requestsPerFunding) {
            requestsSinceFunding = 0;
            ITreasury(treasury).fundOracle(
                darkOracle,
                costPerRequest * requestsPerFunding
            );
        }
    }

    /// @dev Modifiers

    /// @dev Allows only the owner of the contract to call the function
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    /// @dev Allows only the backend to call the function
    modifier onlyDarkOracle() {
        require(msg.sender == darkOracle, "!dark-oracle");
        _;
    }
}
