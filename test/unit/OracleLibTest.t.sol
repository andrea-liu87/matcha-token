// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {OracleLib} from "../../src/libraries/OracleLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";

contract OracleLibTest is Test {
    MockV3Aggregator public ethUsdPriceFeed;
    uint256 public constant ETH_STARTING_PRICE = 2000 * 1e8; // $2000

    function setUp() public {
        ethUsdPriceFeed = new MockV3Aggregator(8, int256(ETH_STARTING_PRICE));
    }

    function testStaleCheckCorrectAnswer() public {
        (, int256 answer,,,) = OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(ethUsdPriceFeed)));
        assertEq(uint256(answer), ETH_STARTING_PRICE);
    }

    function testPriceRevertsOnStaleCheck() public {
        vm.warp(block.timestamp + 4 hours);
        vm.expectRevert(OracleLib.OracleLib__StalePrice.selector);
        OracleLib.staleCheckLatestRoundData(AggregatorV3Interface(address(ethUsdPriceFeed)));
    }

    function testGetTimeout() public {
        uint256 realTimeout = OracleLib.getTimeout(AggregatorV3Interface(address(ethUsdPriceFeed)));
        uint256 expectedTimeout = 3 hours;
        assertEq(realTimeout, expectedTimeout);
    }
}
