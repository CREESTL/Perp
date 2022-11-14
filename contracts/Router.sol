// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./libraries/SafeERC20.sol";

import "./interfaces/ITreasury.sol";
import "./interfaces/ITrading.sol";
import "./interfaces/IRouter.sol";

/// @title Keeps track of:
///        - Currencies
///        - Pools of each currency
///        - Rewards contracts of each currency
contract Router {
    using SafeERC20 for IERC20Metadata;

    /// @notice The address of the owner of the contract
    address public owner;
    /// @notice The address of the {Trading} contract
    address public trading;
    /// @notice The address of the {Oracle} contract
    address public oracle;
    /// @notice The address of the {PoolParifi} contract
    address public parifiPool;
    /// @notice The address of the {Treasury} contract
    address public treasury;
    /// @notice The address of the backend
    address public darkOracle;
    /// @notice The address of the {Factory} contract
    address public factory;

    /// @notice The list of supported tokens (currencies)
    // TODO Add mapping(address => bool) supportedCurrencies and
    // Use it in `addCurrency` and `isSupportedCurrency`
    address[] public currencies;

    /// @notice Decimals of each of the currencies
    mapping(address => uint8) public decimals;

    /// @notice The addresses of pools of each of the currencies
    /// @dev (currency address => pool address)
    /// @dev Pool can either be a currency pool or a parifi tokens pool
    mapping(address => address) public pools;

    /// @dev Mapping from token address to the BPS (one hundredth of 1%) for pool share
    mapping(address => uint256) private poolShares;
    /// @dev Mapping from token address to the BPS (one hundredth of 1%) for parifi-pool share
    mapping(address => uint256) private parifiShares;

    /// @notice Mapping from currency address to the {Rewards} contract using that currency
    mapping(address => address) public poolRewards;
    /// @notice Mapping from currency address to the {Rewards} contract using that currency
    mapping(address => address) public parifiRewards;

    constructor() {
        owner = msg.sender;
    }

    /// @notice Checks if the currency is supported
    /// @param currency The address of the currency to check
    /// @return True if currency is supported
    // TODO Check that there are {Pool}, {Rewards} and {ParifiRewards} for that currency. 
    // It might be, that the currency is the list of supported currencies of this contract, but there are
    // no necessary contracts deployed to support that currency
    function isSupportedCurrency(
        address currency
    ) external view returns (bool) {
        return currency != address(0) && pools[currency] != address(0);
    }

    /// @notice Returns the number of supported currencies
    /// @return The number of supported currencies
    function currenciesLength() external view returns (uint256) {
        return currencies.length;
    }

    /// @notice Returns the address of the pool for the given currency
    /// @param currency The address of the currency token
    /// @return The address of the pool of the currency
    function getPool(address currency) external view returns (address) {
        return pools[currency];
    }

    /// @notice Returns the pool share BPS (one hundredth of 1%) for the given currency
    /// @param currency The address of the currency
    /// @return The pool share BPS (one hundredth of 1%)
    function getPoolShare(address currency) external view returns (uint256) {
        return poolShares[currency];
    }

    /// @notice Returns the parifi-pool share BPS (one hundredth of 1%) for the given currency
    /// @param currency The address of the currency
    /// @return The parifi-pool share BPS (one hundredth of 1%)
    function getParifiShare(address currency) external view returns (uint256) {
        return parifiShares[currency];
    }

    /// @notice Returns the address of the {Rewards} contract with the given currency
    /// @param currency The address of the currency
    /// @return The address of the {Rewards} contract
    function getPoolRewards(address currency) external view returns (address) {
        return poolRewards[currency];
    }

    /// @notice Returns the address of the {Rewards} contract with the given currency
    /// @param currency The address of the currency
    /// @return The address of the {Rewards} contract
    function getParifiRewards(
        address currency
    ) external view returns (address) {
        return parifiRewards[currency];
    }

    /// @notice Returns the decimals of the given currency
    /// @param currency The address of the currency to check
    /// @return The decimals of the currency
    function getDecimals(address currency) external view returns (uint8) {
        if (currency == address(0)) return 18;
        if (decimals[currency] > 0) return decimals[currency];
        if (IERC20Metadata(currency).decimals() > 0)
            return IERC20Metadata(currency).decimals();
        return 18;
    }

    ///@dev Setters

    /// @notice Sets the list of supported currencies
    /// @param _currencies The list of supported currencies
    function setCurrencies(
        address[] calldata _currencies
    ) external onlyOwnerOrFactory {
        currencies = _currencies;
    }

    /// @notice Sets the decimals for the given currency
    /// @param currency The address of the currency
    /// @param _decimals The decimals of the currency
    function setDecimals(
        address currency,
        uint8 _decimals
    ) external onlyOwnerOrFactory {
        decimals[currency] = _decimals;
    }

    /// @notice Sets the addresses of contracts the {Router} can call
    /// @param _treasury The address of the {Treasury} contract
    /// @param _trading The address of the {Trading} contract
    /// @param _parifiPool The address of the {PoolParifi} contract
    /// @param _oracle The address of the {Oracle} contract
    /// @param _darkOracle The address of the backend
    /// @param _factory The address of the {Factory} contract
    function setContracts(
        address _treasury,
        address _trading,
        address _parifiPool,
        address _oracle,
        address _darkOracle,
        address _factory
    ) external onlyOwnerOrFactory {
        treasury = _treasury;
        trading = _trading;
        parifiPool = _parifiPool;
        oracle = _oracle;
        darkOracle = _darkOracle;
        factory = _factory;
    }

    /// @dev Sets the pool address for the given currency
    /// @param currency The currency to set the pool for
    /// @param _contract The address of the pool of the currency
    function setPool(
        address currency,
        address _contract
    ) external onlyOwnerOrFactory {
        pools[currency] = _contract;
    }

    /// @notice Sets the pool share
    /// @param currency The currency of the pool to set the share for
    /// @param share The share of the pool
    function setPoolShare(
        address currency,
        uint256 share
    ) external onlyOwnerOrFactory {
        poolShares[currency] = share;
    }

    /// @notice Sets the parifi-pool share
    /// @param currency The currency of the pool to set the share for
    /// @param share The share of the parifi-pool
    function setParifiShare(
        address currency,
        uint256 share
    ) external onlyOwnerOrFactory {
        parifiShares[currency] = share;
    }

    /// @notice Sets a new {Rewards} contract for the given currency
    /// @param currency The currency to pay rewards in
    /// @param _contract The address of the {Rewards} contract
    function setPoolRewards(
        address currency,
        address _contract
    ) external onlyOwnerOrFactory {
        poolRewards[currency] = _contract;
    }

    /// @notice Sets a new {Rewards} contract for the given currency
    /// @param currency The currency to pay rewards in
    /// @param _contract The address of the {Rewards} contract
    function setParifiRewards(
        address currency,
        address _contract
    ) external onlyOwnerOrFactory {
        parifiRewards[currency] = _contract;
    }

    /// @notice Sets a new owner of the contract
    function setOwner(address newOwner) external onlyOwnerOrFactory {
        owner = newOwner;
    }

    /// @notice Adds a new supported currency
    /// @param _currency The address of the currency to add
    function addCurrency(address _currency) external onlyOwnerOrFactory {
        for (uint256 i; i < currencies.length; i++) {
            require(currencies[i] != _currency, "currencyAdded");
        }
        currencies.push(_currency);
    }

    /// @dev Modifiers

    /// @dev Allows only the owner of the contract or the {Factory} contract to call the function
    modifier onlyOwnerOrFactory() {
        require(
            msg.sender == owner || msg.sender == factory,
            "!ownerOrFactory"
        );
        _;
    }
}
