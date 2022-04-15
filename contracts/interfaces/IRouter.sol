// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRouter {
    function trading() external view returns (address);

    function capPool() external view returns (address);

    function oracle() external view returns (address);

    function treasury() external view returns (address);

    function darkOracle() external view returns (address);

    function isSupportedCurrency(address currency) external view returns (bool);

    function currencies(uint256 index) external view returns (address);

    function currenciesLength() external view returns (uint256);

    function getDecimals(address currency) external view returns(uint8);

    function getPool(address currency) external view returns (address);

    function getPoolShare(address currency) external view returns(uint256);

    function getCapShare(address currency) external view returns(uint256);

    function getPoolRewards(address currency) external view returns (address);

    function getCapRewards(address currency) external view returns (address);

    function setPool(address currency, address _contract) external;

    function setPoolRewards(address currency, address _contract) external;

    function setCapRewards(address currency, address _contract) external;

    function setCurrencies(address[] calldata _currencies) external;

    function setDecimals(address currency, uint8 _decimals) external;
    
    function setPoolShare(address currency, uint256 share) external;

    function setCapShare(address currency, uint256 share) external;

    function addCurrency(address _currency) external;
}
