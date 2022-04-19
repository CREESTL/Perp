//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./Pool.sol";
import "./Rewards.sol";

contract Factory {
    address public owner;
    address public router;

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
        require(_router != address(0), "!router");
        router = _router;
    }
    
    function addToken(address _currency, uint8 _decimals, uint256 _share) external onlyOwner {
        require(_currency != address(0), "!currency");
        require(IRouter(router).getPool(currency) == address(0), "!poolExists");
        require(IRouter(router).getCapRewards(currency), "!capRewardsExists");
        require(IRouter(router).getPoolRewards(_currency) == address(0), "!poolRewardsExists");

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
