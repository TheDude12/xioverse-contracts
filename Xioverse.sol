// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {stringUtils} from "./stringUtils.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";

contract Xioverse is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Pausable,
    Ownable,
    ReentrancyGuard,
    AccessControl,
    ERC2981
{
    // =========================
    // ROLES
    // =========================
    bytes32 public constant COMBO_MANAGER_ROLE =
        keccak256("COMBO_MANAGER_ROLE");
    // =========================
    // VARIABLES
    // =========================
    enum Level {
        L0,
        L1,
        L2,
        L3
    }

    uint256 public upgradeFeeL0L1 = 2500000;
    uint256 public upgradeFeeL1L2 = 5000000;
    uint256 public upgradeFeeL2L3 = 10000000;

    address public resaleWallet;
    address public junkyardWallet;

    struct TraitConfig {
        uint256 level;
        string base;
    }

    // Maps normalized trait -> its config (level, base group)
    mapping(string => TraitConfig) public traitsConfiguration;

    struct TraitGroup {
        mapping(uint256 => string) entries;
        uint256 index; // total inserted
        uint256 indexMinted; // how many have been minted
    }

    // traitGroups[groupCode][level] => TraitGroup
    mapping(string => mapping(Level => TraitGroup)) private traitGroups;

    // ========================= FOR DELETE
    function getTraitGroupIndex(
        string memory groupCode
    ) public view returns (uint256) {
        return traitGroups[groupCode][Level.L0].index;
    }

    struct PrivateCombination {
        string dna;
        string gift;
    }
    struct Combination {
        bool owned;
        bool minted;
        bool reserved;
        string dna;
        int256 id;
    }
    struct referralPoint {
        address walletAddress;
        uint256 currentReferralPoints;
        uint256 overAllReferralPoints;
    }

    uint256 private _nextTokenId;
    uint256 public _mintedResered;
    uint256 public mintingFee;
    string private _baseTokenURI;
    uint256 public _maxReservedCombination;
    uint256 private _currentReservedCombination;
    uint256 private _referral;

    IERC20 public usdcToken;
    IERC20 public xioToken;
    bool public isOG;
    bool public isWL;
    bool public isPublic;

    PrivateCombination[50000] private privateCombinations;
    mapping(string => Combination) public combinations;
    mapping(uint256 => string) public idCombinations;
    mapping(string => uint256) public combinationsId;
    mapping(address => bool) public ogWallets;
    mapping(address => bool) public ogUnusedWallets;
    mapping(address => bool) public wlWallets;
    mapping(string => referralPoint) public referralPoints;
    mapping(address => string) public walletReferralIds;
    mapping(address => bool) public AuthorizedContracts;

    bool public panicMode;

    // =========================
    // ROYALTY
    // =========================
    uint96 public royaltyBasisPoints;

    struct TraitParts {
        string strap;
        string dial;
        string item;
        string hologram;
    }

    // =========================
    // EVENTS
    // =========================

    event EmergencyWithdrawal(
        address indexed to,
        uint256 amount,
        string reason
    );

    // =========================
    // MODIFIERS
    // =========================
    modifier notInPanic() {
        require(!panicMode, "Contract in panic mode");
        _;
    }

    // =========================
    // CONSTRUCTOR
    // =========================
    constructor(
        address initialOwner,
        address _usdcToken
    ) ERC721("xioverse", "XIOVERSE") Ownable(initialOwner) {
        _pause();
        usdcToken = IERC20(_usdcToken);
        mintingFee = 1000000;
        _baseTokenURI = "http://assets.xioverse.com/";
        _maxReservedCombination = 50000;
        isOG = true;
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(COMBO_MANAGER_ROLE, initialOwner);
        royaltyBasisPoints = 1000; // 10%
        _setDefaultRoyalty(initialOwner, royaltyBasisPoints);
    }

    // =========================
    // FUNCTIONS
    // =========================

    // ---- Settings and Admin ----
    function setAuthorizedContract(
        address _authorizedContract,
        bool _isAuthorizedContract
    ) public onlyOwner {
        AuthorizedContracts[_authorizedContract] = _isAuthorizedContract;
    }

    function setUpgradeFee(Level from, Level to, uint256 fee) public onlyOwner {
        if (from == Level.L0 && to == Level.L1) {
            upgradeFeeL0L1 = fee;
        } else if (from == Level.L1 && to == Level.L2) {
            upgradeFeeL1L2 = fee;
        } else if (from == Level.L2 && to == Level.L3) {
            upgradeFeeL2L3 = fee;
        } else {
            revert("Invalid upgrade levels");
        }
    }

    function setResaleWallet(address wallet) public onlyOwner {
        resaleWallet = wallet;
    }

    function setJunkyardWallet(address wallet) public onlyOwner {
        junkyardWallet = wallet;
    }

    function setUsdcToken(address _usdcToken) public onlyOwner {
        usdcToken = IERC20(_usdcToken);
    }

    function setXioToken(address _xioToken) public onlyOwner {
        xioToken = IERC20(_xioToken);
    }

    function setBaseURI(string memory newBaseURI) public onlyOwner {
        _baseTokenURI = newBaseURI;
    }

    function setMintingFee(uint256 newFee) public onlyOwner {
        mintingFee = newFee;
    }

    function changeSmartContractStatus(uint256 status) public onlyOwner {
        if (status == 1) {
            isOG = true;
            isWL = false;
            isPublic = false;
        }
        if (status == 2) {
            isOG = false;
            isWL = true;
            isPublic = false;
        }
        if (status == 3) {
            isOG = false;
            isWL = false;
            isPublic = true;
        }
    }

    function setOGWallets(address[] memory walletOGs) public onlyOwner {
        for (uint256 i = 0; i < walletOGs.length; i++) {
            ogWallets[walletOGs[i]] = true;
            ogUnusedWallets[walletOGs[i]] = true;
        }
    }

    function removeOGWallets(address[] memory walletOGs) public onlyOwner {
        for (uint256 i = 0; i < walletOGs.length; i++) {
            ogWallets[walletOGs[i]] = false;
            ogUnusedWallets[walletOGs[i]] = false;
        }
    }

    function setWLWallets(address[] memory walletWLs) public onlyOwner {
        for (uint256 i = 0; i < walletWLs.length; i++) {
            wlWallets[walletWLs[i]] = true;
        }
    }

    /**
     * @notice Change the royalty rate for all future secondary sales.
     * @param newBasisPoints the new royalty, in basis points (max 10000).
     */
    function setRoyalty(uint96 newBasisPoints) external onlyOwner {
        require(newBasisPoints <= 10000, "Max 100%");
        royaltyBasisPoints = newBasisPoints;
        _setDefaultRoyalty(owner(), royaltyBasisPoints);
    }

    function setPrivateCombinations(
        uint256[] memory indices,
        string[] memory dnas,
        string[] memory gifts
    ) public onlyRole(COMBO_MANAGER_ROLE) {
        require(
            indices.length == dnas.length && dnas.length == gifts.length,
            "Length mismatch"
        );
        for (uint256 i = 0; i < indices.length; i++) {
            require(indices[i] < 50000, "Index out of bounds");
            privateCombinations[indices[i]] = PrivateCombination(
                dnas[i],
                gifts[i]
            );
        }
    }

    function insertCombinations(
        string[] memory keys,
        string[] memory dnas
    ) public onlyRole(COMBO_MANAGER_ROLE) {
        require(
            keys.length == dnas.length,
            "Input arrays must have the same length"
        );
        for (uint256 i = 0; i < keys.length; i++) {
            combinations[keys[i]] = Combination({
                owned: false,
                minted: false,
                reserved: true,
                dna: dnas[i],
                id: -1
            });
        }
    }

    // ---- Trait Management ----
    function setTraitConfig(
        string memory baseGroup,
        uint256 level,
        string memory trait
    ) public onlyRole(COMBO_MANAGER_ROLE) {
        traitsConfiguration[trait] = TraitConfig(level, baseGroup);
    }

    function addTrait(
        string memory groupCode,
        Level level,
        string memory trait
    ) public onlyRole(COMBO_MANAGER_ROLE) {
        TraitGroup storage group = traitGroups[groupCode][level];
        group.entries[group.index] = trait;
        group.index++;
    }

    function getTrait(
        string memory groupCode,
        Level level,
        uint256 i
    ) public view returns (string memory) {
        return traitGroups[groupCode][level].entries[i];
    }

    function getTraitCount(
        string memory groupCode,
        Level level
    ) public view returns (uint256) {
        return traitGroups[groupCode][level].index;
    }

    function getNextUpgradeableTrait(
        string memory fullTraitCode
    ) public view returns (Level nextLevel, string memory nextTrait) {
        // string memory normalized = stringUtils.normalizeTrait(fullTraitCode);

        TraitConfig memory config = traitsConfiguration[fullTraitCode];
        require(config.level < 3, "Max upgrade level reached");

        string memory groupCode = config.base;
        nextLevel = Level(config.level + 1);
        TraitGroup storage nextGroup = traitGroups[groupCode][nextLevel];

        // require(nextGroup.indexMinted, "Trait group does not exist");

        require(
            nextGroup.indexMinted < nextGroup.index,
            "No traits left to mint"
        );

        nextTrait = nextGroup.entries[nextGroup.indexMinted];
    }

    function incrementMinted(string memory fullTraitCode) private {
        // string memory normalized = stringUtils.normalizeTrait(fullTraitCode);

        TraitConfig memory config = traitsConfiguration[fullTraitCode];
        require(config.level < 2, "Max upgrade level reached");

        string memory groupCode = config.base;
        Level nextLevel = Level(config.level + 1);
        TraitGroup storage nextGroup = traitGroups[groupCode][nextLevel];

        require(
            nextGroup.indexMinted < nextGroup.index,
            "No traits left to mint"
        );
        nextGroup.indexMinted++;
    }

    // ---- Minting ----
    function mint(
        address to,
        uint256 amount,
        string memory refID
    ) public nonReentrant notInPanic {
        uint256 userBalance = usdcToken.balanceOf(msg.sender);
        uint256 allowance = usdcToken.allowance(msg.sender, address(this));
        uint256 totalCost = 0;
        require(
            ((isPublic) ||
                ((isOG) && (ogWallets[to] == true)) ||
                ((isWL) &&
                    ((wlWallets[to] == true) || (ogWallets[to] == true)))),
            "This wallet is not listed to mint in this stage"
        );
        require(
            amount + _mintedResered < _maxReservedCombination,
            "You have exceeded the Max Reserved Combination"
        );
        if (ogUnusedWallets[to] == true) {
            require(
                userBalance >= mintingFee * (amount - 1),
                "Insufficient minting fee"
            );
            require(allowance >= mintingFee * (amount - 1), "Not Allowed 1");
            totalCost = mintingFee * (amount - 1);
        } else {
            require(
                userBalance >= mintingFee * amount,
                "Insufficient minting fee"
            );
            require(allowance >= mintingFee * amount, "Not Allowed");
            totalCost = mintingFee * amount;
        }
        require(
            (keccak256(bytes(refID)) == keccak256(bytes("xio10000"))) ||
                referralPoints[refID].walletAddress != address(0),
            "Invalid refID"
        );
        usdcToken.transferFrom(msg.sender, address(this), totalCost);
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenDna = _nextTokenId++;
            uint256 tokenGift = _nextTokenId++;
            uint256 tokenStrap = _nextTokenId++;
            uint256 tokenDial = _nextTokenId++;
            uint256 tokenItem = _nextTokenId++;
            uint256 tokenHologram = _nextTokenId++;
            _safeMint(to, tokenDna);
            _mintedResered += 1;
            _safeMint(to, tokenGift);
            _safeMint(address(owner()), tokenStrap);
            _safeMint(address(owner()), tokenDial);
            _safeMint(address(owner()), tokenItem);
            _safeMint(address(owner()), tokenHologram);
            uint256 index = _currentReservedCombination++;
            (string memory dna, string memory gift) = getPrivateCombination(
                index
            );
            (
                string memory compoKey,
                string memory strap,
                string memory dial,
                string memory item,
                string memory hologram
            ) = stringUtils.processString(dna);
            idCombinations[(_nextTokenId - 6)] = dna;
            idCombinations[(_nextTokenId - 5)] = gift;
            idCombinations[(_nextTokenId - 4)] = strap;
            idCombinations[(_nextTokenId - 3)] = dial;
            idCombinations[(_nextTokenId - 2)] = item;
            idCombinations[(_nextTokenId - 1)] = hologram;
            combinationsId[dna] = _nextTokenId - 6;
            combinationsId[gift] = _nextTokenId - 5;
            combinationsId[strap] = _nextTokenId - 4;
            combinationsId[dial] = _nextTokenId - 3;
            combinationsId[item] = _nextTokenId - 2;
            combinationsId[hologram] = _nextTokenId - 1;
            combinations[compoKey] = Combination({
                owned: true,
                minted: true,
                reserved: false,
                dna: dna,
                id: int256(_nextTokenId) - 6
            });
        }
        ogUnusedWallets[to] = false;
        assignReferralID(to);
        if (
            keccak256(abi.encodePacked(refID)) !=
            keccak256(abi.encodePacked("xio10000"))
        ) {
            reward(refID, amount);
        }
    }

    function mintWithoutReferral(
        address to,
        uint256 amount
    ) public nonReentrant notInPanic {
        uint256 userBalance = usdcToken.balanceOf(msg.sender);
        uint256 allowance = usdcToken.allowance(msg.sender, address(this));
        uint256 totalCost = 0;
        require(
            ((isPublic) ||
                ((isOG) && (ogWallets[to] == true)) ||
                ((isWL) &&
                    ((wlWallets[to] == true) || (ogWallets[to] == true)))),
            "This wallet is not listed to mint in this stage"
        );
        require(
            amount + _mintedResered < _maxReservedCombination,
            "You have exceeded the Max Reserved Combination"
        );
        if (ogUnusedWallets[to] == true) {
            require(
                userBalance >= mintingFee * (amount - 1),
                "Insufficient minting fee"
            );
            require(allowance >= mintingFee * (amount - 1), "Not Allowed 1");
            totalCost = mintingFee * (amount - 1);
        } else {
            require(
                userBalance >= mintingFee * amount,
                "Insufficient minting fee"
            );
            require(allowance >= mintingFee * amount, "Not Allowed");
            totalCost = mintingFee * amount;
        }
        usdcToken.transferFrom(msg.sender, address(this), totalCost);
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenDna = _nextTokenId++;
            uint256 tokenGift = _nextTokenId++;
            uint256 tokenStrap = _nextTokenId++;
            uint256 tokenDial = _nextTokenId++;
            uint256 tokenItem = _nextTokenId++;
            uint256 tokenHologram = _nextTokenId++;
            _safeMint(to, tokenDna);
            _mintedResered += 1;
            _safeMint(to, tokenGift);
            _safeMint(address(owner()), tokenStrap);
            _safeMint(address(owner()), tokenDial);
            _safeMint(address(owner()), tokenItem);
            _safeMint(address(owner()), tokenHologram);
            uint256 index = _currentReservedCombination++;
            (string memory dna, string memory gift) = getPrivateCombination(
                index
            );
            (
                string memory compoKey,
                string memory strap,
                string memory dial,
                string memory item,
                string memory hologram
            ) = stringUtils.processString(dna);
            idCombinations[(_nextTokenId - 6)] = dna;
            idCombinations[(_nextTokenId - 5)] = gift;
            idCombinations[(_nextTokenId - 4)] = strap;
            idCombinations[(_nextTokenId - 3)] = dial;
            idCombinations[(_nextTokenId - 2)] = item;
            idCombinations[(_nextTokenId - 1)] = hologram;
            combinationsId[dna] = _nextTokenId - 6;
            combinationsId[gift] = _nextTokenId - 5;
            combinationsId[strap] = _nextTokenId - 4;
            combinationsId[dial] = _nextTokenId - 3;
            combinationsId[item] = _nextTokenId - 2;
            combinationsId[hologram] = _nextTokenId - 1;
            combinations[compoKey] = Combination({
                owned: true,
                minted: true,
                reserved: false,
                dna: dna,
                id: int256(_nextTokenId) - 6
            });
        }
        ogUnusedWallets[to] = false;
        assignReferralID(to);
    }

    function reward(string memory refID, uint256 points) internal {
        for (uint256 i = 0; i < points; i++) {
            referralPoints[refID].currentReferralPoints += 1;
            referralPoints[refID].overAllReferralPoints += 1;
            if (referralPoints[refID].currentReferralPoints >= 4) {
                if (1 + _mintedResered < _maxReservedCombination) {
                    internalMint(referralPoints[refID].walletAddress);
                    referralPoints[refID].currentReferralPoints -= 4;
                }
            }
        }
    }

    function internalMint(address to) internal {
        uint256 tokenDna = _nextTokenId++;
        uint256 tokenGift = _nextTokenId++;
        uint256 tokenStrap = _nextTokenId++;
        uint256 tokenDial = _nextTokenId++;
        uint256 tokenItem = _nextTokenId++;
        uint256 tokenHologram = _nextTokenId++;
        _safeMint(to, tokenDna);
        _mintedResered += 1;
        _safeMint(to, tokenGift);
        _safeMint(address(owner()), tokenStrap);
        _safeMint(address(owner()), tokenDial);
        _safeMint(address(owner()), tokenItem);
        _safeMint(address(owner()), tokenHologram);
        uint256 index = _currentReservedCombination++;
        (string memory dna, string memory gift) = getPrivateCombination(index);
        (
            string memory compoKey,
            string memory strap,
            string memory dial,
            string memory item,
            string memory hologram
        ) = stringUtils.processString(dna);
        idCombinations[(_nextTokenId - 6)] = dna;
        idCombinations[(_nextTokenId - 5)] = gift;
        idCombinations[(_nextTokenId - 4)] = strap;
        idCombinations[(_nextTokenId - 3)] = dial;
        idCombinations[(_nextTokenId - 2)] = item;
        idCombinations[(_nextTokenId - 1)] = hologram;
        combinationsId[dna] = _nextTokenId - 6;
        combinationsId[gift] = _nextTokenId - 5;
        combinationsId[strap] = _nextTokenId - 4;
        combinationsId[dial] = _nextTokenId - 3;
        combinationsId[item] = _nextTokenId - 2;
        combinationsId[hologram] = _nextTokenId - 1;
        combinations[compoKey] = Combination({
            owned: true,
            minted: true,
            reserved: false,
            dna: dna,
            id: int256(_nextTokenId) - 6
        });
    }

    function assignReferralID(address user) private {
        if (bytes(walletReferralIds[user]).length == 0) {
            string memory newReferralId = increaseReferral();
            referralPoints[newReferralId] = referralPoint({
                walletAddress: user,
                currentReferralPoints: 0,
                overAllReferralPoints: 0
            });
            walletReferralIds[user] = newReferralId;
        }
    }

    function increaseReferral() private returns (string memory) {
        _referral += 1;
        return stringUtils.formatWithXIO(_referral);
    }

    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    // ---- Combination/Assembly ----
    function getCombination(
        string memory key
    ) public view returns (bool, bool, bool, string memory) {
        Combination memory combination = combinations[key];
        return (
            combination.owned,
            combination.minted,
            combination.reserved,
            combination.dna
        );
    }

    function assembleServer(
        uint256 tokenStrapId,
        uint256 tokenDialId,
        uint256 tokenItemId,
        uint256 tokenHologramId,
        address assembler
    ) public onlyOwner {
        require(
            isApprovedForAll(assembler, address(owner())) || // Check if caller is an operator
                (getApproved(tokenStrapId) == address(owner()) &&
                    getApproved(tokenDialId) == address(owner()) &&
                    getApproved(tokenItemId) == address(owner()) &&
                    getApproved(tokenHologramId) == address(owner())), // OR if NFT is approved to this contract
            "Not approved"
        );

        require(tokenStrapId < _nextTokenId, "Invalid token");
        require(tokenDialId < _nextTokenId, "Invalid token");
        require(tokenItemId < _nextTokenId, "Invalid token");
        require(tokenHologramId < _nextTokenId, "Invalid token");

        require(ownerOf(tokenStrapId) == assembler, "Not owned");
        require(ownerOf(tokenDialId) == assembler, "not owned");
        require(ownerOf(tokenItemId) == assembler, "not owned");
        require(ownerOf(tokenHologramId) == assembler, "not owned");

        string memory strap = idCombinations[tokenStrapId];
        string memory dial = idCombinations[tokenDialId];
        string memory item = idCombinations[tokenItemId];
        string memory hologram = idCombinations[tokenHologramId];

        require(stringUtils.isStrapValid(strap), "Invalid Strap");
        require(stringUtils.isDialValid(dial), "Invalid Dial");
        require(stringUtils.isItemValid(item), "Invalid Item");
        require(stringUtils.isHologramValid(hologram), "Invalid Hologram");

        string memory compoKey = stringUtils.concatenateTrails(
            strap,
            dial,
            item,
            hologram
        );
        require(!combinations[compoKey].reserved, "reserved");
        require(!combinations[compoKey].owned, "owned");

        // Transfer the components to the contract owner
        transferFrom(assembler, address(owner()), tokenStrapId);
        transferFrom(assembler, address(owner()), tokenDialId);
        transferFrom(assembler, address(owner()), tokenItemId);
        transferFrom(assembler, address(owner()), tokenHologramId);

        if (combinations[compoKey].minted == true) {
            string memory old_dna = combinations[compoKey].dna;
            string memory new_dna = stringUtils.generateFullDNA(
                strap,
                dial,
                item,
                hologram
            );
            uint256 comboTokenID = combinationsId[old_dna];
            transferFrom(address(owner()), assembler, comboTokenID);
            combinations[compoKey] = Combination({
                owned: true,
                minted: true,
                reserved: false,
                dna: new_dna,
                id: int256(comboTokenID)
            });
            delete combinationsId[old_dna];
            combinationsId[new_dna] = comboTokenID;
            idCombinations[comboTokenID] = new_dna;
        } else {
            string memory dna = stringUtils.generateFullDNA(
                strap,
                dial,
                item,
                hologram
            );
            uint256 tokenDna = _nextTokenId++;
            _safeMint(assembler, tokenDna);
            idCombinations[tokenDna] = dna;
            combinationsId[dna] = tokenDna;
            combinations[compoKey] = Combination({
                owned: true,
                minted: true,
                reserved: false,
                dna: dna,
                id: int256(tokenDna)
            });
        }
    }

    function assemble(
        uint256 tokenStrapId,
        uint256 tokenDialId,
        uint256 tokenItemId,
        uint256 tokenHologramId
    ) public nonReentrant notInPanic {
        require(
            isApprovedForAll(owner(), address(this)),
            "Contract not approved to transfer owner's token"
        );

        require(tokenStrapId < _nextTokenId, "Invalid token");
        require(tokenDialId < _nextTokenId, "Invalid token");
        require(tokenItemId < _nextTokenId, "Invalid token");
        require(tokenHologramId < _nextTokenId, "Invalid token");

        require(ownerOf(tokenStrapId) == msg.sender, "Not owned");
        require(ownerOf(tokenDialId) == msg.sender, "not owned");
        require(ownerOf(tokenItemId) == msg.sender, "not owned");
        require(ownerOf(tokenHologramId) == msg.sender, "not owned");

        string memory strap = idCombinations[tokenStrapId];
        string memory dial = idCombinations[tokenDialId];
        string memory item = idCombinations[tokenItemId];
        string memory hologram = idCombinations[tokenHologramId];

        require(stringUtils.isStrapValid(strap), "Invalid Strap");
        require(stringUtils.isDialValid(dial), "Invalid Dial");
        require(stringUtils.isItemValid(item), "Invalid Item");
        require(stringUtils.isHologramValid(hologram), "Invalid Hologram");

        string memory compoKey = stringUtils.concatenateTrails(
            strap,
            dial,
            item,
            hologram
        );
        require(!combinations[compoKey].reserved, "reserved");
        require(!combinations[compoKey].owned, "owned");

        // Transfer the components to the contract owner
        transferFrom(msg.sender, address(owner()), tokenStrapId);
        transferFrom(msg.sender, address(owner()), tokenDialId);
        transferFrom(msg.sender, address(owner()), tokenItemId);
        transferFrom(msg.sender, address(owner()), tokenHologramId);

        if (combinations[compoKey].minted == true) {
            string memory old_dna = combinations[compoKey].dna;
            string memory new_dna = stringUtils.generateFullDNA(
                strap,
                dial,
                item,
                hologram
            );
            uint256 comboTokenID = combinationsId[old_dna];
            IERC721(address(this)).safeTransferFrom(
                owner(),
                msg.sender,
                comboTokenID
            );
            combinations[compoKey] = Combination({
                owned: true,
                minted: true,
                reserved: false,
                dna: new_dna,
                id: int256(comboTokenID)
            });
            delete combinationsId[old_dna];
            combinationsId[new_dna] = comboTokenID;
            idCombinations[comboTokenID] = new_dna;
        } else {
            string memory dna = stringUtils.generateFullDNA(
                strap,
                dial,
                item,
                hologram
            );
            uint256 tokenDna = _nextTokenId++;
            _safeMint(msg.sender, tokenDna);
            idCombinations[tokenDna] = dna;
            combinationsId[dna] = tokenDna;
            combinations[compoKey] = Combination({
                owned: true,
                minted: true,
                reserved: false,
                dna: dna,
                id: int256(tokenDna)
            });
        }
    }

    // ---- Dismantle ----
    function dismantleServer(
        address dismantler,
        uint256 tokenId
    ) public onlyOwner {
        require(
            isApprovedForAll(ownerOf(tokenId), address(owner())),
            "Not approved"
        );

        require(tokenId < _nextTokenId, "Invalid token");
        require(ownerOf(tokenId) == dismantler, "not the owner");
        string memory dnaResult = idCombinations[tokenId];
        bool isADnaValid = stringUtils.isDnaValid(dnaResult);
        require(isADnaValid, "This is a not a valid DNA");
        (
            string memory compoKey,
            string memory strap,
            string memory dial,
            string memory item,
            string memory hologram
        ) = stringUtils.processString(dnaResult);
        require(combinations[compoKey].owned == true, "Combination not owned");
        uint256 strapID = combinationsId[strap];
        uint256 dialID = combinationsId[dial];
        uint256 itemID = combinationsId[item];
        uint256 hologramID = combinationsId[hologram];
        require(ownerOf(strapID) == address(msg.sender), "not owned");
        require(ownerOf(dialID) == address(msg.sender), "not owned");
        require(ownerOf(itemID) == address(msg.sender), "not owned");
        require(ownerOf(hologramID) == address(msg.sender), "not owned");
        transferFrom(dismantler, address(owner()), tokenId);
        transferFrom(msg.sender, dismantler, strapID);
        transferFrom(msg.sender, dismantler, dialID);
        transferFrom(msg.sender, dismantler, itemID);
        transferFrom(msg.sender, dismantler, hologramID);
        combinations[compoKey] = Combination({
            owned: false,
            minted: true,
            reserved: false,
            dna: dnaResult,
            id: int256(tokenId)
        });
    }

    function dismantle(uint256 tokenId) public nonReentrant notInPanic {
        require(
            isApprovedForAll(owner(), address(this)),
            "Contract not approved to transfer owner's token"
        );
        require(tokenId < _nextTokenId, "Invalid token");
        require(ownerOf(tokenId) == msg.sender, "not the owner");
        string memory dnaResult = idCombinations[tokenId];
        bool isADnaValid = stringUtils.isDnaValid(dnaResult);
        require(isADnaValid, "This is a not a valid DNA");
        (
            string memory compoKey,
            string memory strap,
            string memory dial,
            string memory item,
            string memory hologram
        ) = stringUtils.processString(dnaResult);
        require(combinations[compoKey].owned == true, "Combination not owned");
        uint256 strapID = combinationsId[strap];
        uint256 dialID = combinationsId[dial];
        uint256 itemID = combinationsId[item];
        uint256 hologramID = combinationsId[hologram];
        require(ownerOf(strapID) == address(owner()), "not owned");
        require(ownerOf(dialID) == address(owner()), "not owned");
        require(ownerOf(itemID) == address(owner()), "not owned");
        require(ownerOf(hologramID) == address(owner()), "not owned");

        transferFrom(msg.sender, address(owner()), tokenId);
        IERC721(address(this)).safeTransferFrom(owner(), msg.sender, strapID);
        IERC721(address(this)).safeTransferFrom(owner(), msg.sender, dialID);
        IERC721(address(this)).safeTransferFrom(owner(), msg.sender, itemID);
        IERC721(address(this)).safeTransferFrom(
            owner(),
            msg.sender,
            hologramID
        );
        combinations[compoKey] = Combination({
            owned: false,
            minted: true,
            reserved: false,
            dna: dnaResult,
            id: int256(tokenId)
        });
    }

    // ---- Upgrade ----
    function upgradeTrait(uint256 traitTokenId) public nonReentrant notInPanic {
        string memory oldTraitCode = idCombinations[traitTokenId];
        (Level nextLevel, string memory newTraitCode) = getNextUpgradeableTrait(
            oldTraitCode
        );
        require(traitTokenId < _nextTokenId, "Invalid token");
        require(ownerOf(traitTokenId) == msg.sender, "not the owner");
        address garbageCollector = address(0);
        uint256 upgradeFee = 0;
        if (nextLevel == Level.L1) {
            upgradeFee = upgradeFeeL0L1;
            garbageCollector = resaleWallet;
        } else if (nextLevel == Level.L2) {
            upgradeFee = upgradeFeeL1L2;
            garbageCollector = junkyardWallet;
        } else if (nextLevel == Level.L3) {
            upgradeFee = upgradeFeeL2L3;
            garbageCollector = junkyardWallet;
        }
        require(
            xioToken.balanceOf(msg.sender) >= upgradeFee,
            "Insufficient balance"
        );
        require(
            xioToken.allowance(msg.sender, address(this)) >= upgradeFee,
            "Not allowed to spend"
        );
        require(
            (stringUtils.isStrapValid(oldTraitCode) ==
                stringUtils.isStrapValid(newTraitCode)) &&
                (stringUtils.isDialValid(oldTraitCode) ==
                    stringUtils.isDialValid(newTraitCode)) &&
                (stringUtils.isItemValid(oldTraitCode) ==
                    stringUtils.isItemValid(newTraitCode)) &&
                (stringUtils.isHologramValid(oldTraitCode) ==
                    stringUtils.isHologramValid(newTraitCode)),
            "Trait type mismatch"
        );
        xioToken.transferFrom(msg.sender, address(owner()), upgradeFee);
        transferFrom(msg.sender, address(owner()), traitTokenId);
        uint256 newTraitToken = _nextTokenId++;
        _safeMint(msg.sender, newTraitToken);
        idCombinations[newTraitToken] = newTraitCode;
        combinationsId[newTraitCode] = newTraitToken;
        incrementMinted(oldTraitCode);
        IERC721(address(this)).safeTransferFrom(
            address(owner()),
            garbageCollector,
            traitTokenId
        );
    }

    function upgradeTraitServer(
        uint256 traitTokenId,
        address upgrader
    ) public onlyOwner {
        require(isApprovedForAll(upgrader, address(owner())), "Not approved");
        string memory oldTraitCode = idCombinations[traitTokenId];
        address garbageCollector = address(0);
        (Level nextLevel, string memory newTraitCode) = getNextUpgradeableTrait(
            oldTraitCode
        );
        if (nextLevel == Level.L1) {
            garbageCollector = resaleWallet;
        } else {
            garbageCollector = junkyardWallet;
        }
        require(traitTokenId < _nextTokenId, "Invalid token");
        require(ownerOf(traitTokenId) == upgrader, "not the owner");
        require(
            (stringUtils.isStrapValid(oldTraitCode) ==
                stringUtils.isStrapValid(newTraitCode)) &&
                (stringUtils.isDialValid(oldTraitCode) ==
                    stringUtils.isDialValid(newTraitCode)) &&
                (stringUtils.isItemValid(oldTraitCode) ==
                    stringUtils.isItemValid(newTraitCode)) &&
                (stringUtils.isHologramValid(oldTraitCode) ==
                    stringUtils.isHologramValid(newTraitCode)),
            "Trait type mismatch"
        );
        transferFrom(upgrader, address(owner()), traitTokenId);
        uint256 newTraitToken = _nextTokenId++;
        _safeMint(upgrader, newTraitToken);
        idCombinations[newTraitToken] = newTraitCode;
        combinationsId[newTraitCode] = newTraitToken;
        incrementMinted(oldTraitCode);
        transferFrom(address(owner()), garbageCollector, traitTokenId);
    }

    function upgradeWatch(
        uint256 watchTokenId,
        uint256 traitIndex
    ) public nonReentrant notInPanic {
        require(
            isApprovedForAll(owner(), address(this)),
            "Contract not approved"
        );
        require(watchTokenId < _nextTokenId, "Invalid token");
        require(ownerOf(watchTokenId) == msg.sender, "Not the owner");

        string memory oldCombinationCode = idCombinations[watchTokenId];

        TraitParts memory parts;
        (parts.strap, parts.dial, parts.item, parts.hologram) = stringUtils
            .splitString(oldCombinationCode);

        string memory oldTraitCode = _getTraitByIndex(
            traitIndex,
            parts.strap,
            parts.dial,
            parts.item,
            parts.hologram
        );

        string memory oldComboKey = stringUtils.concatenateTrails(
            parts.strap,
            parts.dial,
            parts.item,
            parts.hologram
        );

        (Level nextLevel, string memory newTraitCode) = getNextUpgradeableTrait(
            oldTraitCode
        );
        (string memory newComboKey, string memory newDna) = _getNewCombination(
            traitIndex,
            parts.strap,
            parts.dial,
            parts.item,
            parts.hologram,
            newTraitCode
        );

        require(!combinations[newComboKey].reserved, "Combination reserved");
        require(!combinations[newComboKey].owned, "Combination owned");
        require(
            _isTraitTypeMatching(traitIndex, newTraitCode),
            "Trait type mismatch"
        );

        address garbageCollector = (nextLevel == Level.L1)
            ? resaleWallet
            : junkyardWallet;
        uint256 upgradeFee = _getUpgradeFee(nextLevel);

        require(
            xioToken.balanceOf(msg.sender) >= upgradeFee,
            "Insufficient balance"
        );
        require(
            xioToken.allowance(msg.sender, address(this)) >= upgradeFee,
            "Not allowed to spend"
        );

        transferFrom(msg.sender, address(owner()), watchTokenId);

        if (combinations[newComboKey].minted) {
            _upgradeWithExistingCombo(
                msg.sender,
                watchTokenId,
                oldCombinationCode,
                oldComboKey,
                oldTraitCode,
                newTraitCode,
                newDna,
                newComboKey,
                garbageCollector,
                upgradeFee
            );
        } else {
            _upgradeWithNewCombo(
                msg.sender,
                watchTokenId,
                oldCombinationCode,
                oldTraitCode,
                oldComboKey,
                newTraitCode,
                newDna,
                newComboKey,
                garbageCollector,
                upgradeFee
            );
        }
    }

    function upgradeWatchServer(
        uint256 watchTokenId,
        uint256 traitIndex,
        address upgrader
    ) public onlyOwner {
        require(isApprovedForAll(upgrader, address(owner())), "Not approved");
        require(watchTokenId < _nextTokenId, "Invalid token");
        require(ownerOf(watchTokenId) == upgrader, "Not the owner");

        string memory oldCombinationCode = idCombinations[watchTokenId];

        TraitParts memory parts;
        (parts.strap, parts.dial, parts.item, parts.hologram) = stringUtils
            .splitString(oldCombinationCode);

        string memory oldTraitCode = _getTraitByIndex(
            traitIndex,
            parts.strap,
            parts.dial,
            parts.item,
            parts.hologram
        );

        string memory oldComboKey = stringUtils.concatenateTrails(
            parts.strap,
            parts.dial,
            parts.item,
            parts.hologram
        );

        (Level nextLevel, string memory newTraitCode) = getNextUpgradeableTrait(
            oldTraitCode
        );

        (string memory newComboKey, string memory newDna) = _getNewCombination(
            traitIndex,
            parts.strap,
            parts.dial,
            parts.item,
            parts.hologram,
            newTraitCode
        );

        require(
            _isTraitTypeMatching(traitIndex, newTraitCode),
            "Trait type mismatch"
        );

        require(!combinations[newComboKey].reserved, "Combination reserved");
        require(!combinations[newComboKey].owned, "Combination owned");

        address garbageCollector = (nextLevel == Level.L1)
            ? resaleWallet
            : junkyardWallet;
        transferFrom(upgrader, address(owner()), watchTokenId); //

        uint256 oldTraitTokenId = combinationsId[oldTraitCode];
        // int256 watchTokenIdInt = int256(watchTokenId);

        if (combinations[newComboKey].minted) {
            _handleUpgradeMintedCombo(
                upgrader,
                oldComboKey,
                oldTraitCode,
                newTraitCode,
                newDna,
                newComboKey,
                garbageCollector,
                oldTraitTokenId
            );
        } else {
            _handleUpgradeNewCombo(
                upgrader,
                oldComboKey,
                oldTraitCode,
                newTraitCode,
                newDna,
                newComboKey,
                garbageCollector
            );
        }
    }

    function _getTraitByIndex(
        uint256 index,
        string memory strap,
        string memory dial,
        string memory item,
        string memory hologram
    ) internal pure returns (string memory) {
        if (index == 1) return strap;
        if (index == 2) return dial;
        if (index == 3) return item;
        if (index == 4) return hologram;
        revert("Invalid trait index");
    }

    function _getNewCombination(
        uint256 index,
        string memory strap,
        string memory dial,
        string memory item,
        string memory hologram,
        string memory newTrait
    ) internal pure returns (string memory newCombo, string memory newDna) {
        if (index == 1) {
            newCombo = stringUtils.concatenateTrails(
                newTrait,
                dial,
                item,
                hologram
            );
            newDna = stringUtils.generateFullDNA(
                newTrait,
                dial,
                item,
                hologram
            );
        } else if (index == 2) {
            newCombo = stringUtils.concatenateTrails(
                strap,
                newTrait,
                item,
                hologram
            );
            newDna = stringUtils.generateFullDNA(
                strap,
                newTrait,
                item,
                hologram
            );
        } else if (index == 3) {
            newCombo = stringUtils.concatenateTrails(
                strap,
                dial,
                newTrait,
                hologram
            );
            newDna = stringUtils.generateFullDNA(
                strap,
                dial,
                newTrait,
                hologram
            );
        } else if (index == 4) {
            newCombo = stringUtils.concatenateTrails(
                strap,
                dial,
                item,
                newTrait
            );
            newDna = stringUtils.generateFullDNA(strap, dial, item, newTrait);
        } else {
            revert("Invalid trait index");
        }
    }

    function _isTraitTypeMatching(
        uint256 index,
        string memory trait
    ) internal pure returns (bool) {
        if (index == 1) return stringUtils.isStrapValid(trait);
        if (index == 2) return stringUtils.isDialValid(trait);
        if (index == 3) return stringUtils.isItemValid(trait);
        if (index == 4) return stringUtils.isHologramValid(trait);
        return false;
    }

    function _getUpgradeFee(Level level) internal view returns (uint256) {
        if (level == Level.L1) return upgradeFeeL0L1;
        if (level == Level.L2) return upgradeFeeL1L2;
        if (level == Level.L3) return upgradeFeeL2L3;
        revert("Invalid level");
    }

    function _upgradeWithExistingCombo(
        address user, // Upgrader address
        uint256 oldTokenId, // Watch token ID
        string memory oldCombinationCode, // Watch With Numbers
        string memory oldComboKey, // Watch without numbers
        string memory oldTrait, // Old trait code aabaaaa12
        string memory newTrait, // New trait code aabaaff13
        string memory newDna, // New DNA code with numbers including new trait
        string memory newComboKey, // New DNA code (without) numbers including new trait
        address garbageCollector, // Address to send old trait to
        uint256 fee // Upgrade fee
    ) internal {
        uint256 newTraitId = _nextTokenId++;
        _safeMint(address(owner()), newTraitId);
        idCombinations[newTraitId] = newTrait;
        combinationsId[newTrait] = newTraitId;
        string memory oldDna = combinations[newComboKey].dna;
        uint256 comboTokenId = combinationsId[oldDna];
        delete combinationsId[oldDna];
        combinationsId[newDna] = comboTokenId;
        idCombinations[comboTokenId] = newDna;

        IERC721(address(this)).safeTransferFrom(owner(), user, comboTokenId);
        xioToken.transferFrom(user, address(owner()), fee);
        incrementMinted(oldTrait);

        combinations[oldComboKey] = Combination(
            false,
            true,
            false,
            oldCombinationCode,
            int256(oldTokenId)
        );
        combinations[newComboKey] = Combination(
            true,
            true,
            false,
            newDna,
            int256(comboTokenId)
        );

        IERC721(address(this)).safeTransferFrom(
            owner(),
            garbageCollector,
            combinationsId[oldTrait]
        );
    }

    function _upgradeWithNewCombo(
        address user,
        uint256 watchTokenId,
        string memory oldCombinationCode,
        string memory oldTrait,
        string memory oldComboKey,
        string memory newTrait,
        string memory newDna,
        string memory newComboKey,
        address garbageCollector,
        uint256 fee
    ) internal {
        uint256 newTraitId = _nextTokenId++;
        uint256 newDnaId = _nextTokenId++;
        _safeMint(address(owner()), newTraitId);
        _safeMint(user, newDnaId);
        idCombinations[newTraitId] = newTrait;
        combinationsId[newTrait] = newTraitId;
        idCombinations[newDnaId] = newDna;
        combinationsId[newDna] = newDnaId;
        xioToken.transferFrom(user, address(owner()), fee);
        incrementMinted(oldTrait);

        combinations[oldComboKey] = Combination(
            false,
            true,
            false,
            oldCombinationCode,
            int256(watchTokenId)
        );
        combinations[newComboKey] = Combination(
            true,
            true,
            false,
            newDna,
            int256(newDnaId)
        );
        IERC721(address(this)).safeTransferFrom(
            owner(),
            garbageCollector,
            combinationsId[oldTrait]
        );
    }

    function _handleUpgradeMintedCombo(
        address upgrader,
        string memory oldComboKey,
        string memory oldTraitCode,
        string memory newTraitCode,
        string memory newDna,
        string memory newComboKey,
        address garbageCollector,
        uint256 oldTraitTokenId
    ) internal {
        uint256 traitTokenID = _nextTokenId++;
        _safeMint(address(owner()), traitTokenID);
        idCombinations[traitTokenID] = newTraitCode;
        combinationsId[newTraitCode] = traitTokenID;
        string memory oldDna = combinations[newComboKey].dna;
        uint256 comboTokenID = combinationsId[oldDna];
        delete combinationsId[oldDna];
        combinationsId[newDna] = comboTokenID;
        idCombinations[comboTokenID] = newDna;
        transferFrom(address(owner()), upgrader, comboTokenID);
        incrementMinted(oldTraitCode);
        Combination storage oldCombo = combinations[oldComboKey];
        oldCombo.owned = false;
        _setCombination(
            newComboKey,
            true,
            true,
            false,
            newDna,
            int256(comboTokenID)
        );
        transferFrom(address(owner()), garbageCollector, oldTraitTokenId);
    }

    function _handleUpgradeNewCombo(
        address upgrader,
        string memory oldComboKey,
        string memory oldTrait,
        string memory newTrait,
        string memory newDna,
        string memory newComboKey,
        address garbageCollector
    ) internal {
        uint256 newTraitId = _nextTokenId++;
        uint256 newDnaId = _nextTokenId++;

        _safeMint(address(owner()), newTraitId);
        _safeMint(upgrader, newDnaId);

        idCombinations[newTraitId] = newTrait;
        combinationsId[newTrait] = newTraitId;

        idCombinations[newDnaId] = newDna;
        combinationsId[newDna] = newDnaId;
        incrementMinted(oldTrait);

        Combination storage oldCombo = combinations[oldComboKey];
        oldCombo.owned = false;

        _setCombination(
            newComboKey,
            true,
            true,
            false,
            newDna,
            int256(newDnaId)
        );
        IERC721(address(this)).safeTransferFrom(
            owner(),
            garbageCollector,
            combinationsId[oldTrait]
        );
    }

    function _setCombination(
        string memory key,
        bool owned,
        bool minted,
        bool reserved,
        string memory dna,
        int256 id
    ) internal {
        combinations[key] = Combination({
            owned: owned,
            minted: minted,
            reserved: reserved,
            dna: dna,
            id: id
        });
    }

    // ---- Withdrawals ----
    function withDrawUSDC(
        address receiver,
        uint256 amount
    ) public onlyOwner nonReentrant {
        require(amount >= 10e6, "Min 10 USDC");
        require(
            usdcToken.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        bool success = usdcToken.transfer(receiver, amount);
        require(success, "Transfer failed");
    }

    function emergencyWithdrawUSDC(
        address to,
        uint256 amount,
        string memory reason
    ) public onlyOwner nonReentrant {
        require(to != address(0), "Invalid address");
        require(
            usdcToken.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        bool success = usdcToken.transfer(to, amount);
        require(success, "Transfer failed");

        emit EmergencyWithdrawal(to, amount, reason);
    }

    // ---- Pause/Panic ----
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function triggerPanicMode() public onlyOwner {
        panicMode = true;
        _pause();
    }

    function resumeNormalMode() public onlyOwner {
        panicMode = false;
        _unpause();
    }

    // ---- ERC721 Overrides ----
    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        // Override _baseURI to return the custom base URI
        return _baseTokenURI;
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            ERC721,
            ERC721Enumerable,
            ERC721URIStorage,
            AccessControl,
            ERC2981
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    // ---- Utility ----
    function getPrivateCombination(
        uint256 index
    ) private view returns (string memory, string memory) {
        require(index < 50000, "Index out of bounds");
        PrivateCombination memory privatecombination = privateCombinations[
            index
        ];
        return (privatecombination.dna, privatecombination.gift);
    }
}
