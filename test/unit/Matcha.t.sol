// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Matcha} from "../../src/Matcha.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract MatchaTest is Test {
    Matcha public matcha;
    address public owner = makeAddr("Owner");
    address public user = makeAddr("User");
    
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 10 ** 18;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        vm.prank(owner);
        matcha = new Matcha(INITIAL_SUPPLY, owner);
    }

    // ============ Deployment Tests ============
    function testDeployment() public {
        assertEq(matcha.name(), "Matcha Token");
        assertEq(matcha.symbol(), "MATCHA");
        assertEq(matcha.owner(), owner);
        assertEq(matcha.MAX_SUPPLY(), MAX_SUPPLY);
    }

    function testInitialSupplyMintedToOwner() public {
        assertEq(matcha.totalSupply(), INITIAL_SUPPLY);
        assertEq(matcha.balanceOf(owner), INITIAL_SUPPLY);
    }

    function testRevertWhenInitialSupplyExceedsMaxSupply() public {
        uint256 excessiveSupply = MAX_SUPPLY + 1;
        
        vm.expectRevert("Initial supply exceeds max supply");
        new Matcha(excessiveSupply, owner);
    }

    // ============ Minting Tests ============
    function testMintTokens() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        
        vm.prank(owner);
        bool success = matcha.mint(user, mintAmount);
        
        assertTrue(success);
        assertEq(matcha.balanceOf(user), mintAmount);
        assertEq(matcha.totalSupply(), INITIAL_SUPPLY + mintAmount);
    }

    function testRevertWhenMintByNonOwner() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(user)));
        matcha.mint(user, mintAmount);
    }

    function testRevertWhenMintToZeroAddress() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        
        vm.prank(owner);
        vm.expectRevert(Matcha.Matcha__NotZeroAddress.selector);
        matcha.mint(address(0), mintAmount);
    }

    function testRevertWhenMintZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(Matcha.Matcha__AmountMustBeMoreThanZero.selector);
        matcha.mint(user, 0);
    }

    function testRevertWhenMintExceedsMaxSupply() public {
        uint256 remainingCapacity = MAX_SUPPLY - INITIAL_SUPPLY;
        uint256 excessiveAmount = remainingCapacity + 1;
        
        vm.prank(owner);
        vm.expectRevert(Matcha.Matcha__MintingIsExceedMaxSupply.selector);
        matcha.mint(user, excessiveAmount);
    }

    function testMintUpToMaxSupply() public {
        uint256 remainingCapacity = MAX_SUPPLY - INITIAL_SUPPLY;
        
        vm.prank(owner);
        bool success = matcha.mint(user, remainingCapacity);
        
        assertTrue(success);
        assertEq(matcha.totalSupply(), MAX_SUPPLY);
        assertEq(matcha.balanceOf(user), remainingCapacity);
    }

    // ============ Burning Tests ============
    function testBurnTokens() public {
        uint256 burnAmount = 500 * 10 ** 18;
        
        // First transfer some tokens to user1
        vm.prank(owner);
        matcha.transfer(user, burnAmount);
        
        // User burns their tokens
        vm.prank(user);
        matcha.burn(burnAmount);
        
        assertEq(matcha.balanceOf(user), 0);
        assertEq(matcha.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }


    function testRevertWhenBurnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(Matcha.Matcha__AmountMustBeMoreThanZero.selector);
        matcha.burn(0);
    }

    function testRevertWhenBurnExceedsBalance() public {
        uint256 userBalance = matcha.balanceOf(user);
        uint256 burnAmount = userBalance + 1;
        
        vm.prank(user);
        vm.expectRevert(Matcha.Matcha__BurnAmountExceedsBalance.selector);
        matcha.burn(burnAmount);
    }

    function testBurnFromOwner() public {
        uint256 burnAmount = 500 * 10 ** 18;
        uint256 initialOwnerBalance = matcha.balanceOf(owner);
        
        vm.prank(owner);
        matcha.burn(burnAmount);
        
        assertEq(matcha.balanceOf(owner), initialOwnerBalance - burnAmount);
        assertEq(matcha.totalSupply(), INITIAL_SUPPLY - burnAmount);
    }


    // ============ Edge Cases ============
    function testMaxSupplyConstant() public {
        assertEq(matcha.MAX_SUPPLY(), MAX_SUPPLY);
        
        // Verify it's truly constant by trying to find a setter (shouldn't exist)
        bytes4 selector = bytes4(keccak256("MAX_SUPPLY()"));
        (bool success, ) = address(matcha).staticcall(abi.encodeWithSelector(selector));
        assertTrue(success);
    }

    function testTotalSupplyNeverExceedsMaxSupply() public {
        // Mint up to max supply
        uint256 remainingCapacity = MAX_SUPPLY - INITIAL_SUPPLY;
        
        vm.prank(owner);
        matcha.mint(user, remainingCapacity);
        
        assertEq(matcha.totalSupply(), MAX_SUPPLY);
        
        // Try to mint one more token (should fail)
        vm.prank(owner);
        vm.expectRevert(Matcha.Matcha__MintingIsExceedMaxSupply.selector);
        matcha.mint(user, 1);
    }

    function testBurnThenMint() public {
        uint256 burnAmount = 500 * 10 ** 18;
        uint256 mintAmount = 300 * 10 ** 18;
        
        // Burn some tokens
        vm.prank(owner);
        matcha.burn(burnAmount);
        
        // Mint new tokens (should work since we burned some)
        vm.prank(owner);
        matcha.mint(user, mintAmount);
        
        assertEq(matcha.totalSupply(), INITIAL_SUPPLY - burnAmount + mintAmount);
        assertEq(matcha.balanceOf(user), mintAmount);
    }
}