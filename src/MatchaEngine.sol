// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Matcha} from "./Matcha.sol";
import {OracleLib} from "./libraries/OracleLib.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "forge-std/Test.sol";

/*
 * @title MatchaEngine
 *
 * The system is deisgned to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exegenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 * - Collateral token is ETH
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only ETH.
 *
 * @notice This contract is the core of the Matcha token system. It handles all the logic
 * for minting and redeeming Matcha, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract MatchaEngine is ReentrancyGuard {
    ///////////////////
    // Erros
    ///////////////////
    error MatchaEngine__NeedsMoreThanZero();
    error MatchaEngine__TokenNotAllowed(address token);
    error MatchaEngine__TransferFailed();
    error MatchaEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error MatchaEngine__MintFailed();
    error MatchaEngine__HealthFactorOk();
    error MatchaEngine__HealthFactorNotImproved();

    ///////////////////
    // Types
    ///////////////////
    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables
    ///////////////////
    Matcha private immutable i_matcha;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    address private s_collateralToken;
    address private s_collateralTokenPriceFeed;
    // user  -> amountCollateralDeposit
    mapping(address => uint256) private s_userToAmountDeposited;
    // user -> amountMatchaMinted
    mapping(address => uint256) private s_userToMatchaMinted;

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, uint256 indexed amountCollateral, address from, address to); // if from != to, then it was liquidated

    ///////////////////
    // Modifiers
    ///////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert MatchaEngine__NeedsMoreThanZero();
        }
        _;
    }

    ///////////////////
    // Functions
    ///////////////////
    constructor(address ethAddress, address ethPriceFeedAddress, address matchaAddress) {
        s_collateralTokenPriceFeed = ethPriceFeedAddress; // eth pricefeed address
        s_collateralToken = ethAddress;
        i_matcha = Matcha(matchaAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////
    /*
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountMatchaToMint: The amount of Matcha you want to mint
     * @notice This function will deposit your collateral and mint Matcha in one transaction
     */
    function depositCollateralAndMintMatcha(uint256 amountCollateral, uint256 amountMatchaToMint) external {
        depositCollateral(amountCollateral);
        mintMatcha(amountMatchaToMint);
    }

    /*
     * @param amountCollateral: The amount of collateral you're depositing
     * @param amountMatchaToBurn: The amount of Matcha you want to burn
     * @notice This function will deposit your collateral and burn Matcha in one transaction
     */
    function redeemCollateralForMatcha(uint256 amountCollateral, uint256 amountMatchaToBurn)
        external
        moreThanZero(amountCollateral)
    {
        _burnMatcha(amountMatchaToBurn, msg.sender, msg.sender);
        _redeemCollateral(amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param amountCollateral: The amount of collateral you're redeeming
     * @notice This function will redeem your collateral.
     * @notice If you have Matcha minted, you will not be able to redeem until you burn your Matcha
     */
    function redeemCollateral(uint256 amountCollateral) external moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(amountCollateral, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice careful! You'll burn your Matcha here! Make sure you want to do this...
     * @dev you might want to use this if you're nervous you might get liquidated and want to just burn
     * you Matcha but keep your collateral in.
     */
    function burnMatcha(uint256 amount) external moreThanZero(amount) {
        _burnMatcha(amount, msg.sender, msg.sender);
        revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit...
    }

    /*
     * Liquidator will get collateral from the user who is insolvent.
     * In return, liquidator have to burn some Matcha to pay off their debt.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of Matcha you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     */
    function liquidate(address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert MatchaEngine__HealthFactorOk();
        }
        // If covering 100 Matcha, we need to $100 of collateral
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(debtToCover);
        // And give them a 10% bonus
        // So we are giving the liquidator $110 of ETH for 100 Matcha
        // We should implement a feature to liquidate in the event the protocol is insolvent
        // And sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        // Burn Matcha equal to debtToCover
        // Figure out how much collateral to recover based on how much burnt
        _redeemCollateral(tokenAmountFromDebtCovered + bonusCollateral, user, msg.sender);
        console.log("redeem colateral ", tokenAmountFromDebtCovered + bonusCollateral);
        _burnMatcha(debtToCover, user, msg.sender);
        console.log("burn matcha ", debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        console.log("health factor ", endingUserHealthFactor);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert MatchaEngine__HealthFactorNotImproved();
        }
        revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Public Functions
    ///////////////////
    /*
     * @param amountMatchaToMint: The amount of Matcha you want to mint
     * You can only mint Matcha if you hav enough collateral
     */
    function mintMatcha(uint256 amountMatchaToMint) public moreThanZero(amountMatchaToMint) nonReentrant {
        s_userToMatchaMinted[msg.sender] += amountMatchaToMint;
        revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_matcha.mint(msg.sender, amountMatchaToMint);
        if (minted != true) {
            revert MatchaEngine__MintFailed();
        }
    }

    /*
     * @param amountCollateral: The amount of collateral you're depositing
     */
    function depositCollateral(uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        s_userToAmountDeposited[msg.sender] += amountCollateral;
        emit CollateralDeposited(msg.sender, amountCollateral);
        bool success = IERC20(s_collateralToken).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert MatchaEngine__TransferFailed();
        }
    }

    ///////////////////
    // Private Functions
    ///////////////////
    function _redeemCollateral(uint256 amountCollateral, address from, address to) private {
        if (amountCollateral > s_userToAmountDeposited[from]) {
            amountCollateral = s_userToAmountDeposited[from];
        }
        s_userToAmountDeposited[from] -= amountCollateral;
        emit CollateralRedeemed(from, amountCollateral, from, to);
        bool success = IERC20(s_collateralToken).transfer(to, amountCollateral);
        if (!success) {
            revert MatchaEngine__TransferFailed();
        }
    }

    function _burnMatcha(uint256 amountMatchaToBurn, address onBehalfOf, address matchaFrom) private {
        s_userToMatchaMinted[onBehalfOf] -= amountMatchaToBurn;

        bool success = i_matcha.transferFrom(matchaFrom, address(this), amountMatchaToBurn);
        if (!success) {
            revert MatchaEngine__TransferFailed();
        }
        i_matcha.burn(amountMatchaToBurn);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalMatchaMinted, uint256 collateralValueInUsd)
    {
        totalMatchaMinted = s_userToMatchaMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalMatchaMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalMatchaMinted, collateralValueInUsd);
    }

    /**
     *
     * @param amount Amount of Matcha to be valued as USD
     */
    function _getUsdValue(uint256 amount) private view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collateralTokenPriceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function _calculateHealthFactor(uint256 totalMatchaMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalMatchaMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * 1e18) / totalMatchaMinted;
    }

    function revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert MatchaEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    function calculateHealthFactor(uint256 totalMatchaMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalMatchaMinted, collateralValueInUsd);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalMatchaMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getUsdValue(
        uint256 amount // in WEI
    ) external view returns (uint256) {
        return _getUsdValue(amount);
    }

    function getCollateralBalanceOfUser(address user) external view returns (uint256) {
        return s_userToAmountDeposited[user];
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        uint256 amount = s_userToAmountDeposited[user];
        totalCollateralValueInUsd += _getUsdValue(amount);
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_collateralTokenPriceFeed);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getCollateralToken() external view returns (address) {
        return s_collateralToken;
    }

    function getMatcha() external view returns (address) {
        return address(i_matcha);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_collateralTokenPriceFeed;
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
}
