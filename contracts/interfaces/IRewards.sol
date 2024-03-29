// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRewards {
    function setRouter(address _router) external;

    function updateRewards(address account) external;

    function notifyRewardReceived(uint256 amount) external;
}
