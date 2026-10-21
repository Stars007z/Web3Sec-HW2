// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TripFund {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    address public immutable organizer;
    uint256 public immutable goal;
    uint256 public immutable deadline;

    mapping(address => uint256) public contributions;
    uint256 public totalRaised;
    bool public withdrawn;

    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    error ZeroAddress();
    error ZeroGoal();
    error DeadlineNotInFuture();
    error ZeroAmount();
    error DeadlinePassed();
    error DeadlineNotReached();
    error NotOrganizer();
    error GoalNotReached();
    error GoalReached();
    error AlreadyWithdrawn();
    error NoContribution();

    constructor(IERC20 token_, address organizer_, uint256 goal_, uint256 deadline_) {
        if (address(token_) == address(0) || organizer_ == address(0)) revert ZeroAddress();
        if (goal_ == 0) revert ZeroGoal();
        if (deadline_ <= block.timestamp) revert DeadlineNotInFuture();

        token = token_;
        organizer = organizer_;
        goal = goal_;
        deadline = deadline_;
    }

    function contribute(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (block.timestamp >= deadline) revert DeadlinePassed();

        contributions[msg.sender] += amount;
        totalRaised += amount;
        emit Contributed(msg.sender, amount);

        token.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw() external {
        if (msg.sender != organizer) revert NotOrganizer();
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised < goal) revert GoalNotReached();
        if (withdrawn) revert AlreadyWithdrawn();

        withdrawn = true;
        uint256 amount = totalRaised;
        emit Withdrawn(msg.sender, amount);

        token.safeTransfer(msg.sender, amount);
    }

    function refund() external {
        if (block.timestamp < deadline) revert DeadlineNotReached();
        if (totalRaised >= goal) revert GoalReached();
        uint256 amount = contributions[msg.sender];
        if (amount == 0) revert NoContribution();

        contributions[msg.sender] = 0;
        emit Refunded(msg.sender, amount);

        token.safeTransfer(msg.sender, amount);
    }
}
