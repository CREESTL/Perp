// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/ITrading.sol";

contract Oracle {

	// Contract dependencies
	address public owner;
	address public router;
	address public darkOracle;
	address public treasury;
	address public trading;

	// Variables
	uint256 public requestsPerFunding = 100;
	uint256 public costPerRequest = 6 * 10**14; // 0.0006 ETH
	uint256 public requestsSinceFunding;

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

	// Governance methods

	function setOwner(address newOwner) external onlyOwner {
		owner = newOwner;
	}

	function setRouter(address _router) external onlyOwner {
		router = _router;
		trading = IRouter(router).trading();
		treasury = IRouter(router).treasury();
		darkOracle = IRouter(router).darkOracle();
	}

	function setParams(
		uint256 _requestsPerFunding, 
		uint256 _costPerRequest
	) external onlyOwner {
		requestsPerFunding = _requestsPerFunding;
		costPerRequest = _costPerRequest;
	}

	// Methods

	function settleStopOrders(
		address[] calldata users,
		bytes32[] calldata productIds,
		address[] calldata currencies,
		bool[] calldata directions,
		uint256[] calldata stops
	) external onlyDarkOracle {
		for (uint256 i = 0; i < users.length; i++) {
			address user = users[i];
			bytes32 productId = productIds[i];
			address currency = currencies[i];
			bool isLong = directions[i];

			try ITrading(trading).settleStopOrder(user, productId, currency, isLong, stops[i]) {

			} catch Error(string memory reason) {
				emit SettlementError(
					user,
					currency,
					productId,
					isLong,
					reason
				);
		}
		}
	}

	function settleTakeOrders(
		address[] calldata users,
		bytes32[] calldata productIds,
		address[] calldata currencies,
		bool[] calldata directions,
		uint256[] calldata takes
	) external onlyDarkOracle {
		for (uint256 i = 0; i < users.length; i++) {
			address user = users[i];
			bytes32 productId = productIds[i];
			address currency = currencies[i];
			bool isLong = directions[i];

			try ITrading(trading).settleTakeOrder(user, productId, currency, isLong, takes[i]) {

			} catch Error(string memory reason) {
				emit SettlementError(
					user,
					currency,
					productId,
					isLong,
					reason
				);
		}
		}
	}

	// function setLimits(
	// 	address[] calldata users,
	// 	bytes32[] calldata productIds,
	// 	address[] calldata currencies,
	// 	bool[] calldata directions,
	// 	uint256[] calldata stops,
	// 	uint256[] calldata takes
	// ) external onlyDarkOracle {
	// 	for (uint256 i = 0; i < users.length; i++) {
	// 		address user = users[i];
	// 		bytes32 productId = productIds[i];
	// 		address currency = currencies[i];
	// 		bool isLong = directions[i];

	// 		_setStop(user, productId, currency, isLong, stops[i]);
	// 		_setTake(user, productId, currency, isLong, takes[i]);
	// 	}
	// }


	// function _setStop(
	// 	address user,
	// 	bytes32 productId,
	// 	address currency,
	// 	bool isLong,
	// 	uint256 stop
	// ) private {
		// try ITrading(trading).setStop(user, productId, currency, isLong, stop) {

		// } catch Error(string memory reason) {
		// 	emit SettlementError(
		// 		user,
		// 		currency,
		// 		productId,
		// 		isLong,
		// 		reason
		// 	);
		// }
	// }

	// function _setTake(
	// 	address user,
	// 	bytes32 productId,
	// 	address currency,
	// 	bool isLong,
	// 	uint256 take
	// ) private {
	// 	try ITrading(trading).setTake(user, productId, currency, isLong, take) {

	// 	} catch Error(string memory reason) {
	// 		emit SettlementError(
	// 			user,
	// 			currency,
	// 			productId,
	// 			isLong,
	// 			reason
	// 		);
	// 	}
	// }

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

			try ITrading(trading).settleOrder(user, productId, currency, isLong, prices[i]) {

			} catch Error(string memory reason) {
				emit SettlementError(
					user,
					currency,
					productId,
					isLong,
					reason
				);
			}

		}

		_tallyOracleRequests(users.length);

	}

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
			ITrading(trading).liquidatePosition(user, productId, currency, isLong, prices[i]);
		}
		_tallyOracleRequests(users.length);
	}

	function _tallyOracleRequests(uint256 newRequests) internal {
		if (newRequests == 0) return;
		requestsSinceFunding += newRequests;
		if (requestsSinceFunding >= requestsPerFunding) {
			requestsSinceFunding = 0;
			ITreasury(treasury).fundOracle(darkOracle, costPerRequest * requestsPerFunding);
		}
	}

	// Modifiers

	modifier onlyOwner() {
		require(msg.sender == owner, "!owner");
		_;
	}

	modifier onlyDarkOracle() {
		require(msg.sender == darkOracle, "!dark-oracle");
		_;
	}

}