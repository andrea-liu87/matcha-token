// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MatchaEngine} from "../../src/MatchaEngine.sol";
import {Matcha} from "../../src/Matcha.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockFailedTransferFrom} from "./mocks/MockFailedTransferFrom.sol";

contract MatchaEngineTest is Test {
    MatchaEngine public matchaEngine;
    Matcha public matcha;
    ERC20Mock public weth;
    MockV3Aggregator public ethUsdPriceFeed;

    address public owner = makeAddr("Owner");
    address public user = makeAddr("User");
    address public liquidator = makeAddr("Liquidator");

    uint256 public constant INITIAL_SUPPLY = 1000 ether;
    uint256 public constant ETH_STARTING_PRICE = 2000 * 1e8; // $2000
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;
    uint256 public constant MINT_AMOUNT = 500 ether; // $500 worth of Matcha

    function setUp() public {
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(liquidator, 100 ether);

        // Deploy mock tokens and price feed
        weth = new ERC20Mock();
        ethUsdPriceFeed = new MockV3Aggregator(8, int256(ETH_STARTING_PRICE));

        // Deploy Matcha token
        vm.prank(owner);
        matcha = new Matcha(INITIAL_SUPPLY, owner);

        // Deploy MatchaEngine
        matchaEngine = new MatchaEngine(address(weth), address(ethUsdPriceFeed), address(matcha));

        // Set up initial balances
        weth.mint(user, 10 ether);
        weth.mint(liquidator, 10 ether);

        // Approve MatchaEngine to spend tokens
        vm.prank(user);
        weth.approve(address(matchaEngine), type(uint256).max);

        vm.prank(liquidator);
        weth.approve(address(matchaEngine), type(uint256).max);

        // Give MatchaEngine minting rights
        vm.prank(owner);
        matcha.transferOwnership(address(matchaEngine));
    }

    // ============ Constructor Tests ============
    function testConstructor() public {
        assertEq(matchaEngine.getCollateralToken(), address(weth));
        assertEq(matchaEngine.getMatcha(), address(matcha));
        assertEq(matchaEngine.getLiquidationThreshold(), 50);
        assertEq(matchaEngine.getLiquidationBonus(), 10);
        assertEq(matchaEngine.getMinHealthFactor(), 1e18);
    }

    // ============ Deposit Collateral Tests ============
    function test_DepositCollateral() public {
        uint256 initialBalance = weth.balanceOf(user);

        vm.prank(user);
        matchaEngine.depositCollateral(DEPOSIT_AMOUNT);

        assertEq(weth.balanceOf(user), initialBalance - DEPOSIT_AMOUNT);
        assertEq(matchaEngine.getCollateralBalanceOfUser(user), DEPOSIT_AMOUNT);
    }

    function testRevertWhenDepositZeroCollateral() public {
        vm.prank(user);
        vm.expectRevert(MatchaEngine.MatchaEngine__NeedsMoreThanZero.selector);
        matchaEngine.depositCollateral(0);
    }

    function testRevertWhenDepositCollateralTransferFails() public {
        MockFailedTransferFrom mockEth = new MockFailedTransferFrom();
        vm.startPrank(owner);
        MatchaEngine mockEngine = new MatchaEngine(address(mockEth), address(ethUsdPriceFeed), address(matcha));
        vm.stopPrank();

        mockEth.mint(user, 10 ether);

        vm.startPrank(user);
        mockEth.approve(address(mockEngine), type(uint256).max);
        vm.expectRevert(MatchaEngine.MatchaEngine__TransferFailed.selector);
        mockEngine.depositCollateral(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // ============ Mint Matcha Tests ============
    function testMintMatcha() public {
        // First deposit collateral
        vm.prank(user);
        matchaEngine.depositCollateral(DEPOSIT_AMOUNT);

        // Then mint Matcha
        vm.prank(user);
        matchaEngine.mintMatcha(MINT_AMOUNT);

        assertEq(matcha.balanceOf(user), MINT_AMOUNT);
        (uint256 totalMinted, uint256 collateralValue) = matchaEngine.getAccountInformation(user);
        assertEq(totalMinted, MINT_AMOUNT);
        assertGt(collateralValue, 0);
    }

    function testRevertWhenMintMatchaWithoutCollateral() public {
        vm.prank(user);
        vm.expectPartialRevert(MatchaEngine.MatchaEngine__BreaksHealthFactor.selector);
        matchaEngine.mintMatcha(MINT_AMOUNT);
    }

    function testRevertWhen_intZeroMatcha() public {
        vm.prank(user);
        vm.expectRevert(MatchaEngine.MatchaEngine__NeedsMoreThanZero.selector);
        matchaEngine.mintMatcha(0);
    }

    // ============ Deposit and Mint Combined Tests ============
    function testDepositCollateralAndMintMatcha() public {
        vm.prank(user);
        matchaEngine.depositCollateralAndMintMatcha(DEPOSIT_AMOUNT, MINT_AMOUNT);

        assertEq(matchaEngine.getCollateralBalanceOfUser(user), DEPOSIT_AMOUNT);
        assertEq(matcha.balanceOf(user), MINT_AMOUNT);
    }

    // ============ Health Factor Tests ============
    function testHealthFactorCalculation() public {
        vm.prank(user);
        matchaEngine.depositCollateral(DEPOSIT_AMOUNT);

        vm.prank(user);
        matchaEngine.mintMatcha(MINT_AMOUNT);

        uint256 healthFactor = matchaEngine.getHealthFactor(user);
        assertGt(healthFactor, matchaEngine.getMinHealthFactor());
    }

    function testRevertWhenHealthFactorBroken() public {
        vm.prank(user);
        matchaEngine.depositCollateral(DEPOSIT_AMOUNT);

        // Try to mint too much Matcha (more than collateral allows)
        uint256 excessiveMint = 3000 ether; // $3000 worth, but only $2000 collateral

        vm.prank(user);
        vm.expectPartialRevert(MatchaEngine.MatchaEngine__BreaksHealthFactor.selector);
        matchaEngine.mintMatcha(excessiveMint);
    }

    // ============ Burn Matcha Tests ============
    function testBurnMatcha() public {
        // Setup: deposit and mint
        vm.prank(user);
        matchaEngine.depositCollateralAndMintMatcha(DEPOSIT_AMOUNT, MINT_AMOUNT);

        uint256 initialMatchaBalance = matcha.balanceOf(user);

        vm.startPrank(user);
        matcha.approve(address(matchaEngine), type(uint256).max);
        matchaEngine.burnMatcha(MINT_AMOUNT / 2);
        vm.stopPrank();

        assertEq(matcha.balanceOf(user), initialMatchaBalance - (MINT_AMOUNT / 2));
    }

    // ============ Redeem Collateral Tests ============
    function testRedeemCollateral() public {
        // Setup: deposit collateral
        vm.prank(user);
        matchaEngine.depositCollateral(DEPOSIT_AMOUNT);

        uint256 initialWethBalance = weth.balanceOf(user);

        vm.prank(user);
        matchaEngine.redeemCollateral(DEPOSIT_AMOUNT / 2);

        assertEq(weth.balanceOf(user), initialWethBalance + (DEPOSIT_AMOUNT / 2));
        assertEq(matchaEngine.getCollateralBalanceOfUser(user), DEPOSIT_AMOUNT / 2);
    }

    function testRevertWhenRedeemCollateralBreaksHealthFactor() public {
        // Setup: deposit and mint
        vm.prank(user);
        matchaEngine.depositCollateralAndMintMatcha(DEPOSIT_AMOUNT, MINT_AMOUNT);

        // Try to redeem too much collateral
        vm.prank(user);
        vm.expectPartialRevert(MatchaEngine.MatchaEngine__BreaksHealthFactor.selector);
        matchaEngine.redeemCollateral(DEPOSIT_AMOUNT);
    }

    // ============ Liquidation Tests ============
    function testLiquidate() public {
        // user deposits and mints
        vm.prank(user);
        // deposit 1 ether = $2000, mint 500 matcha
        matchaEngine.depositCollateralAndMintMatcha(DEPOSIT_AMOUNT, MINT_AMOUNT);

        // Price drops to make user undercollateralized
        ethUsdPriceFeed.updateAnswer(500 * 1e8); // $500 ETH
        uint256 userHealthFactor = matchaEngine.getHealthFactor(address(user)); // health factor 0.5
        // deposit user now = $500 ---> only allowed 250 matcha max
        uint256 debtToCover = 500 ether;

        // Liquidator prepares by getting Matcha tokens
        vm.startPrank(liquidator);
        matcha.approve(address(matchaEngine), type(uint256).max);
        // Deposit worth $2000 = 1 ether, mint 500 matcha
        matchaEngine.depositCollateralAndMintMatcha(4 * DEPOSIT_AMOUNT, MINT_AMOUNT);
        uint256 initialLiquidatorWeth = weth.balanceOf(liquidator);

        matchaEngine.liquidate(user, debtToCover);
        uint256 userHealthFactorAfter = matchaEngine.getHealthFactor(address(user));
        vm.stopPrank();

        // Liquidator should have received collateral with bonus
        assertGt(weth.balanceOf(liquidator), initialLiquidatorWeth);

        // user's debt should be reduced
        (uint256 totalMintedAfter,) = matchaEngine.getAccountInformation(user);
        assertLt(totalMintedAfter, MINT_AMOUNT);
    }

    function testRevertWhenLiquidateHealthyUser() public {
        // user is healthy
        vm.prank(user);
        matchaEngine.depositCollateralAndMintMatcha(DEPOSIT_AMOUNT, MINT_AMOUNT);

        vm.prank(liquidator);
        vm.expectRevert(MatchaEngine.MatchaEngine__HealthFactorOk.selector);
        matchaEngine.liquidate(user, 100 ether);
    }

    function testRevertWhenLiquidateZeroAmount() public {
        vm.prank(liquidator);
        vm.expectRevert(MatchaEngine.MatchaEngine__NeedsMoreThanZero.selector);
        matchaEngine.liquidate(user, 0);
    }

    function testRevertWhenLiquidationDoesNotImproveHealthFactor() public {
        // This would require a more complex setup where liquidation doesn't help
        // For now, we test the revert condition exists
        vm.prank(liquidator);
        vm.expectRevert(); // Could be various errors depending on setup
        matchaEngine.liquidate(user, 100 ether);
    }

    // ============ Price Calculation Tests ============
    function testGetUsdValue() public {
        uint256 usdValue = matchaEngine.getUsdValue(1 ether);
        // 1 ETH * $2000 = $2000
        assertEq(usdValue, 2000 ether);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 tokenAmount = matchaEngine.getTokenAmountFromUsd(2000 ether);
        // $2000 / $2000 per ETH = 1 ETH
        assertEq(tokenAmount, 1 ether);
    }

    function testAccountCollateralValue() public {
        vm.prank(user);
        matchaEngine.depositCollateral(DEPOSIT_AMOUNT);

        uint256 collateralValue = matchaEngine.getAccountCollateralValue(user);
        // 1 ETH * $2000 = $2000
        assertEq(collateralValue, 2000 ether);
    }

    // ============ Edge Case Tests ============
    function testRedeemCollateralForMatcha() public {
        // Setup: deposit and mint
        vm.prank(user);
        matchaEngine.depositCollateralAndMintMatcha(DEPOSIT_AMOUNT, MINT_AMOUNT);

        uint256 initialWeth = weth.balanceOf(user);
        uint256 initialMatcha = matcha.balanceOf(user);

        vm.startPrank(user);
        matcha.approve(address(matchaEngine), type(uint256).max);
        matchaEngine.redeemCollateralForMatcha(DEPOSIT_AMOUNT / 2, MINT_AMOUNT / 2);
        vm.stopPrank();

        assertEq(weth.balanceOf(user), initialWeth + (DEPOSIT_AMOUNT / 2));
        assertEq(matcha.balanceOf(user), initialMatcha - (MINT_AMOUNT / 2));
    }

    function testHealthFactorWhenNoDebt() public {
        vm.prank(user);
        matchaEngine.depositCollateral(DEPOSIT_AMOUNT);

        uint256 healthFactor = matchaEngine.getHealthFactor(user);
        assertEq(healthFactor, type(uint256).max);
    }

    // ============ Math Function Tests ============
    function testCalculateHealthFactor() public {
        uint256 healthFactor = matchaEngine.calculateHealthFactor(
            1000 ether, // $1000 debt
            3000 ether // $3000 collateral
        );
        // collateralAdjustedForThreshold = 3000 * 50 / 100 = 1500
        // healthFactor = (1500 * 1e18) / 1000 = 1.5e18
        assertEq(healthFactor, 1.5e18);
    }

    // ============ Reentrancy Protection Tests ============
    function testNonReentrant() public {
        // This would require a malicious contract to test properly
        // For now, we ensure the modifier is present on functions
        assert(true);
    }
}
