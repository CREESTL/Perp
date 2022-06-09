//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IRewards.sol";
import "./Pool.sol";
import "./Rewards.sol";

contract Factory {
    address public owner;
    address public router;

    event TokenAdded(
        address newToken,
        address pool,
        address poolRewards,
        address parifiRewards
    );

    event SetRouterForPoolAndRewards(
        address pool,
        address poolRewards,
        address parifiRewards
    );

    event UpdateParams(
        uint256 minDepositTime,
        uint256 utilizationMultiplier,
        uint256 maxParifi,
        uint256 withdrawFee
    );

    constructor() {
        owner = msg.sender;
    }

    function setOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "!router");
        router = _router;
    }

    function addToken(
        address _currency,
        uint8 _decimals,
        uint256 _share
    ) external onlyOwner {
        require(_currency != address(0), "!currency");
        require(
            IRouter(router).getPool(_currency) == address(0),
            "!poolExists"
        );
        require(
            IRouter(router).getParifiRewards(_currency) == address(0),
            "!parifiRewardsExists"
        );
        require(
            IRouter(router).getPoolRewards(_currency) == address(0),
            "!poolRewardsExists"
        );

        IRouter(router).setDecimals(_currency, _decimals);
        IRouter(router).addCurrency(_currency); // add currency in array

        Pool pool = new Pool(_currency);
        IRouter(router).setPool(_currency, address(pool));
        IRouter(router).setPoolShare(_currency, _share);

        Rewards poolRewards = new Rewards(address(pool), _currency);
        IRouter(router).setPoolRewards(_currency, address(poolRewards));

        Rewards parifiRewards = new Rewards(address(pool), _currency);
        IRouter(router).setParifiRewards(_currency, address(parifiRewards));
        IRouter(router).setParifiShare(_currency, _share);

        emit TokenAdded(
            _currency,
            address(pool),
            address(poolRewards),
            address(parifiRewards)
        );
    }

    /**
     * function to set router for pool, since pool doesnt know router. Get pool with help currency
     */
    function setRouterForPoolAndRewards(
        address _currency
    ) external onlyOwner {
        address pool = IRouter(router).getPool(_currency);
        IPool(pool).setRouter(router);
        address poolRewards = IRouter(router).getPoolRewards(_currency);
        IRewards(poolRewards).setRouter(router);
        address parifiRewards = IRouter(router).getParifiRewards(_currency);
        IRewards(parifiRewards).setRouter(router);
        emit SetRouterForPoolAndRewards(pool, poolRewards, parifiRewards);
    }

    /**
     * because pool owner factory needs ability to set pool settings. Only owner can do this
     */
    function setParamsPool(
        address _currency,
        uint256 _minDepositTime,
        uint256 _utilizationMultiplier,
        uint256 _maxParifi,
        uint256 _withdrawFee
    ) external onlyOwner {
        address pool = IRouter(router).getPool(_currency);
        IPool(pool).setParams(
            _minDepositTime,
            _utilizationMultiplier,
            _maxParifi,
            _withdrawFee
        );
        emit UpdateParams(
            _minDepositTime,
            _utilizationMultiplier,
            _maxParifi,
            _withdrawFee
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
}
