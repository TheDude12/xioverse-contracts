// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract XioverseMarketplace is Ownable, ReentrancyGuard {
    // 🔹 State Variables

    struct Listing {
        address seller;
        uint256 price;
    }

    struct Offer {
        uint256 amount;
        uint256 expiration;
    }

    struct Auction {
        address seller;
        uint256 highestBid;
        address highestBidder;
        uint256 endTime;
        bool active;
    }

    struct SaleHistory {
        address buyer;
        uint256 price;
        uint256 timestamp;
    }

    IERC20 public usdcxm;
    address public immutable nftContract;
    address public royaltyRecipient;
    uint256 public constant ROYALTY_BASIS_POINTS = 1000; // 10%
    bool public usdcMode = false;

    mapping(uint256 => Listing) public listings;
    mapping(uint256 => mapping(address => Offer)) public offers;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => SaleHistory[]) public saleHistory;

    // 🔹 Events

    event NFTListed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTUnlisted(uint256 indexed tokenId);
    event NFTSold(uint256 indexed tokenId, address seller, address buyer, uint256 price);
    event OfferMade(uint256 indexed tokenId, address buyer, uint256 amount, uint256 expiration);
    event OfferAccepted(uint256 indexed tokenId, address seller, address buyer, uint256 amount);
    event OfferCancelled(uint256 indexed tokenId, address buyer);
    event OfferRejected(uint256 indexed tokenId, address buyer);
    event AuctionStarted(uint256 indexed tokenId, uint256 endTime);
    event BidPlaced(uint256 indexed tokenId, address bidder, uint256 amount);
    event AuctionEnded(uint256 indexed tokenId, address winner, uint256 amount);
    event AuctionFailed(uint256 indexed tokenId);
    event USDCPaymentModeChanged(bool enabled);

    // 🔹 Constructor

    constructor(address _usdcxm, address _nftContract) Ownable(msg.sender) {
        usdcxm = IERC20(_usdcxm);
        nftContract = _nftContract;
        royaltyRecipient = 0x00fC469238E424c31d06F9A21d38531A9382F57D;
    }

    // 🔹 Admin

    function setRoyaltyRecipient(address _recipient) external onlyOwner {
        royaltyRecipient = _recipient;
    }

     function setUSDCMode(bool _mode) external onlyOwner {
        usdcMode = _mode;
        emit USDCPaymentModeChanged(_mode);
    }

    function setUSDCContract(address newUSDC) external onlyOwner {
    require(newUSDC != address(0), "Invalid address");
    usdcxm = IERC20(newUSDC);
    }

    // 🔹 Listing

    function listNFT(uint256 tokenId, uint256 price) external {
        require(listings[tokenId].seller == address(0), "Already listed");
        require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner");
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "Marketplace not approved"
        );
        listings[tokenId] = Listing(msg.sender, price);
        emit NFTListed(tokenId, msg.sender, price);
    }

    function updateListing(uint256 tokenId, uint256 newPrice) external {
        Listing storage l = listings[tokenId];
        require(l.seller == msg.sender, "Not seller");
        l.price = newPrice;
        emit NFTListed(tokenId, msg.sender, newPrice);
    }

    function unlistNFT(uint256 tokenId) public {
        Listing memory l = listings[tokenId];
        require(msg.sender == l.seller || msg.sender == owner(), "Not authorized");
        delete listings[tokenId];
        emit NFTUnlisted(tokenId);
    }

    function buyNFT(uint256 tokenId) external nonReentrant {
        Listing memory l = listings[tokenId];
        require(l.price > 0, "Not listed");
        require(IERC721(nftContract).ownerOf(tokenId) == l.seller, "NFT not owned by seller");

        uint256 royalty = (l.price * ROYALTY_BASIS_POINTS) / 10000;
        require(usdcxm.transferFrom(msg.sender, royaltyRecipient, royalty), "Royalty failed");
        require(usdcxm.transferFrom(msg.sender, l.seller, l.price - royalty), "Payment failed");

        IERC721(nftContract).safeTransferFrom(l.seller, msg.sender, tokenId);
        delete listings[tokenId];

        saleHistory[tokenId].push(SaleHistory(msg.sender, l.price, block.timestamp));
        emit NFTSold(tokenId, l.seller, msg.sender, l.price);
    }

    function buyFor(address to, uint256 tokenId) external nonReentrant {
        Listing memory l = listings[tokenId];
        require(l.price > 0, "Not listed");
        require(IERC721(nftContract).ownerOf(tokenId) == l.seller, "NFT not owned by seller");

        uint256 royalty = (l.price * ROYALTY_BASIS_POINTS) / 10000;
        require(usdcxm.transferFrom(msg.sender, royaltyRecipient, royalty), "Royalty failed");
        require(usdcxm.transferFrom(msg.sender, l.seller, l.price - royalty), "Payment failed");

        IERC721(nftContract).safeTransferFrom(l.seller, to, tokenId);
        delete listings[tokenId];

        saleHistory[tokenId].push(SaleHistory(to, l.price, block.timestamp));
        emit NFTSold(tokenId, l.seller, to, l.price);
    }

    // 🔹 Offers

    function makeOffer(uint256 tokenId, uint256 amount, uint256 expiration) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(expiration > block.timestamp, "Invalid expiration");
        require(offers[tokenId][msg.sender].amount == 0, "Offer already exists");

        require(usdcxm.transferFrom(msg.sender, address(this), amount), "Payment failed");

        offers[tokenId][msg.sender] = Offer(amount, expiration);
        emit OfferMade(tokenId, msg.sender, amount, expiration);
    }
    
     function makeOfferFor(uint256 tokenId, uint256 amount, uint256 expiration, address buyer) external nonReentrant {
        require(usdcMode, "Crossmint offer mode disabled");
        require(amount > 0, "Invalid amount");
        require(expiration > block.timestamp, "Invalid expiration");
        require(offers[tokenId][buyer].amount == 0, "Offer already exists");

        require(usdcxm.transferFrom(msg.sender, address(this), amount), "Payment failed");

        offers[tokenId][buyer] = Offer(amount, expiration);
        emit OfferMade(tokenId, buyer, amount, expiration);
    }


    function cancelOffer(uint256 tokenId) external {
        Offer memory o = offers[tokenId][msg.sender];
        require(o.amount > 0, "No offer");

        delete offers[tokenId][msg.sender];
        require(usdcxm.transfer(msg.sender, o.amount), "Refund failed");
        emit OfferCancelled(tokenId, msg.sender);
    }

    function cancelExpiredOffer(uint256 tokenId, address buyer) external {
    Offer memory o = offers[tokenId][buyer];
    require(o.amount > 0, "No offer found");
    require(block.timestamp > o.expiration, "Offer not yet expired");

    delete offers[tokenId][buyer];
    require(usdcxm.transfer(buyer, o.amount), "Refund failed");
    emit OfferCancelled(tokenId, buyer);
}


    function rejectOffer(uint256 tokenId, address buyer) external {
    require(IERC721(nftContract).ownerOf(tokenId) == msg.sender || msg.sender == owner(), "Not authorized");

    Offer memory o = offers[tokenId][buyer];
    require(o.amount > 0, "No offer found");

    delete offers[tokenId][buyer];
    require(usdcxm.transfer(buyer, o.amount), "Refund failed");
    emit OfferRejected(tokenId, buyer);
}


    function acceptOffer(uint256 tokenId, address buyer) external nonReentrant {
    // Ensure the caller is the current owner of the NFT
    require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Caller doesn't own NFT");

    // Ensure the offer exists and has not expired
    Offer memory o = offers[tokenId][buyer];
    require(o.amount > 0 && o.expiration >= block.timestamp, "Invalid or expired offer");

    // Calculate royalty
    uint256 royalty = (o.amount * ROYALTY_BASIS_POINTS) / 10000;

    // Transfer royalty and payment
    require(usdcxm.transfer(royaltyRecipient, royalty), "Royalty transfer failed");
    require(usdcxm.transfer(msg.sender, o.amount - royalty), "Seller payment failed");

    // Transfer the NFT to the buyer
    IERC721(nftContract).safeTransferFrom(msg.sender, buyer, tokenId);

    // Clean up
    delete offers[tokenId][buyer];
    delete listings[tokenId]; // In case it's still listed

    // Record the sale
    saleHistory[tokenId].push(SaleHistory(buyer, o.amount, block.timestamp));

    emit OfferAccepted(tokenId, msg.sender, buyer, o.amount);
}

    // 🔹 Auctions

   function startAuction(uint256 tokenId, uint256 startingBid, uint256 duration) external {
    require(!auctions[tokenId].active, "Auction active");
    require(duration <= 30 days, "Max 30 days");
    require(IERC721(nftContract).ownerOf(tokenId) == msg.sender, "Not owner");
    require(
        IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
        IERC721(nftContract).getApproved(tokenId) == address(this),
        "Marketplace not approved"
    );

    auctions[tokenId] = Auction(msg.sender, startingBid, address(0), block.timestamp + duration, true);
    emit AuctionStarted(tokenId, block.timestamp + duration);
}

