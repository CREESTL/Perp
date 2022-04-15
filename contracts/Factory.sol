//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./Pool.sol";
import "./Rewards.sol";

contract Factory {
    address public owner;
    address public router;
    mapping(address => bool) public isAdded;

    event TokenAdded(
        address indexed newToken,
        address indexed pool,
        address poolRewards,
        address capRewards
    );

    constructor() {
        owner = msg.sender;
    }

    function setRouter(address _router) external onlyOwner {
        router = _router;
    }

    function addToken(address _currency, uint8 _decimals, uint256 _share) external onlyOwner {
        require(!isAdded[_currency] && _currency != address(0), "!added");

        IRouter(router).setDecimals(_currency, _decimals);
        IRouter(router).addCurrency(_currency); // add currency in array

        Pool pool = new Pool(_currency);
        IRouter(router).setPool(_currency, address(pool)); 
        IRouter(router).setPoolShare(_currency, _share);

        Rewards poolRewards = new Rewards(address(pool), _currency);
        IRouter(router).setPoolRewards(_currency, address(poolRewards));

        Rewards capRewards = new Rewards(address(pool), _currency);
        IRouter(router).setCapRewards(_currency, address(capRewards));
        IRouter(router).setCapShare(_currency, _share);

        isAdded[_currency] = true;

        emit TokenAdded(
            _currency,
            address(pool),
            address(poolRewards),
            address(capRewards)
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
}
