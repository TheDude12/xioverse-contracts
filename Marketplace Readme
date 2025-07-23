# 🛒 Xioverse Marketplace Smart Contract

Is a secure, gas-efficient smart contract for buying, selling, bidding, and making offers on **Xioverse NFTs** using **USDC** on the SKALE blockchain.

This marketplace is designed to support both Web3-native users and fiat-friendly flows through **Crossmint-style** bidding and offers. All transactions are royalty-enforced and fully on-chain.

---

## 🛠️ Main Contract: `XioverseMarketplace.sol`

The contract supports direct sales, offers, and auctions of ERC721 tokens, and handles royalties automatically.

### 🔹 Core Features

- **Listing & Buying**
  - List NFTs at fixed USDC price
  - Buyers pay using USDCx (ERC20)
  - 10% royalty auto-split to recipient
  - `buyFor()` enables purchase for others (e.g., via Crossmint)

- **Offers**
  - Users can make time-limited offers
  - Sellers can accept, reject, or ignore offers
  - Refund on cancelation or expiration
  - `makeOfferFor()` allows third-party initiated offers (example crossmint)

- **Auctions**
  - Sellers start time-bound auctions
  - Highest bid wins if auction ends successfully
  - Refund for overbid participants
  - `bidFor()` supports delegated bidding on behalf of others (example crossmint)

- **Royalty System**
  - Configurable royalty recipient (default: team wallet)
  - Enforced at both fixed-price and auction sales

- **Crossmint Mode**
  - Toggle USDC-based third-party bidding/offer system
  - Enables fiat entry points and off-chain integrations

## 🧾 Sale History

Each successful sale or auction is stored on-chain in a history log, allowing users and external apps to track provenance.

