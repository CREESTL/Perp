// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";
import "./libraries/Address.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/IRewards.sol";

/// @title Reward-distribution contract
contract Treasury {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice The owner of the contract
    address public owner;
    /// @notice The address of the {Router} contract
    address public router;
    /// @notice The address of the {Trading} contract
    address public trading;
    /// @notice The address of the {Oracle} contract
    address public oracle;

    uint256 public constant UNIT = 10 ** 18;

    constructor() {
        owner = msg.sender;
    }

    /// @dev Governance methods

    /// @notice Sets the owner of the contract
    /// @param newOwner The address of the new owner of the contract
    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Sets the address of the router to be used
    /// @param _router The new address of the router
    /// @dev Initialized variables with addresses received from router
    function setRouter(address _router) external onlyOwner {
        router = _router;
        oracle = IRouter(router).oracle();
        trading = IRouter(router).trading();
    }

    /// @dev Methods

    /// @notice Sends rewards to pool and parifi-pool contracts and notifies them about it
    /// @param currency The address of the tokens to be transferred
    /// @param amount The amount of tokens used to calculate the reward for each pool
    function notifyFeeReceived(
        address currency,
        uint256 amount
    ) external onlyTrading {
        // Get address of the contract that receives pool rewards
        address poolRewards = IRouter(router).getPoolRewards(currency);
        // Get the amount of tokens to be paid as pool reward
        uint256 poolReward = (IRouter(router).getPoolShare(currency) * amount) /
            10 ** 4;
        // Transfer the reward to the pool contract
        _transferOut(currency, poolRewards, poolReward);
        // Add the reward to the total amount of rewards paid
        IRewards(poolRewards).notifyRewardReceived(poolReward);

        // Get address of the contract that receives parifi-pool rewards
        address parifiRewards = IRouter(router).getParifiRewards(currency);
        // Get the amount of tokens to be paid as parifi pool reward
        uint256 parifiReward = (IRouter(router).getParifiShare(currency) *
            amount) / 10 ** 4;
        // Transfer the reward to the parifi-pool contract
        _transferOut(currency, parifiRewards, parifiReward);
        // Add the reward to the total amount of rewards paid
        IRewards(parifiRewards).notifyRewardReceived(parifiReward);
    }

    /// @notice Sends native tokens to the oracle for its services
    /// @param destination The address of the oracle to receive funds
    /// @param amount The amount of tokens to send to the oracle
    function fundOracle(
        address destination,
        uint256 amount
    ) external onlyOracle {
        uint256 ethBalance = address(this).balance;
        if (amount > ethBalance) return;
        payable(destination).sendValue(amount);
    }

    /// @notice Sends tokens from the treasury to the given address
    /// @param token The address of the token to send
    /// @param destination The address to transfer to
    /// @param amount The amount of tokens to transfer
    function sendFunds(
        address token,
        address destination,
        uint256 amount
    ) external onlyOwner {
        _transferOut(token, destination, amount);
    }

    /// @dev Allow this contract to receive ETH
    fallback() external payable {}

    receive() external payable {}

    /// @dev Utils

    /// @dev Transfers tokens to the given address
    /// @param currency The address of the token to transfer
    /// @param to The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    function _transferOut(
        address currency,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0 || to == address(0)) return;
        // Adjust decimals
        uint256 decimals = IRouter(router).getDecimals(currency);
        amount = (amount * (10 ** decimals)) / UNIT;
        if (currency == address(0)) {
            // Send native tokens
            payable(to).sendValue(amount);
        } else {
            // Send ERC20 tokens
            IERC20(currency).safeTransfer(to, amount);
        }
    }

    /// @dev Modifiers

    /// @dev Allows only the user of the contract to call the function
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    /// @dev Allows only the {Trading} contract to call the function
    modifier onlyTrading() {
        require(msg.sender == trading, "!trading");
        _;
    }

    /// @dev Allows only the {Oracle} contract to call the function
    modifier onlyOracle() {
        require(msg.sender == oracle, "!oracle");
        _;
    }
}
