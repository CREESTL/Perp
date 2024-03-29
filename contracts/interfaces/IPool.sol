// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IPool {
    function setParams(
        uint256 _minDepositTime,
        uint256 _utilizationMultiplier,
        uint256 _maxParifi,
        uint256 _withdrawFee
    ) external;

    function setRouter(address _router) external;

    function totalSupply() external view returns (uint256);

    function creditUserProfit(address destination, uint256 amount) external;

    function updateOpenInterest(uint256 amount, bool isDecrease) external;

    function getUtilization() external view returns (uint256);

    function getBalance(address account) external view returns (uint256);
}
