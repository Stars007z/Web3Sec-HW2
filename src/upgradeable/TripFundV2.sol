// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {TripFundV1} from "./TripFundV1.sol";

/// @custom:oz-upgrades-from src/upgradeable/TripFundV1.sol:TripFundV1
contract TripFundV2 is TripFundV1 {
    using SafeERC20 for IERC20;

    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);

    function contributeFor(address beneficiary, uint256 amount) external {
        if (beneficiary == address(0)) revert ZeroAddress();
        _recordContribution(beneficiary, amount);
        emit ContributedFor(msg.sender, beneficiary, amount);

        token.safeTransferFrom(msg.sender, address(this), amount);
    }
}
