// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./libraries/SafeERC20.sol";

import "./interfaces/ITreasury.sol";
import "./interfaces/ITrading.sol";
import "./interfaces/IRouter.sol";

contract Router {

	using SafeERC20 for IERC20Metadata; 

	// Contract dependencies
	address public owner;
	address public trading;
	address public oracle;
	address public parifiPool;
	address public treasury;
	address public darkOracle;
	address public factory;

	address[] public currencies;

	mapping(address => uint8) decimals;

	mapping(address => address) pools; // currency => contract
	
	mapping(address => uint256) private poolShare; // currency (eth, usdc, etc.) => bps
	mapping(address => uint256) private parifiShare; // currency => bps

	mapping(address => address) poolRewards; // currency => contract
	mapping(address => address) parifiRewards; // currency => contract

	constructor() {
		owner = msg.sender;
	}

	function isSupportedCurrency(address currency) external view returns(bool) {
		return currency != address(0) && pools[currency] != address(0);
	}

	function currenciesLength() external view returns(uint256) {
		return currencies.length;
	}

	function getPool(address currency) external view returns(address) {
		return pools[currency];
	}

	function getPoolShare(address currency) external view returns(uint256) {
		return poolShare[currency];
	}

	function getParifiShare(address currency) external view returns(uint256) {
		return parifiShare[currency];
	}

	function getPoolRewards(address currency) external view returns(address) {
		return poolRewards[currency];
	}

	function getParifiRewards(address currency) external view returns(address) {
		return parifiRewards[currency];
	}

	function getDecimals(address currency) external view returns(uint8) {
		if (currency == address(0)) return 18;
		if (decimals[currency] > 0) return decimals[currency];
		if (IERC20Metadata(currency).decimals() > 0) return IERC20Metadata(currency).decimals();
		return 18;
	}

	// Setters

	function setCurrencies(address[] calldata _currencies) external onlyOwnerOrFactory {
		currencies = _currencies;
	}

	function setDecimals(address currency, uint8 _decimals) external onlyOwnerOrFactory {
		decimals[currency] = _decimals;
	}

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

	function setPool(address currency, address _contract) external onlyOwnerOrFactory {
		pools[currency] = _contract;
	}

	function setPoolShare(address currency, uint256 share) external onlyOwnerOrFactory {
		poolShare[currency] = share;
	}
	function setParifiShare(address currency, uint256 share) external onlyOwnerOrFactory {
		parifiShare[currency] = share;
	}

	function setPoolRewards(address currency, address _contract) external onlyOwnerOrFactory {
		poolRewards[currency] = _contract;
	}

	function setParifiRewards(address currency, address _contract) external onlyOwnerOrFactory {
		parifiRewards[currency] = _contract;
	}

	function setOwner(address newOwner) external onlyOwnerOrFactory {
		owner = newOwner;
	}

	function addCurrency(address _currency) external onlyOwnerOrFactory {
		for(uint256 i; i < currencies.length; i++) {
			require(currencies[i] != _currency, "currencyAdded");
		}
		currencies.push(_currency);
	}

	// Modifiers

	modifier onlyOwnerOrFactory() {
		require(msg.sender == owner || msg.sender == factory, "!ownerOrFactory");
		_;
	}

}