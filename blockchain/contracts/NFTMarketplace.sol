// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

contract NFTMarketplace is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _itemCounter; //start from 1
    Counters.Counter private _itemSoldCounter;

    uint256 marketOwnerKoef = 10;
    uint256 sellerKoef = 100 - marketOwnerKoef;

    enum State {
        Created,
        Release,
        Inactive
    }

    struct MarketItem {
        uint256 id;
        address nftContract;
        uint256 tokenId;
        address payable seller;
        address payable buyer;
        uint256 price;
        State state;
    }

    mapping(uint256 => MarketItem) private marketItems;

    event MarketItemCreated(
        uint256 indexed id,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price,
        State state
    );

    event MarketItemSold(
        uint256 indexed id,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price,
        State state
    );

    function setMarketOwnerFee(uint256 ownerFee) public onlyOwner {
        marketOwnerKoef = ownerFee;
    }

    function transferMarketOwnership(address newOwner)
        public
        virtual
        onlyOwner
    {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        transferOwnership(newOwner);
    }

    function createMarketItem(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) public payable nonReentrant {
        require(price > 0, "Price must be at least 1 wei");

        _itemCounter.increment();
        uint256 id = _itemCounter.current();

        marketItems[id] = MarketItem(
            id,
            nftContract,
            tokenId,
            payable(msg.sender),
            payable(address(0)),
            price,
            State.Created
        );

        require(
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "NFT must be approved to market"
        );

        emit MarketItemCreated(
            id,
            nftContract,
            tokenId,
            msg.sender,
            address(0),
            price,
            State.Created
        );
    }

    function deleteMarketItem(uint256 itemId) public nonReentrant {
        require(itemId <= _itemCounter.current(), "id must <= item count");
        require(
            marketItems[itemId].state == State.Created,
            "item must be on market"
        );
        MarketItem storage item = marketItems[itemId];

        require(
            IERC721(item.nftContract).ownerOf(item.tokenId) == msg.sender,
            "must be the owner"
        );
        require(
            IERC721(item.nftContract).getApproved(item.tokenId) ==
                address(this),
            "NFT must be approved to market"
        );

        item.state = State.Inactive;

        emit MarketItemSold(
            itemId,
            item.nftContract,
            item.tokenId,
            item.seller,
            address(0),
            0,
            State.Inactive
        );
    }

    function createMarketSale(address nftContract, uint256 id)
        public
        payable
        nonReentrant
    {
        MarketItem storage item = marketItems[id]; //should use storage!!!!
        uint256 tokenId = item.tokenId;
        uint256 price = item.price;
        // uint256 marketOwnerValue = (msg.value * 100) / marketOwnerKoef;
        // uint256 sellerValue = (msg.value * 100) / sellerKoef;

        require(msg.value == price, "Please submit the asking price");
        require(
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "NFT must be approved to market"
        );

        item.buyer = payable(msg.sender);
        item.state = State.Release;
        _itemSoldCounter.increment();

        IERC721(nftContract).transferFrom(item.seller, msg.sender, tokenId);
        // payable(owner()).transfer(marketOwnerValue);
        item.seller.transfer(price);

        emit MarketItemSold(
            id,
            nftContract,
            tokenId,
            item.seller,
            msg.sender,
            price,
            State.Release
        );
    }

    function fetchActiveItems() public view returns (MarketItem[] memory) {
        return fetchHepler(FetchOperator.ActiveItems);
    }

    function fetchMyPurchasedItems() public view returns (MarketItem[] memory) {
        return fetchHepler(FetchOperator.MyPurchasedItems);
    }

    function fetchMyCreatedItems() public view returns (MarketItem[] memory) {
        return fetchHepler(FetchOperator.MyCreatedItems);
    }

    enum FetchOperator {
        ActiveItems,
        MyPurchasedItems,
        MyCreatedItems
    }

    function fetchHepler(FetchOperator _op)
        private
        view
        returns (MarketItem[] memory)
    {
        uint256 total = _itemCounter.current();

        uint256 itemCount = 0;
        for (uint256 i = 1; i <= total; i++) {
            if (isCondition(marketItems[i], _op)) {
                itemCount++;
            }
        }

        uint256 index = 0;
        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 1; i <= total; i++) {
            if (isCondition(marketItems[i], _op)) {
                items[index] = marketItems[i];
                index++;
            }
        }
        return items;
    }

    function isCondition(MarketItem memory item, FetchOperator _op)
        private
        view
        returns (bool)
    {
        if (_op == FetchOperator.MyCreatedItems) {
            return
                (item.seller == msg.sender && item.state != State.Inactive)
                    ? true
                    : false;
        } else if (_op == FetchOperator.MyPurchasedItems) {
            return (item.buyer == msg.sender) ? true : false;
        } else if (_op == FetchOperator.ActiveItems) {
            return
                (item.buyer == address(0) &&
                    item.state == State.Created &&
                    (IERC721(item.nftContract).getApproved(item.tokenId) ==
                        address(this)))
                    ? true
                    : false;
        } else {
            return false;
        }
    }
}
