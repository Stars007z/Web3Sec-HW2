// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {TripFundV1} from "../src/upgradeable/TripFundV1.sol";
import {TripFundV2} from "../src/upgradeable/TripFundV2.sol";
import {TestToken} from "./mocks/TestToken.sol";

contract TripFundUpgradeTest is Test {
    uint256 constant GOAL = 1_000e18;
    uint256 constant START_BALANCE = 10_000e18;

    TestToken token;
    address proxy;
    address proxyAdmin;
    uint256 deadline;

    address proxyAdminOwner = makeAddr("proxyAdminOwner");
    address organizer = makeAddr("organizer");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address friend = makeAddr("friend");
    address stranger = makeAddr("stranger");

    function setUp() public {
        vm.warp(1_760_000_000);
        deadline = block.timestamp + 7 days;

        token = new TestToken();
        token.mint(alice, START_BALANCE);
        token.mint(bob, START_BALANCE);

        proxy = Upgrades.deployTransparentProxy(
            "TripFundV1.sol",
            proxyAdminOwner,
            abi.encodeCall(TripFundV1.initialize, (IERC20(address(token)), organizer, GOAL, deadline))
        );
        proxyAdmin = Upgrades.getAdminAddress(proxy);
    }

    function _contribute(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(proxy, amount);
        TripFundV1(proxy).contribute(amount);
        vm.stopPrank();
    }

    function _upgradeToV2() internal {
        Upgrades.upgradeProxy(proxy, "TripFundV2.sol", "", proxyAdminOwner);
    }

    function test_V1_DeployedBehindTransparentProxy() public view {
        TripFundV1 fund = TripFundV1(proxy);
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(ProxyAdmin(proxyAdmin).owner(), proxyAdminOwner);
    }

    function test_RevertWhen_ProxyInitializedAgain() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        TripFundV1(proxy).initialize(IERC20(address(token)), stranger, 1, deadline);

        _upgradeToV2();

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        TripFundV2(proxy).initialize(IERC20(address(token)), stranger, 1, deadline);

        assertEq(TripFundV2(proxy).organizer(), organizer);
    }

    function test_RevertWhen_ImplementationInitializedDirectly() public {
        TripFundV1 implementationV1 = TripFundV1(Upgrades.getImplementationAddress(proxy));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementationV1.initialize(IERC20(address(token)), stranger, 1, deadline);

        _upgradeToV2();

        TripFundV2 implementationV2 = TripFundV2(Upgrades.getImplementationAddress(proxy));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementationV2.initialize(IERC20(address(token)), stranger, 1, deadline);
    }

    function test_RevertWhen_UpgradeByNotProxyAdminOwner() public {
        Options memory opts;
        address implementationV2 = Upgrades.prepareUpgrade("TripFundV2.sol", opts);
        address implementationV1 = Upgrades.getImplementationAddress(proxy);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), implementationV2, "");

        vm.prank(organizer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, organizer));
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), implementationV2, "");

        assertEq(Upgrades.getImplementationAddress(proxy), implementationV1);
    }

    function test_StorageLayout_V2CompatibleWithV1() public {
        Options memory opts;
        opts.referenceContract = "TripFundV1.sol";
        Upgrades.validateUpgrade("TripFundV2.sol", opts);
    }

    function test_Upgrade_KeepsState_ThenContributeForAndRefundToFriend() public {
        _contribute(alice, 300e18);

        address implementationV1 = Upgrades.getImplementationAddress(proxy);
        uint256 proxyBalance = token.balanceOf(proxy);

        vm.warp(deadline - 1 days);
        _upgradeToV2();
        TripFundV2 fund = TripFundV2(proxy);

        assertNotEq(Upgrades.getImplementationAddress(proxy), implementationV1);
        assertEq(Upgrades.getAdminAddress(proxy), proxyAdmin);
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.contributions(alice), 300e18);
        assertEq(fund.totalRaised(), 300e18);
        assertEq(token.balanceOf(proxy), proxyBalance);

        vm.prank(bob);
        token.approve(proxy, 200e18);
        vm.expectEmit(proxy);
        emit TripFundV2.ContributedFor(bob, friend, 200e18);
        vm.prank(bob);
        fund.contributeFor(friend, 200e18);

        assertEq(fund.contributions(friend), 200e18);
        assertEq(fund.contributions(bob), 0);
        assertEq(token.balanceOf(bob), START_BALANCE - 200e18);
        assertEq(fund.totalRaised(), 500e18);

        vm.prank(alice);
        token.approve(proxy, 100e18);
        vm.expectEmit(proxy);
        emit TripFundV1.Contributed(alice, 100e18);
        vm.prank(alice);
        fund.contribute(100e18);

        assertEq(fund.contributions(alice), 400e18);
        assertEq(fund.totalRaised(), 600e18);

        vm.warp(deadline);

        vm.prank(bob);
        vm.expectRevert(TripFundV1.NoContribution.selector);
        fund.refund();

        vm.prank(friend);
        fund.refund();
        assertEq(token.balanceOf(friend), 200e18);
        assertEq(fund.contributions(friend), 0);

        vm.prank(alice);
        fund.refund();
        assertEq(token.balanceOf(alice), START_BALANCE);
        assertEq(token.balanceOf(proxy), 0);
    }

    function test_RevertWhen_ContributeForZeroBeneficiary() public {
        _upgradeToV2();
        vm.prank(bob);
        token.approve(proxy, 100e18);

        vm.prank(bob);
        vm.expectRevert(TripFundV1.ZeroAddress.selector);
        TripFundV2(proxy).contributeFor(address(0), 100e18);

        assertEq(TripFundV2(proxy).totalRaised(), 0);
        assertEq(token.balanceOf(bob), START_BALANCE);
    }
}
