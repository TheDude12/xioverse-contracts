# ⌚ Xioverse Smart Contracts

Welcome to the official smart contract repository for **Xioverse** — a next-gen cross-game NFT platform centered around modular AR watches.

These contracts are written in Solidity and deployed on the [SKALE Nebula Testnet](https://skale.space). They power the minting, upgrading, dismantling, and combining of Xioverse NFT watches — dynamic on-chain assets designed for interoperability across games and experiences.

---

## 🛠️ Main Contract: `Xioverse.sol`

This is the core ERC721-based smart contract implementing the following features:

### 🔹 Minting Logic
- Supports **OG**, **Whitelist (WL)**, and **Public** mint phases
- OG wallets get **1 free mint**
- Minting requires **USDCx** (super token) approval
- Fiat-compatible via Crossmint

### 🔹 Trait-Based Modular NFTs
- Each watch is composed of traits: `Strap`, `Dial`, `Item`, `Hologram`
- Each watch has a **DNA string** representing the trait combination
- Modular design allows **upgrades**, **swapping**, and **dismantling** of traits on-chain

### 🔹 On-Chain Utilities
- `assemble()` and `dismantle()` functions for trait composition and decomposition
- `combine()` logic to merge or upgrade items
- Watch NFTs can be **projected in AR**, filmed, and customized through the Xioverse app

---

## 🔧 Companion Library: `stringUtils.sol`

- Provides internal helper functions to parse and manipulate DNA strings
- Enables trait identification and extraction
- Helps determine rarity and uniqueness based on DNA composition

---

## 🪙 Currency & Approvals

- All transactions use **USDCx** on SKALE
- Minting flow:
  1. Check wallet eligibility
  2. Approve USDCx spend
  3. Mint NFT
- Also supports **sFUEL auto-top-up** for Web3 wallets via backend when needed

---

## 🌐 Ecosystem Compatibility

- NFTs are **game-ready** and meant to be used across multiple titles
- Built-in **referral system** and **listing metadata**
- Integrates with Crossmint to onboard Web2 users via email and credit card

---

## 📲 Frontend and App Integration

- Fully functional minting frontend: [https://mint.xioverse.com](https://mint.xioverse.com)
- Watch NFTs can be:
  - Dismantled or upgraded in-app
  - Projected in Augmented Reality (AR)
  - Shared via video or image using the mobile UI

---

## 📄 License

MIT — Free to use with attribution.

---

## 🔗 Useful Links

- 🌐 Website: [https://xioverse.com](https://xioverse.com)
- 📖 Whitepaper: [Xioverse Whitepaper](https://xioverse.com/wp-content/uploads/2024/04/Xioverse-Whitepaper.pdf)
- 📊 Project Deck: [Xioverse Project Deck](https://xioverse.com/wp-content/uploads/2024/01/Xioverse-Deck.pdf)
- 🎮 Mint Page: [https://mint.xioverse.com](https://mint.xioverse.com)

---

### 🚀 Follow the journey, become a Clockhead, and join the revolution.
