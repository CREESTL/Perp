//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./interfaces/IRouter.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IRewards.sol";
import "./Pool.sol";
import "./Rewards.sol";

/// @title Adds a new tradable ERC20 token and deploys pools and rewards contracts for it
contract Factory {
    /// @notice The address of the owner of the contract
    address public owner;
    /// @notice The address of the {Router} contract
    address public router;

    /// @dev Indicates that a new supported ERC20 token for trading was added
    event TokenAdded(
        address newToken,
        address pool,
        address poolRewards,
        address parifiRewards
    );

    /// @dev Indicates that a new router has been set for a pool contract and 2 rewards contracts
    event SetRouterForPoolAndRewards(
        address pool,
        address poolRewards,
        address parifiRewards
    );

    /// @dev Indicates that new params have been set for a pool contract
    event UpdateParams(
        uint256 minDepositTime,
        uint256 utilizationMultiplier,
        uint256 maxParifi,
        uint256 withdrawFee
    );

    constructor() {
        owner = msg.sender;
    }

    /// @notice Changes owner's address
    /// @param _newOwner New owner's address
    function setOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    /// @notice Changes router's address
    /// @param _router New router's address
    /// NOTE: Should be called at the very beginning
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "!router");
        router = _router;
    }

    /// @notice Add support for trading with new ERC20 token
    /// @param _currency Address of added ERC20 token
    /// @param _decimals Decimals of added token
    /// @param _share Pool share of added token
    /// @dev Deploys new pool of the currency, new rewards contract for that currency pool and
    ///      a new rewards contract for global parifi pool and gives router control over them
    function addToken(
        address _currency,
        uint8 _decimals,
        uint256 _share
    ) external onlyOwner {
        require(_currency != address(0), "!currency");
        // Check that there is a pool contract and two pool contracts for the provided currency.
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

        // Add a new supported currency to the router
        IRouter(router).setDecimals(_currency, _decimals);
        IRouter(router).addCurrency(_currency);

        // Set the pool address for the currency
        Pool pool = new Pool(_currency);
        IRouter(router).setPool(_currency, address(pool));
        // Set the share for the currency pool
        IRouter(router).setPoolShare(_currency, _share);
        // Set rewards contract for the currency pool
        Rewards poolRewards = new Rewards(address(pool), _currency);
        IRouter(router).setPoolRewards(_currency, address(poolRewards));

        // Set the pool address for the global parifi pool of project tokens
        Rewards parifiRewards = new Rewards(address(pool), _currency);
        IRouter(router).setParifiRewards(_currency, address(parifiRewards));
        // Set the share for the global parifi pool of project tokens
        IRouter(router).setParifiShare(_currency, _share);

        // Initialize all needed adresses
        pool.setRouter(router);
        poolRewards.setRouter(router);
        parifiRewards.setRouter(router);

        emit TokenAdded(
            _currency,
            address(pool),
            address(poolRewards),
            address(parifiRewards)
        );
    }

    /// @notice Change router in contracts deployed through (and therefore owned by) the factory
    /// @param _currency Token which router should be changed
    /// @param _router New router address
    function setRouterForPoolAndRewards(
        address _currency,
        address _router
    ) external onlyOwner {
        require(_router != address(0), "!router");
        // Check that router suppoers the currency
        require(IRouter(_router).isSupportedCurrency(_currency), "!currency");
        // Get the pool for the given currency
        address pool = IRouter(_router).getPool(_currency);
        // Set a new router for the currency pool
        IPool(pool).setRouter(_router);
        // Set a new router for rewards contract of the currency pool
        address poolRewards = IRouter(_router).getPoolRewards(_currency);
        IRewards(poolRewards).setRouter(_router);
        // Set a new router for rewards contract of the global parifi pool
        address parifiRewards = IRouter(_router).getParifiRewards(_currency);
        IRewards(parifiRewards).setRouter(_router);
        emit SetRouterForPoolAndRewards(pool, poolRewards, parifiRewards);
    }

    /// @notice Change pool parameters in pool deployed through (and therefore owned by) the factory
    /// @param _currency Token which pool's parameters should be changed
    /// @param _minDepositTime Minimum deposit time
    /// @param _utilizationMultiplier Utilisation Multiplier
    /// @param _maxParifi Maximum amount of ether that can be stored in the pool
    /// @param _withdrawFee Withdraw fee
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

    /// @dev Modifiers

    /// @dev Allows only the owner of the contract to call functions
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
}
