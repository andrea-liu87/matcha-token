<h1> Matcha — Matcha - Dollar Stablecoin</h1>

A fully on-chain **overcollateralized stablecoin protocol** built with Solidity and Foundry for minting, burning, redeeming, and liquidating positions.

> **Smart Contracts (Deployed on Ethereum Sepolia Testnet)**  
> 📝 [StableCoin](https://sepolia.etherscan.io/token/contract address)
> 📝 [Matcha Engine Protocol](https://sepolia.etherscan.io/address/contract address)


> **Live Demo *Building the Matcha Dollar***  
> 🔗 [Open dApp website](https://xxx.vercel.app/)
> 🎥 [Watch Demo on Loom](https://www.loom.com/share/2c9acdae45d6435baffbe3160cfb255c)
![UI](frontend-integration/public/desktop.png)

---

## Overview

Matcha is an exogenous decentralized stablecoin backed by **wETH collateral** and designed to maintain stability through **overcollateralization** and **liquidation mechanisms**. Relative Stability Pegged -> $1.00

Users can:

- 💰 Deposit ETH  to **mint** Matcha  
- 🔥 **Burn** Matcha to reduce debt  
- ♻️ **Redeem** collateral  
- ⚖️ **Liquidate** unhealthy positions  

The UI provides real-time updates on collateral value, minting limits, and health factor metrics.

---

## Smart Contract Architecture

The MatchaEngine contract is designed to support collateral assets. For this version, the frontend implements the flow only for wETH to simplify the user experience. The backend is built in Solidity using **Foundry** for deployment, testing, and verification.

### Core Contracts

- **MatchaDEngine.sol**:Core logic for minting, burning, redeeming, and liquidation
- **Matcha.sol**: ERC20-compliant stablecoin token
- **PriceFeed integration**: Chainlink AggregatorV3Interface for real-time ETH/USD price updates

### Key Mechanisms

- **Overcollateralization** — prevents undercollateralized loans.  
- **Health Factor** — determines user’s liquidation risk.  
  - `> 1.5` → Safe  
  - `1.2–1.5` → At Risk  
  - `1.0–1.2` → Danger Zone  
  - `< 1.0` → Liquidatable  

- **Liquidation Bonus (10%)** — incentivizes third parties to liquidate unsafe positions.  
- **Chainlink Price Feeds** — ensure consistent USD valuations.

---


### Core Sections

- **Deposit & Mint** | Deposit ETH → Mint Matcha (in one flow)
- **Burn Matcha** | Repay debt to increase your Health Factor 
- **Redeem Collateral** | Withdraw ETH based on remaining collateral 
- **Liquidate** | Cover another user’s debt and claim their collateral (with bonus)

---

## Smart Contract Flow

```text
Deposit ETH  →  MatchaEngine wraps  →  Mint Matcha
Burn Matcha    →  Repay debt       →  Increase Health Factor
Redeem ETH   →  Withdraw ETH    →  Decrease Health Factor
Liquidate    →  Burn Matcha       →  Receive collateral (with bonus)
```

---

## Local Installation

### Smart Contracts Setup

```bash
git clone https://github.com/andrea-liu87/matcha-token/
forge build
forge coverage
```

![Tests coverage](/frontend-integration/public/testcoverage.png)