function bid(uint256 tokenId, uint256 amount) external nonReentrant {
    Auction storage a = auctions[tokenId];
    require(a.active && block.timestamp < a.endTime, "Auction ended");

    // Accept amount >= starting bid if no bids yet
    if (a.highestBidder == address(0)) {
        require(amount >= a.highestBid, "Bid must meet or exceed reserve");
    } else {
        require(amount > a.highestBid, "Bid must be higher than current");
    }

    require(usdcxm.transferFrom(msg.sender, address(this), amount), "Transfer failed");

    if (a.highestBidder != address(0)) {
        require(usdcxm.transfer(a.highestBidder, a.highestBid), "Refund failed");
    }

    a.highestBid = amount;
    a.highestBidder = msg.sender;
    emit BidPlaced(tokenId, msg.sender, amount);
}

function bidFor(uint256 tokenId, uint256 amount, address bidder) external nonReentrant {
    require(usdcMode, "Crossmint bid mode disabled");

    Auction storage a = auctions[tokenId];
    require(a.active && block.timestamp < a.endTime, "Auction not active or expired");

    if (a.highestBidder == address(0)) {
        require(amount >= a.highestBid, "Bid must meet or exceed reserve");
    } else {
        require(amount > a.highestBid, "Bid must be higher than current");
    }

    require(usdcxm.transferFrom(msg.sender, address(this), amount), "Transfer failed");

    if (a.highestBidder != address(0)) {
        require(usdcxm.transfer(a.highestBidder, a.highestBid), "Refund failed");
    }

    a.highestBid = amount;
    a.highestBidder = bidder;
    emit BidPlaced(tokenId, bidder, amount);
}

