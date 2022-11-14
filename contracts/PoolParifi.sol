// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/IRewards.sol";

// @title The pool of internal project tokens users stake
contract PoolParifi {
    using SafeERC20 for IERC20;

    /// @notice The address of the owner of this contract
    address public owner;
    /// @notice The address of the {Router} contract
    address public router;
    /// @notice The address of the project token
    address public parifi;
    /// @dev The mapping from account's address to the amount of ERC20 tokens he deposited
    mapping(address => uint256) private balances;
    /// @notice The total amount of ERC20 tokens stored in the pool
    uint256 public totalSupply;

    /// @dev Events
    /// @notice Indicates that funds were deposited into the parifi-pool
    event DepositParifi(address indexed user, uint256 amount);
    /// @notice Indicates that funds were withdrawn from parifi-pool
    event WithdrawParifi(address indexed user, uint256 amount);

    constructor(address _parifi) {
        owner = msg.sender;
        parifi = _parifi;
    }

    /// @dev Governance methods

    /// @notice Seths the address of the new owner of the contract
    /// @param newOwner The address of the new owner of the contact
    function setOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Sets the address of the new router used in the contract
    /// @param _router The address of the new router
    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    /// @notice Allows user to deposit tokens into the pool
    /// @param amount The amount of tokens to be deposited (ERC20 only)
    function deposit(uint256 amount) external {
        require(amount > 0, "!amount");

        // When user deposits funds into parifi pool, his rewards for staking
        // all other currencies in different pools also get updated
        _updateRewards();

        // Update the total amount of tokens in the pool and the user's balance of the tokens
        totalSupply += amount;
        balances[msg.sender] += amount;

        // Transfer tokens from the user into the pool
        IERC20(parifi).safeTransferFrom(msg.sender, address(this), amount);

        emit DepositParifi(msg.sender, amount);
    }

    /// @notice Allows a user to withdraw funds from the pool
    /// @param amount The amount of parifi tokens to withdraw from the pool
    function withdraw(uint256 amount) external {
        // Zero-value withdrawals are not allowed
        require(amount > 0, "!amount");

        // The amount of tokens to withdraw should not exceed user's balance
        if (amount >= balances[msg.sender]) {
            amount = balances[msg.sender];
        }

        // When user deposits funds into parifi pool, his rewards for staking
        // all other currencies in different pools also get updated
        _updateRewards();

        // Update the total amount of tokens in the pool and the user's balance of the tokens
        totalSupply -= amount;
        balances[msg.sender] -= amount;

        // Transfer tokens from the pool to the user
        IERC20(parifi).safeTransfer(msg.sender, amount);

        emit WithdrawParifi(msg.sender, amount);
    }

    /// @notice Returns the amount of tokens a user holds in the pool
    /// @param account The account to get the balance of
    /// @return The amount of tokens a user holds in the pool
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @dev Updates rewards of the caller for each currency he staked in other pools
    function _updateRewards() internal {
        uint256 length = IRouter(router).currenciesLength();
        for (uint256 i = 0; i < length; i++) {
            address currency = IRouter(router).currencies(i);
            // Each currency has its own {Rewards} contract
            address rewardsContract = IRouter(router).getParifiRewards(
                currency
            );
            // Update rewards in that currency for the caller
            IRewards(rewardsContract).updateRewards(msg.sender);
        }
    }

    /// @dev Modifiers

    /// @dev Only allows the owner of the contract to call functions
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
}
