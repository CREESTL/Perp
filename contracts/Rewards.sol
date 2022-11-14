// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";
import "./libraries/Address.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/ITrading.sol";
import "./interfaces/IPool.sol";

/// @title Receives and holds tokens that can later be claimed by users
/// @dev Can either represent rewards for parifi tokens pool or rewards for currency tokens pool
/// @dev Each currency has at least one corresponding rewards contract
contract Rewards {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice The address of the owner of the contract
    address public owner;
    /// @notice The address of the {Router} contract
    address public router;
    /// @notice The address of the {Trading} contract
    address public trading;
    /// @notice The address of the {Treasury} contract
    address public treasury;
    /// @notice The address of the {Pool or PoolParifi} contract assosiated with these rewards
    address public pool;
    /// @notice The address of the token stored in the contract and used to pay the rewards
    address public currency;

    /// @notice The reward for a single token stored in the pool by a user
    uint256 public cumulativeRewardPerTokenStored;
    /// @notice The reward that has been trasfered from some other contract to this contract,
    ///         but hasn't been processed in any way yet
    uint256 public pendingReward;

    /// @dev Mapping from user's address to the amount of reward he can claim
    mapping(address => uint256) private claimableReward;
    /// @dev Mapping from the user's address to the reward he claimed last time
    mapping(address => uint256) private previousRewardPerToken;

    /// @notice Corrects decimals
    uint256 public constant UNIT = 10 ** 18;

    /// @notice Indicates that a reward has been collected by the user
    event CollectedReward(
        address user,
        address poolContract,
        address currency,
        uint256 amount
    );

    constructor(address _pool, address _currency) {
        owner = msg.sender;
        pool = _pool;
        currency = _currency;
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
        trading = IRouter(_router).trading();
        treasury = IRouter(_router).treasury();
    }

    /// @dev Methods

    /// @notice Is called by other contracts after they transfer tokens to this contract
    ///         to indicate that tokens have been transferred
    /// @param amount The amount of tokens transferred (18 decimals)
    function notifyRewardReceived(uint256 amount) external onlyTreasuryOrPool {
        pendingReward += amount;
    }

    /// @notice Calculates the claimable reward for the account based on his pool's tokens balance
    ///         and the reward for a single token
    /// @dev User can have either parifi or currency tokens on his balance
    /// @param account The address of account which rewards should be updated
    function updateRewards(address account) public {
        if (account == address(0)) return;

        // Distribute fees to the treasury and both pools
        ITrading(trading).distributeFees(currency);

        // Get the total amount of tokens in the pool after rewards
        // distribution from trading
        uint256 supply = IPool(pool).totalSupply();

        // If there are any tokens in the pool - update the reward for a *single* stored token
        if (supply > 0) {
            cumulativeRewardPerTokenStored += (pendingReward * UNIT) / supply;
            pendingReward = 0;
        }

        // If the total reward is zero we should not pay any rewards
        if (cumulativeRewardPerTokenStored == 0) return;

        // Get account's balance in Parifi Liquidity Tokens
        uint256 accountBalance = IPool(pool).getBalance(account);

        // Calculate the total reward based on the LP token balance and the reward for a single token
        claimableReward[account] +=
            (accountBalance *
                (cumulativeRewardPerTokenStored -
                    previousRewardPerToken[account])) /
            UNIT;

        // Mark the current reward for a single token as a "used" one
        previousRewardPerToken[account] = cumulativeRewardPerTokenStored;
    }

    /// @notice Allows a user to claim his reward
    function collectReward() external {

        // Update the rewards first of all
        updateRewards(msg.sender);

        // Get the reward amount for the caller
        uint256 rewardToSend = claimableReward[msg.sender];
        // And reset if afterwards
        claimableReward[msg.sender] = 0;

        if (rewardToSend > 0) {
            // Transfer it to the caller
            _transferOut(msg.sender, rewardToSend);

            emit CollectedReward(msg.sender, pool, currency, rewardToSend);
        }
    }

    /// @notice Returns the reward amount a user can claim at the moment
    /// @return The reward amount a user can claim at the moment
    function getClaimableReward() external view returns (uint256) {
        // Get the current reward without recalculation
        // It will be recalculated if there are any tokens in the pool
        uint256 currentClaimableReward = claimableReward[msg.sender];

        // Get the amount of tokens in the pool
        uint256 supply = IPool(pool).totalSupply();
        // If there are no tokens in the pool then the caller can claim a current reward
        if (supply == 0) return currentClaimableReward;

        // Get the share of the reward currency in either a parifi pool or a currency pool
        uint256 share;
        if (pool == IRouter(router).parifiPool()) {
            share = IRouter(router).getParifiShare(currency);
        } else {
            share = IRouter(router).getPoolShare(currency);
        }

        // Increase the pending reward with the pending fee of the currencie's share of the pool
        uint256 _pendingReward = pendingReward +
            (ITrading(trading).getPendingFee(currency) * share) /
            10 ** 4;

        // And now recalculate the reward for a single token using a fresh pending reward
        uint256 _rewardPerTokenStored = cumulativeRewardPerTokenStored +
            (_pendingReward * UNIT) /
            supply;

        // If a reward for a single token is 0, then we should pay no rewards at all
        if (_rewardPerTokenStored == 0) return currentClaimableReward;

        // Get the LP tokens balance of the caller
        uint256 accountStakedBalance = IPool(pool).getBalance(msg.sender);

        // Calculate and return the current claimable reward
        return
            currentClaimableReward +
            (accountStakedBalance *
                (_rewardPerTokenStored - previousRewardPerToken[msg.sender])) /
            UNIT;
    }

    /// @dev Allows this contract to receive ETH
    fallback() external payable {}

    receive() external payable {}

    /// @dev Utils

    /// @dev Transfers tokens to the given address
    /// @param to The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    function _transferOut(address to, uint256 amount) internal {
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

    /// @notice Allows only the owner of the contract to call functions
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    /// @notice Allows only the {Pool} or the {Treasury} contracts to call functions
    modifier onlyTreasuryOrPool() {
        require(msg.sender == treasury || msg.sender == pool, "!treasury|pool");
        _;
    }
}
