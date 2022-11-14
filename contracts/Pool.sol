// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./libraries/SafeERC20.sol";
import "./libraries/Address.sol";

import "./interfaces/IRouter.sol";
import "./interfaces/IRewards.sol";

// @title The pool of one specific currency users trade (stake)
contract Pool {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice The address of the owner of this contract
    address public owner;
    /// @notice The address of the {Router} contract
    address public router;
    /// @notice The address of the {Trading} contract
    address public trading;
    /// @notice The address of the {Rewards} contract
    address public rewards;
    /// @notice Withdrawing funds from the pool costs 0.3% extra fee
    uint256 public withdrawFee = 30;
    /// @notice The address of the currency (token) stored in the pool
    address public currency;

    /// @notice Utilization multiplier (in Basis Points)
    uint256 public utilizationMultiplier = 100;

    /// @notice The maximum amount of ether that can be stored in the pool
    uint256 public maxParifi = 1000000 ether;

    /// @dev The mapping from account's address to the amount of LP tokens he got for deposit
    /// @dev These are *not* amounts of tokens the user transferred into the pool!
    mapping(address => uint256) private balances;
    /// @notice The total amount of *LP* tokens stored in the pool
    uint256 public totalSupply;

    /// @dev The mapping from account's address to the time this account made his latest stake
    mapping(address => uint256) lastDeposited;
    /// @notice The minimum time from deposit to withdrawal
    uint256 public minDepositTime = 1 hours;

    /// @notice The interest right after the position was opened
    uint256 public openInterest;

    /// @notice Decimals correction
    uint256 public constant UNIT = 10 ** 18;

    /// @dev Events

    /// @dev Indicated that funds have been deposited into the pool
    event Deposit(
        address indexed user,
        address indexed currency,
        uint256 amount,
        uint256 plpAmount
    );
    /// @dev Indicates that funds have been withdrawn from the pool
    event Withdraw(
        address indexed user,
        address indexed currency,
        uint256 amount,
        uint256 plpAmount
    );

    constructor(address _currency) {
        owner = msg.sender;
        currency = _currency;
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
        trading = IRouter(router).trading();
        rewards = IRouter(router).getPoolRewards(currency);
    }

    /// @notice Changes crusial variables of the pool
    /// @param _minDepositTime A new minimal time from token deposit till token withdrawal
    /// @param _utilizationMultiplier A new utilization multiplier (in Basis Points)
    /// @param _maxParifi A new maximum amount of ether that can be stored in the pool
    /// @param _withdrawFee A new fee for tokens withdrawal
    function setParams(
        uint256 _minDepositTime,
        uint256 _utilizationMultiplier,
        uint256 _maxParifi,
        uint256 _withdrawFee
    ) external onlyOwner {
        minDepositTime = _minDepositTime;
        utilizationMultiplier = _utilizationMultiplier;
        maxParifi = _maxParifi;
        withdrawFee = _withdrawFee;
    }

    /// @notice Updates open interest. Increase or decrease it.
    /// @param amount The amount to be added/subtracted from the current open interest
    /// @param isDecrease True if open interest shoul be decreased. False otherwhise.
    function updateOpenInterest(
        uint256 amount,
        bool isDecrease
    ) external onlyTrading {
        if (isDecrease) {
            if (openInterest <= amount) {
                openInterest = 0;
            } else {
                openInterest -= amount;
            }
        } else {
            openInterest += amount;
        }
    }

    /// @dev Methods

    /// @notice Deposits funds into the pool
    /// @param amount The amount of tokens to be deposited (ERC20 only)
    function deposit(uint256 amount) external payable {

        // The balance of the pool before the transfer of tokens
        // 1. Native tokens transfer
        // - Real ETH balance before calling deposit(): 10
        // - deposit 1 ETH
        // - Real ETH balance while calling deposit(): 11 
        // - lastBalance = real ETH balance = 11
        // - amount = 1
        // - lastBalance = 11 - 1 = 10 as before calling deposit()
        // - Real ETH balance after calling deposit(): 11 
        // 2. ERC20 token transfer
        // - ERC20 balance before calling deposit(): 10
        // - ERC20 balance while executing deposit(): 10
        // - deposit 1 ERC20 (transfer the the very end of this function)
        // - ERC20 balance after executing deposit(): 11
        uint256 lastBalance = _getCurrentBalance();
        if (currency == address(0)) {
            amount = msg.value;
            lastBalance -= amount;
        }

        // Zero-value deposists are forbidden
        require(amount > 0, "!amount");
        // Check that maximum balance is not exceeded
        require(amount + lastBalance <= maxParifi, "!max-parifi");

        // NOTICE: When user deposits tokens into the pool, his receives Parifi Liquidity Provider tokens to his balance
        // PLPs are not actually minted to the user. They simply represent the amount of external tokens transferred to the pool

        // Calculate the amount of LP tokens to be minted to the user
        uint256 plpAmountToMint = lastBalance == 0 || totalSupply == 0
            ? amount
            : (amount * totalSupply) / lastBalance;

        // Mark the time of the last deposit
        lastDeposited[msg.sender] = block.timestamp;

        // Update claimable reward for the user after his deposit
        IRewards(rewards).updateRewards(msg.sender);

        // Update the total supply of LP tokens in the pool
        totalSupply += plpAmountToMint;
        // Update the LP token balance of the caller
        balances[msg.sender] += plpAmountToMint;

        // If ERC20 tokens are deposited - transfer them into the contract
        if (currency != address(0)) {
            _transferIn(amount);
        }

        emit Deposit(msg.sender, currency, amount, plpAmountToMint);
    }

    /// @notice Allows a user to withdraw his funds from the pool
    /// @param currencyAmount The amount of external tokens a user want to withdraw
    function withdraw(uint256 currencyAmount) external {
        // Zero-value withdrawals are forbidden
        require(currencyAmount > 0, "!amount");
        // Withdrawal is allowed only after a cool-down time
        require(
            block.timestamp > lastDeposited[msg.sender] + minDepositTime,
            "!cooldown"
        );

        // Update the claimable rewards for the user
        IRewards(rewards).updateRewards(msg.sender);

        // Get the current balance of the contract (native/ERC20 tokens)
        uint256 currentBalance = _getCurrentBalance();
        require(currentBalance > 0 && totalSupply > 0, "!empty");

        // Get the utilization of the pool
        uint256 utilization = getUtilization();
        require(utilization < 10 ** 4, "!utilization");

        // Calculate PLP amount equal to the amount of tokens a user wants to withdraw
        uint256 amount = (currencyAmount * totalSupply) / currentBalance;

        // If a user wants to withdraw more tokens than he has (represented as PLP token), he will 
        // withdraw his whole balance of tokens and no more
        if (amount >= balances[msg.sender]) {
            amount = balances[msg.sender];
            // Currency amount to withdraw should also be recalculated in that case
            currencyAmount = (amount * currentBalance) / totalSupply;
        }

        // The balance of tokens available to withdraw
        uint256 availableBalance = (currentBalance * (10 ** 4 - utilization)) /
            10 ** 4;
        // Apply withdraw fee. Increase the currency amount to withdraw
        uint256 currencyAmountAfterFee = (currencyAmount *
            (10 ** 4 - withdrawFee)) / 10 ** 4;
        require(
            currencyAmountAfterFee <= availableBalance,
            "!available-balance"
        );

        // Decrease the total amount of LP tokens in the pool
        totalSupply -= amount;
        // Decrease the LP tokens balance of the user
        balances[msg.sender] -= amount;

        // Transfer currency from the pool to the caller
        _transferOut(msg.sender, currencyAmountAfterFee);

        // Transfer fees to the corresponding {Rewards} contract
        // (they can later be withdrawn by users from that contract)
        uint256 feeAmount = currencyAmount - currencyAmountAfterFee;
        _transferOut(rewards, feeAmount);
        IRewards(rewards).notifyRewardReceived(feeAmount);

        emit Withdraw(msg.sender, currency, currencyAmountAfterFee, amount);
    }

    /// @dev Transfers currency from the pool to the given address
    /// @param destination The address to withdraw currency to
    /// @param amount The amount of currency to withdraw
    function creditUserProfit(
        address destination,
        uint256 amount
    ) external onlyTrading {
        if (amount == 0) return;
        uint256 currentBalance = _getCurrentBalance();
        require(amount < currentBalance, "!balance");
        _transferOut(destination, amount);
    }

    /// @notice Allows this contract to receive ether
    fallback() external payable {}

    receive() external payable {}

    /// @dev Utils

    /// @dev Transfers the provided amount of ERC20 tokens into the pool
    /// @param amount The amount of ERC20 tokens to transfer into the pool
    function _transferIn(uint256 amount) internal {
        // Correct decimals
        uint256 decimals = IRouter(router).getDecimals(currency);
        amount = (amount * (10 ** decimals)) / UNIT;
        IERC20(currency).safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @dev Transfers currency from the pool to the given address
    /// @param to The address to withdraw currency to
    /// @param amount The amount of currency to withdraw
    function _transferOut(address to, uint256 amount) internal {
        if (amount == 0 || to == address(0)) return;
        // Correct decimals
        uint256 decimals = IRouter(router).getDecimals(currency);
        amount = (amount * (10 ** decimals)) / UNIT;
        if (currency == address(0)) {
            // Transfer native tokens
            payable(to).sendValue(amount);
        } else {
            // Or transfer ERC20 tokens
            IERC20(currency).safeTransfer(to, amount);
        }
    }

    /// @dev Returns the currency balance of the pool
    /// @return The currency balance of the pool
    function _getCurrentBalance() internal view returns (uint256) {
        uint256 currentBalance;
        if (currency == address(0)) {
            // Balance of native tokens
            currentBalance = address(this).balance;
        } else {
            // Or balance of ERC20 tokens
            currentBalance = IERC20(currency).balanceOf(address(this));
        }
        // Correct decimals
        uint256 decimals = IRouter(router).getDecimals(currency);
        return (currentBalance * UNIT) / (10 ** decimals);
    }

    /// @dev Getters

    /// @notice Returns the current utilization of the pool
    /// @return Current utilization of the pool (in Basis Points)
    function getUtilization() public view returns (uint256) {
        // Get the current balance first
        uint256 currentBalance = _getCurrentBalance();
        if (currentBalance == 0) return 0;
        // Calculate and return the utilization
        return (openInterest * utilizationMultiplier) / currentBalance;
    }

    /// @notice Returns the currency balance of the given account
    /// @param account The account to get the currency balance of
    /// @return The currency balance of the given account
    function getCurrencyBalance(
        address account
    ) external view returns (uint256) {
        if (totalSupply == 0) return 0;
        // Get the currency balance of the whole pool
        uint256 currentBalance = _getCurrentBalance();
        // Calculate the currency balance of the account
        return (balances[account] * currentBalance) / totalSupply;
    }

    /// @notice Returns the PLP balance of the account
    /// @param account The account to get the PLP balance of
    /// @return The PLP balance of the account
    function getBalance(address account) external view returns (uint256) {
        return balances[account];
    }

    /// @dev Modifiers

    /// @dev Allows only the owner of the contract to call functions
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    /// @dev Allows only the {Trading} contact to call functions
    modifier onlyTrading() {
        require(msg.sender == trading, "!trading");
        _;
    }
}
