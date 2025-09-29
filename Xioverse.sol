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

    bytes32 public constant ComboManager_Role =
        keccak256("ComboManager_Role");
    
    bytes32 public constant CustodyWallet_Role =
        keccak256("CustodyWallet_ROLE");
    
    address public custodyWallet;
    
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
    uint256 public _mintedReserved;
    uint256 public mintingFee;
    string private _baseTokenURI;
    string private _uriExtension;
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
    event CustodyWalletChanged(address indexed oldWallet, address indexed newWallet);
    event UpgradeCharged(address indexed payer, uint256 indexed fee, uint8 level);
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
        mintingFee = 0;
        _baseTokenURI = "http://assets.xioverse.com/";
        _uriExtension = ".json";
        _maxReservedCombination = 50000;
        isOG = true;
        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _grantRole(ComboManager_Role, initialOwner);
        _setCustodyWallet(initialOwner);
        royaltyBasisPoints = 1000; // 10%
        _setDefaultRoyalty(initialOwner, royaltyBasisPoints);
    }

    // =========================
    // FUNCTIONS
    // =========================

    // ---- Settings and Admin ----
    function setCustodyWallet(address newWallet)
    external
    onlyOwner   // or onlyOwner if you prefer
{
    _setCustodyWallet(newWallet);
}

