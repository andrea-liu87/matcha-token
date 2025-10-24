// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Matcha
 * @dev ERC-20 token with minting capabilities and supply cap
 */
contract Matcha is ERC20, Ownable {
    error Matcha__NotZeroAddress();
    error Matcha__AmountMustBeMoreThanZero();
    error Matcha__BurnAmountExceedsBalance();
    error Matcha__MintingIsExceedMaxSupply();

    // Maximum number of tokens that can ever exist
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens
    string public constant name = "Matcha Token";
    string public constant symbol = "MATCHA";

    constructor(uint256 initialSupply, address initialOwner) ERC20(name, symbol) Ownable(initialOwner) {
        require(initialSupply <= MAX_SUPPLY, "Initial supply exceeds max supply");
        // Mint initial supply to the contract deployer
        _mint(initialOwner, initialSupply);
    }

    /**
     * @dev Mint new tokens (only contract owner can call this)
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyOwner returns (bool) {
        if (to == address(0)) {
            revert Matcha__NotZeroAddress();
        }
        if (amount <= 0) {
            revert Matcha__AmountMustBeMoreThanZero();
        }
        if (totalSupply() + amount >= MAX_SUPPLY) {
            revert Matcha__MintingIsExceedMaxSupply();
        }
        _mint(to, amount);
        return true;
    }

    /**
     * @dev Burn tokens from caller's balance
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) public {
        uint256 balance = balanceOf(msg.sender);
        if (amount <= 0) {
            revert Matcha__AmountMustBeMoreThanZero();
        }
        if (balance < amount) {
            revert Matcha__BurnAmountExceedsBalance();
        }
        _burn(msg.sender, amount);
    }
}
