// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {TripFund} from "../src/TripFund.sol";
import {TestToken} from "./mocks/TestToken.sol";

contract TripFundTest is Test {
    uint256 constant GOAL = 1_000e18;
    uint256 constant START_BALANCE = 10_000e18;

    TestToken token;
    TripFund fund;
    uint256 deadline;

    address organizer = makeAddr("organizer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address stranger = makeAddr("stranger");

    function setUp() public {
        vm.warp(1_760_000_000);
        deadline = block.timestamp + 7 days;

        token = new TestToken();
        token.mint(alice, START_BALANCE);
        token.mint(bob, START_BALANCE);
        token.mint(stranger, START_BALANCE);

        fund = new TripFund(token, organizer, GOAL, deadline);
    }

    function _contribute(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(address(fund), amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function test_Constructor_SetsParameters() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
    }

    function test_RevertWhen_Constructor_ZeroToken() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        new TripFund(IERC20(address(0)), organizer, GOAL, deadline);
    }

    function test_RevertWhen_Constructor_ZeroOrganizer() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        new TripFund(token, address(0), GOAL, deadline);
    }

    function test_RevertWhen_Constructor_ZeroGoal() public {
        vm.expectRevert(TripFund.ZeroGoal.selector);
        new TripFund(token, organizer, 0, deadline);
    }

    function test_RevertWhen_Constructor_DeadlineIsNow() public {
        vm.expectRevert(TripFund.DeadlineNotInFuture.selector);
        new TripFund(token, organizer, GOAL, block.timestamp);
    }

    function test_RevertWhen_Constructor_DeadlineInPast() public {
        vm.expectRevert(TripFund.DeadlineNotInFuture.selector);
        new TripFund(token, organizer, GOAL, block.timestamp - 1);
    }

    function test_Contribute_TwoParticipantsWithRepeatedContributions() public {
        vm.prank(alice);
        token.approve(address(fund), 100e18);
        vm.expectEmit(address(fund));
        emit TripFund.Contributed(alice, 100e18);
        vm.prank(alice);
        fund.contribute(100e18);

        _contribute(bob, 250e18);
        _contribute(alice, 150e18);
        _contribute(bob, 50e18);

        assertEq(fund.contributions(alice), 250e18);
        assertEq(fund.contributions(bob), 300e18);
        assertEq(fund.totalRaised(), 550e18);
        assertEq(token.balanceOf(address(fund)), 550e18);
        assertEq(token.balanceOf(alice), START_BALANCE - 250e18);
        assertEq(token.balanceOf(bob), START_BALANCE - 300e18);
    }

    function test_RevertWhen_ContributeZeroAmount() public {
        _contribute(alice, 100e18);
        vm.prank(alice);
        token.approve(address(fund), 100e18);

        vm.prank(alice);
        vm.expectRevert(TripFund.ZeroAmount.selector);
        fund.contribute(0);

        assertEq(fund.contributions(alice), 100e18);
        assertEq(fund.totalRaised(), 100e18);
        assertEq(token.balanceOf(alice), START_BALANCE - 100e18);
        assertEq(token.balanceOf(address(fund)), 100e18);
    }

    function test_RevertWhen_ContributeWithInsufficientBalance() public {
        address poor = makeAddr("poor");
        token.mint(poor, 50e18);
        vm.prank(poor);
        token.approve(address(fund), 100e18);

        vm.prank(poor);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, poor, 50e18, 100e18));
        fund.contribute(100e18);

        assertEq(fund.contributions(poor), 0);
        assertEq(fund.totalRaised(), 0);
        assertEq(token.balanceOf(poor), 50e18);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function test_RevertWhen_ContributeWithInsufficientAllowance() public {
        vm.prank(alice);
        token.approve(address(fund), 99e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 99e18, 100e18)
        );
        fund.contribute(100e18);

        assertEq(fund.contributions(alice), 0);
        assertEq(fund.totalRaised(), 0);
        assertEq(token.balanceOf(alice), START_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function test_Contribute_OneSecondBeforeDeadline() public {
        vm.warp(deadline - 1);
        _contribute(alice, 100e18);

        assertEq(fund.contributions(alice), 100e18);
        assertEq(fund.totalRaised(), 100e18);
    }

    function test_RevertWhen_ContributeAtDeadline() public {
        vm.warp(deadline);
        vm.prank(alice);
        token.approve(address(fund), 100e18);

        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlinePassed.selector);
        fund.contribute(100e18);

        assertEq(fund.totalRaised(), 0);
        assertEq(token.balanceOf(alice), START_BALANCE);
    }

    function test_RevertWhen_PayoutBeforeDeadline_EvenIfGoalReached() public {
        _contribute(alice, GOAL);
        vm.warp(deadline - 1);

        vm.prank(organizer);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.withdraw();

        vm.prank(alice);
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        fund.refund();

        assertEq(token.balanceOf(organizer), 0);
        assertEq(token.balanceOf(address(fund)), GOAL);
    }

    function test_Withdraw_ExactlyGoal() public {
        _contribute(alice, 600e18);
        _contribute(bob, 400e18);
        vm.warp(deadline);

        vm.expectEmit(address(fund));
        emit TripFund.Withdrawn(organizer, GOAL);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
        assertTrue(fund.withdrawn());
        assertEq(fund.totalRaised(), GOAL);
    }

    function test_Withdraw_AboveGoal() public {
        _contribute(alice, 700e18);
        _contribute(bob, 500e18);
        vm.warp(deadline);

        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), 1_200e18);
        assertEq(token.balanceOf(address(fund)), 0);
    }

    function test_RevertWhen_WithdrawByNotOrganizer() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.prank(stranger);
        vm.expectRevert(TripFund.NotOrganizer.selector);
        fund.withdraw();

        vm.prank(alice);
        vm.expectRevert(TripFund.NotOrganizer.selector);
        fund.withdraw();

        assertEq(token.balanceOf(stranger), START_BALANCE);
        assertEq(token.balanceOf(address(fund)), GOAL);
    }

    function test_RevertWhen_WithdrawTwice() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.startPrank(organizer);
        fund.withdraw();
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        fund.withdraw();
        vm.stopPrank();

        assertEq(token.balanceOf(organizer), GOAL);
    }

    function test_RevertWhen_RefundOnSuccess() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);

        vm.prank(alice);
        vm.expectRevert(TripFund.GoalReached.selector);
        fund.refund();

        assertEq(token.balanceOf(alice), START_BALANCE - GOAL);
    }

    function test_Refund_BelowGoal_IndependentRefunds() public {
        _contribute(alice, 300e18);
        _contribute(bob, 200e18);
        _contribute(alice, 100e18);
        vm.warp(deadline);

        vm.expectEmit(address(fund));
        emit TripFund.Refunded(bob, 200e18);
        vm.prank(bob);
        fund.refund();

        assertEq(token.balanceOf(bob), START_BALANCE);
        assertEq(fund.contributions(bob), 0);
        assertEq(fund.contributions(alice), 400e18);
        assertEq(token.balanceOf(address(fund)), 400e18);

        vm.prank(alice);
        fund.refund();

        assertEq(token.balanceOf(alice), START_BALANCE);
        assertEq(fund.contributions(alice), 0);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 600e18);
    }

    function test_RevertWhen_RefundTwice() public {
        _contribute(alice, 100e18);
        vm.warp(deadline);

        vm.startPrank(alice);
        fund.refund();
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();
        vm.stopPrank();

        assertEq(token.balanceOf(alice), START_BALANCE);
    }

    function test_RevertWhen_RefundWithoutContribution() public {
        _contribute(alice, 100e18);
        vm.warp(deadline);

        vm.prank(stranger);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();

        assertEq(token.balanceOf(address(fund)), 100e18);
    }

    function test_RevertWhen_WithdrawOnFailure() public {
        _contribute(alice, GOAL - 1);
        vm.warp(deadline);

        vm.prank(organizer);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), 0);
        assertEq(token.balanceOf(address(fund)), GOAL - 1);
    }

    function test_DirectTransfer_StaysAfterWithdraw() public {
        _contribute(alice, GOAL);
        vm.prank(stranger);
        token.transfer(address(fund), 77e18);

        assertEq(fund.totalRaised(), GOAL);
        assertEq(fund.contributions(stranger), 0);

        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();

        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 77e18);
    }

    function test_DirectTransfer_StaysAfterRefunds() public {
        _contribute(alice, 300e18);
        _contribute(bob, 200e18);
        vm.prank(stranger);
        token.transfer(address(fund), 77e18);

        assertEq(fund.totalRaised(), 500e18);

        vm.warp(deadline);
        vm.prank(alice);
        fund.refund();
        vm.prank(bob);
        fund.refund();

        vm.prank(stranger);
        vm.expectRevert(TripFund.NoContribution.selector);
        fund.refund();

        assertEq(token.balanceOf(address(fund)), 77e18);
    }
}