function _setCustodyWallet(address newWallet) internal {
    require(newWallet != address(0), "custody wallet = zero");
    address old = custodyWallet;

    // If an old wallet exists, revoke role from it
    if (old != address(0) && hasRole(CustodyWallet_Role, old)) {
        super._revokeRole(CustodyWallet_Role, old); // call super to skip our override guard
    }

    custodyWallet = newWallet;

    // Grant role to the new wallet
    if (!hasRole(CustodyWallet_Role, newWallet)) {
        super._grantRole(CustodyWallet_Role, newWallet); // call super to skip our override guard
    }

    emit CustodyWalletChanged(old, newWallet);
}

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

    function setUriExtension(string memory newExtension) public onlyOwner {
    _uriExtension = newExtension;
    }

    function setMintingFee(uint256 newFee) public onlyOwner {
        mintingFee = newFee;
    }

    function changeMintingPhase(uint256 status) public onlyOwner {
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
    ) public onlyRole(ComboManager_Role) {
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
    ) public onlyRole(ComboManager_Role) {
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
    ) public onlyRole(ComboManager_Role) {
        traitsConfiguration[trait] = TraitConfig(level, baseGroup);
    }
    
    function setTraitConfig(
        string[] memory baseGroups,
        uint256[] memory levels,
        string[] memory traits
    ) public onlyRole(ComboManager_Role) {
        uint256 len = traits.length;
        require(
            baseGroups.length == len && levels.length == len,
            "Length mismatch"
        );
        for (uint256 i = 0; i < len; i++) {
            traitsConfiguration[traits[i]] = TraitConfig(levels[i], baseGroups[i]);
        }
    }

    function addTrait(
        string memory groupCode,
        Level level,
        string memory trait
    ) public onlyRole(ComboManager_Role) {
        TraitGroup storage group = traitGroups[groupCode][level];
        group.entries[group.index] = trait;
        group.index++;
    }
    function setTraitAtIndex(
        string memory groupCode,
        Level level,
        uint256 i,
        string memory trait
    ) external onlyRole(ComboManager_Role) {
        require(i < traitGroups[groupCode][level].index, "Index OOB");
        traitGroups[groupCode][level].entries[i] = trait;
    }

    function addTrait(
            string[] memory groupCodes,
            string[] memory traits,
            uint256[] memory levels
        ) public onlyRole(ComboManager_Role) {
            uint256 len = traits.length;
            require(len > 0, "No traits");
            require(groupCodes.length == len && levels.length == len, "Length mismatch");
            for (uint256 i = 0; i < len; i++) {
                uint256 rawLevel = levels[i];
                require(rawLevel < 4, "Invalid level");
                TraitGroup storage group = traitGroups[groupCodes[i]][Level(rawLevel)];
                group.entries[group.index] = traits[i];
                group.index++;
            }
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
        string memory normalized = stringUtils.normalizeTrait(fullTraitCode);

        TraitConfig memory config = traitsConfiguration[normalized];
        require(config.level < 3, "Max upgrade level reached");

        string memory groupCode = config.base;
        nextLevel = Level(config.level + 1);
        TraitGroup storage nextGroup = traitGroups[groupCode][nextLevel];

        

        require(
            nextGroup.indexMinted < nextGroup.index,
            "No traits left to mint"
        );

        nextTrait = nextGroup.entries[nextGroup.indexMinted];
    }

    function incrementMinted(string memory fullTraitCode) private {
        string memory normalized = stringUtils.normalizeTrait(fullTraitCode);

        TraitConfig memory config = traitsConfiguration[normalized];
        require(config.level < 3, "Max upgrade level reached");

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
    function _mintcore(
        address to,
        uint256 amount,
        string memory refID
    ) internal {
        require(amount > 0, "Amount must be > 0"); 
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
            amount + _mintedReserved <= _maxReservedCombination,
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
            _mintedReserved += 1;
            _safeMint(to, tokenGift);
            _safeMint(custodyWallet, tokenStrap);
            _safeMint(custodyWallet, tokenDial);
            _safeMint(custodyWallet, tokenItem);
            _safeMint(custodyWallet, tokenHologram);
            uint256 index = _currentReservedCombination++;
            (string memory dna, string memory gift) = getPrivateCombination(
                index
            );
            (
                string memory ComboKey,
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
            combinations[ComboKey] = Combination({
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

    function mint(address to, uint256 amount, string memory refID)
        public
        nonReentrant
        notInPanic
    {
        _mintcore(to, amount, refID);
    }

    function mintWithoutReferral(address to, uint256 amount)
        public
        nonReentrant
        notInPanic
    {
        _mintcore(to, amount, "xio10000");
    }

    function reward(string memory refID, uint256 points) internal {
        for (uint256 i = 0; i < points; i++) {
            referralPoints[refID].currentReferralPoints += 1;
            referralPoints[refID].overAllReferralPoints += 1;
            if (referralPoints[refID].currentReferralPoints >= 4) {
                if (1 + _mintedReserved <= _maxReservedCombination) {
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
        _mintedReserved += 1;
        _safeMint(to, tokenGift);
        _safeMint(custodyWallet, tokenStrap);
        _safeMint(custodyWallet, tokenDial);
        _safeMint(custodyWallet, tokenItem);
        _safeMint(custodyWallet, tokenHologram);
        uint256 index = _currentReservedCombination++;
        (string memory dna, string memory gift) = getPrivateCombination(index);
        (
            string memory ComboKey,
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
        combinations[ComboKey] = Combination({
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

    function Airdrop(address to, uint256 amount)
        public
        onlyOwner
        nonReentrant
        notInPanic
    {
        require(
            amount + _mintedReserved <= _maxReservedCombination,
            "You have exceeded the Max Reserved Combination"
        );

        for (uint256 i = 0; i < amount; i++) {
            internalMint(to);
        }
    }


    // ---- Combination/Assembly ----
    function _contractTransfer(address from, address to, uint256 tokenId) internal {
    IERC721(address(this)).safeTransferFrom(from, to, tokenId);
}

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
    ) public nonReentrant onlyRole(CustodyWallet_Role) {
        require(
            isApprovedForAll(assembler, address(this)) || // Check if caller is an operator
                (getApproved(tokenStrapId) == address(this) &&
                    getApproved(tokenDialId) == address(this) &&
                    getApproved(tokenItemId) == address(this) &&
                    getApproved(tokenHologramId) == address(this)), // OR if NFT is approved to this contract
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

        string memory ComboKey = stringUtils.concatenateTrails(
            strap,
            dial,
            item,
            hologram
        );
        require(!combinations[ComboKey].reserved, "reserved");
        require(!combinations[ComboKey].owned, "owned");

        // Transfer the components to the custody wallet
        _contractTransfer(assembler, custodyWallet, tokenStrapId);
        _contractTransfer(assembler, custodyWallet, tokenDialId);
        _contractTransfer(assembler, custodyWallet, tokenItemId);
        _contractTransfer(assembler, custodyWallet, tokenHologramId);

        if (combinations[ComboKey].minted == true) {
            string memory old_dna = combinations[ComboKey].dna;
            string memory new_dna = stringUtils.generateFullDNA(
                strap,
                dial,
                item,
                hologram
            );
            uint256 comboTokenID = combinationsId[old_dna];
            transferFrom(custodyWallet, assembler, comboTokenID);
            combinations[ComboKey] = Combination({
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
            combinations[ComboKey] = Combination({
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
            isApprovedForAll(custodyWallet, address(this)),
            "Contract not approved to transfer project's token"
        );

        require(tokenStrapId < _nextTokenId, "Invalid Strap token");
        require(tokenDialId < _nextTokenId, "Invalid Dial token");
        require(tokenItemId < _nextTokenId, "Invalid Item token");
        require(tokenHologramId < _nextTokenId, "Invalid Hologram token");

        require(ownerOf(tokenStrapId) == msg.sender, "Strap not owned by user");
        require(ownerOf(tokenDialId) == msg.sender, "Dial not owned by user");
        require(ownerOf(tokenItemId) == msg.sender, "Item not owned by user");
        require(ownerOf(tokenHologramId) == msg.sender, "Hologram not owned by user");

        string memory strap = idCombinations[tokenStrapId];
        string memory dial = idCombinations[tokenDialId];
        string memory item = idCombinations[tokenItemId];
        string memory hologram = idCombinations[tokenHologramId];

        require(stringUtils.isStrapValid(strap), "Invalid Strap");
        require(stringUtils.isDialValid(dial), "Invalid Dial");
        require(stringUtils.isItemValid(item), "Invalid Item");
        require(stringUtils.isHologramValid(hologram), "Invalid Hologram");

        string memory ComboKey = stringUtils.concatenateTrails(
            strap,
            dial,
            item,
            hologram
        );
        require(!combinations[ComboKey].reserved, "reserved");
        require(!combinations[ComboKey].owned, "owned");

        // Transfer the components to the contract owner
        transferFrom(msg.sender, custodyWallet, tokenStrapId);
        transferFrom(msg.sender, custodyWallet, tokenDialId);
        transferFrom(msg.sender, custodyWallet, tokenItemId);
        transferFrom(msg.sender, custodyWallet, tokenHologramId);

        if (combinations[ComboKey].minted == true) {
            string memory old_dna = combinations[ComboKey].dna;
            string memory new_dna = stringUtils.generateFullDNA(
                strap,
                dial,
                item,
                hologram
            );
            uint256 comboTokenID = combinationsId[old_dna];
            _contractTransfer(custodyWallet, msg.sender, comboTokenID);
            combinations[ComboKey] = Combination({
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
            combinations[ComboKey] = Combination({
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
    ) public nonReentrant onlyRole(CustodyWallet_Role) {
        require(
            isApprovedForAll(ownerOf(tokenId), address(this)),
            "Not approved"
        );

        require(tokenId < _nextTokenId, "Invalid token");
        require(ownerOf(tokenId) == dismantler, "User is not the watch owner");

        string memory dnaResult = idCombinations[tokenId];
        bool isADnaValid = stringUtils.isDnaValid(dnaResult);
        require(isADnaValid, "This is a not a valid DNA");
        (
            string memory ComboKey,
            string memory strap,
            string memory dial,
            string memory item,
            string memory hologram
        ) = stringUtils.processString(dnaResult);
        require(combinations[ComboKey].owned == true, "Combination not owned");
        uint256 strapID = combinationsId[strap];
        uint256 dialID = combinationsId[dial];
        uint256 itemID = combinationsId[item];
        uint256 hologramID = combinationsId[hologram];
        require(ownerOf(strapID) == custodyWallet, "Strap not in Project custody");
        require(ownerOf(dialID) == custodyWallet, "Dial not in Project custody");
        require(ownerOf(itemID) == custodyWallet, "Item not in Project custody");
        require(ownerOf(hologramID) == custodyWallet, "Hologram not in Project custody");
        _contractTransfer(dismantler, custodyWallet, tokenId);
        transferFrom(custodyWallet, dismantler, strapID);
        transferFrom(custodyWallet, dismantler, dialID);
        transferFrom(custodyWallet, dismantler, itemID);
        transferFrom(custodyWallet, dismantler, hologramID);
        combinations[ComboKey] = Combination({
            owned: false,
            minted: true,
            reserved: false,
            dna: dnaResult,
            id: int256(tokenId)
        });
    }

    function dismantle(uint256 tokenId) public nonReentrant notInPanic {
        require(
            isApprovedForAll(custodyWallet, address(this)),
            "Contract not approved to transfer project's token"
        );
        require(tokenId < _nextTokenId, "Invalid token");
        require(ownerOf(tokenId) == msg.sender, "not the owner");
        string memory dnaResult = idCombinations[tokenId];
        bool isADnaValid = stringUtils.isDnaValid(dnaResult);
        require(isADnaValid, "This is a not a valid DNA");
        (
            string memory ComboKey,
            string memory strap,
            string memory dial,
            string memory item,
            string memory hologram
        ) = stringUtils.processString(dnaResult);
        require(combinations[ComboKey].owned == true, "Combination not owned");
        uint256 strapID = combinationsId[strap];
        uint256 dialID = combinationsId[dial];
        uint256 itemID = combinationsId[item];
        uint256 hologramID = combinationsId[hologram];
        require(ownerOf(strapID) == custodyWallet, "Strap not in Project custody");
        require(ownerOf(dialID) == custodyWallet, "Dial not in Project custody");
        require(ownerOf(itemID) == custodyWallet, "Item not in Project custody");
        require(ownerOf(hologramID) == custodyWallet, "Hologram not in Project custody");

        transferFrom(msg.sender, custodyWallet, tokenId);
        _contractTransfer(custodyWallet, msg.sender, strapID);
        _contractTransfer(custodyWallet, msg.sender, dialID);
        _contractTransfer(custodyWallet, msg.sender, itemID);
        _contractTransfer(custodyWallet, msg.sender, hologramID);
        
        combinations[ComboKey] = Combination({
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
        transferFrom(msg.sender, custodyWallet, traitTokenId);
        uint256 newTraitToken = _nextTokenId++;
        _safeMint(msg.sender, newTraitToken);
        idCombinations[newTraitToken] = newTraitCode;
        combinationsId[newTraitCode] = newTraitToken;
        incrementMinted(oldTraitCode);
        _contractTransfer(custodyWallet, garbageCollector,traitTokenId)
        ;
    }

    function upgradeTraitServer(
        uint256 traitTokenId,
        address upgrader
    ) public nonReentrant onlyRole(CustodyWallet_Role) {
        require(isApprovedForAll(upgrader, address(this)), "User has not given approval");
        string memory oldTraitCode = idCombinations[traitTokenId];
        address garbageCollector = address(0);
        uint256 upgradeFee = 0;
        (Level nextLevel, string memory newTraitCode) = getNextUpgradeableTrait(
            oldTraitCode
        );

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
            xioToken.balanceOf(upgrader) >= upgradeFee,
            "Insufficient balance"
        );
        require(
            xioToken.allowance(upgrader, address(this)) >= upgradeFee,
            "Not allowed to spend"
        );
        require(traitTokenId < _nextTokenId, "Invalid token");
        require(ownerOf(traitTokenId) == upgrader, "User is not the owner of selected trait");
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
        xioToken.transferFrom(upgrader, address(owner()), upgradeFee);
        _contractTransfer(upgrader, custodyWallet, traitTokenId);
        uint256 newTraitToken = _nextTokenId++;
        _safeMint(upgrader, newTraitToken);
        idCombinations[newTraitToken] = newTraitCode;
        combinationsId[newTraitCode] = newTraitToken;
        incrementMinted(oldTraitCode);
        transferFrom(custodyWallet, garbageCollector, traitTokenId);
    }

    function upgradeWatch(
        uint256 watchTokenId,
        uint256 traitIndex
    ) public nonReentrant notInPanic {
        require(
            isApprovedForAll(custodyWallet, address(this)),
            "Contract not approved to transfer project's token"
        );
        require(watchTokenId < _nextTokenId, "Invalid token");
        require(ownerOf(watchTokenId) == msg.sender, "User does not own the watch");

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

        _chargeUpgrade(msg.sender, nextLevel);
        transferFrom(msg.sender, custodyWallet, watchTokenId);

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
                garbageCollector
               
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
                garbageCollector
               
            );
        }
    }

    function upgradeWatchServer(
        uint256 watchTokenId,
        uint256 traitIndex,
        address upgrader
    ) public nonReentrant onlyRole(CustodyWallet_Role) {
        require(isApprovedForAll(upgrader, address(this)), "Not approved");
        require(watchTokenId < _nextTokenId, "Invalid token");
        require(ownerOf(watchTokenId) == upgrader, "User is not the watch's owner");

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
        
        _chargeUpgrade(upgrader, nextLevel);
            
        _contractTransfer(upgrader, custodyWallet, watchTokenId); //

        uint256 oldTraitTokenId = combinationsId[oldTraitCode];
        

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
        string memory oldTrait, // Old trait code 
        string memory newTrait, // New trait code 
        string memory newDna, // New DNA code with numbers including new trait
        string memory newComboKey, // New DNA code (without) numbers including new trait
        address garbageCollector // Address to send old trait to

    ) internal {
        uint256 newTraitId = _nextTokenId++;
        _safeMint(custodyWallet, newTraitId);
        idCombinations[newTraitId] = newTrait;
        combinationsId[newTrait] = newTraitId;
        string memory oldDna = combinations[newComboKey].dna;
        uint256 comboTokenId = combinationsId[oldDna];
        delete combinationsId[oldDna];
        combinationsId[newDna] = comboTokenId;
        idCombinations[comboTokenId] = newDna;

        _contractTransfer(custodyWallet, user, comboTokenId);

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

        _contractTransfer(custodyWallet, garbageCollector, combinationsId[oldTrait]);
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
        address garbageCollector

    ) internal {
        uint256 newTraitId = _nextTokenId++;
        uint256 newDnaId = _nextTokenId++;
        _safeMint(custodyWallet, newTraitId);
        _safeMint(user, newDnaId);
        idCombinations[newTraitId] = newTrait;
        combinationsId[newTrait] = newTraitId;
        idCombinations[newDnaId] = newDna;
        combinationsId[newDna] = newDnaId;
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

        _contractTransfer(custodyWallet, garbageCollector, combinationsId[oldTrait]);
        
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
        _safeMint(custodyWallet, traitTokenID);
        idCombinations[traitTokenID] = newTraitCode;
        combinationsId[newTraitCode] = traitTokenID;
        string memory oldDna = combinations[newComboKey].dna;
        uint256 comboTokenID = combinationsId[oldDna];
        delete combinationsId[oldDna];
        combinationsId[newDna] = comboTokenID;
        idCombinations[comboTokenID] = newDna;
        transferFrom(custodyWallet, upgrader, comboTokenID);
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
        transferFrom(custodyWallet, garbageCollector, oldTraitTokenId);
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

        _safeMint(custodyWallet, newTraitId);
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
        _contractTransfer(custodyWallet, garbageCollector, combinationsId[oldTrait]);
        
    }

    function _chargeUpgrade(address payer, Level lvl) internal {
        uint256 upgradeFee = _getUpgradeFee(lvl);
        require(
            xioToken.balanceOf(payer) >= upgradeFee,
            "Insufficient balance"
        );
        require(
            xioToken.allowance(payer, address(this)) >= upgradeFee,
            "Not allowed to spend"
        );
        xioToken.transferFrom(payer, address(owner()), upgradeFee);
        emit UpgradeCharged(payer, upgradeFee, uint8(lvl));

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

    function enablePanicMode() public onlyOwner {
        panicMode = true;
        _pause();
    }

    function disablePanicMode() public onlyOwner {
        panicMode = false;
        _unpause();
    }

    // ---- ERC721 Overrides ----
function tokenURI(uint256 tokenId)
    public
    view
    override(ERC721, ERC721URIStorage)
    returns (string memory)
{
    _requireOwned(tokenId);

    string memory dna = idCombinations[tokenId];
    require(bytes(dna).length > 0, "No DNA assigned to this token");

    // Decide: watch DNA or trait DNA
    string memory slug = stringUtils.isDnaValid(dna)
        ? stringUtils.extractNoNumbers(dna)  // watch
        : stringUtils.normalizeTrait(dna);   // trait

    return string.concat(_baseURI(), slug, _uriExtension);
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

    function getWatchParts(uint256 watchTokenId)
    external
    view
    returns (
        string memory strap, uint256 strapId,
        string memory dial,  uint256 dialId,
        string memory item,  uint256 itemId,
        string memory hologram, uint256 hologramId
    )
{
    string memory dna = idCombinations[watchTokenId];
    require(bytes(dna).length > 0, "No DNA");
    require(stringUtils.isDnaValid(dna), "Invalid DNA");

    ( , strap, dial, item, hologram) = stringUtils.processString(dna);

    strapId    = combinationsId[strap];
    dialId     = combinationsId[dial];
    itemId     = combinationsId[item];
    hologramId = combinationsId[hologram];

}

}

