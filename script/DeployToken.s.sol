// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Matcha} from "../src/Matcha.sol";

contract DeployToken is Script {
    function run() external {
        // Load deployer's private key from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        // Token configuration parameters
        uint256 initialSupply = 100_000_000 * 10 ** 18; // 100 million tokens

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy the token contract
        Matcha token = new Matcha(initialSupply, deployerAddress);

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log deployment information
        console.log("Token deployed to:", address(token));
        console.log("Token name:", token.name());
        console.log("Token symbol:", token.symbol());
        console.log("Initial supply:", token.totalSupply());
        console.log("Deployer balance:", token.balanceOf(deployerAddress));
    }
}