function endAuction(uint256 tokenId) external nonReentrant {
    Auction storage a = auctions[tokenId];

    require(a.active, "No active auction");

    // Allow anyone to end only after the scheduled end time
    // Allow the seller to end early
    bool isAfterEndTime = block.timestamp >= a.endTime;
    bool isSeller = msg.sender == a.seller;

    require(isAfterEndTime || isSeller, "Not authorized to end early");

    a.active = false;

    // If no bids were placed, just emit failed
    if (a.highestBidder == address(0)) {
        emit AuctionFailed(tokenId);
        return;
    }

    // Ensure seller still owns and has approved the NFT
    if (
        IERC721(nftContract).ownerOf(tokenId) == a.seller &&
        (
            IERC721(nftContract).isApprovedForAll(a.seller, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this)
        )
    ) {
        uint256 royalty = (a.highestBid * ROYALTY_BASIS_POINTS) / 10000;
        require(usdcxm.transfer(royaltyRecipient, royalty), "Royalty failed");
        require(usdcxm.transfer(a.seller, a.highestBid - royalty), "Payout failed");

        IERC721(nftContract).safeTransferFrom(a.seller, a.highestBidder, tokenId);
        saleHistory[tokenId].push(SaleHistory(a.highestBidder, a.highestBid, block.timestamp));
        emit AuctionEnded(tokenId, a.highestBidder, a.highestBid);
    } else {
        // If seller no longer owns the NFT or hasn't approved it
        require(usdcxm.transfer(a.highestBidder, a.highestBid), "Refund failed");
        emit AuctionFailed(tokenId);
    }
}


function cancelAuction(uint256 tokenId) external {
    Auction memory a = auctions[tokenId];
    require(a.active, "No active auction");

    require(
        msg.sender == a.seller || IERC721(nftContract).ownerOf(tokenId) != a.seller,
        "Not authorized to cancel"
    );

    auctions[tokenId].active = false;

    if (a.highestBidder != address(0)) {
        require(usdcxm.transfer(a.highestBidder, a.highestBid), "Refund failed");
    }

    emit AuctionFailed(tokenId);
}



    // 🔹 Views

    function getSaleHistory(uint256 tokenId) external view returns (SaleHistory[] memory) {
        return saleHistory[tokenId];
    }
}
