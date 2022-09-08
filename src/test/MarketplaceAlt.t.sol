// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { IMarketplaceAlt } from "contracts/marketplace/libStorage/MarketplaceAlt.sol";
import { MarketplaceEntrypoint } from "contracts/marketplace/libStorage/MarketplaceEntrypoint.sol";
import {TWProxy} from "contracts/TWProxy.sol";

// Test imports
import "./utils/BaseTest.sol";

contract MarketplaceAltTest is BaseTest {
    MarketplaceEntrypoint public marketplace;

    MarketplaceEntrypoint.ListingParameters public directListing;
    MarketplaceEntrypoint.ListingParameters public auctionListing;

    function setUp() public override {
        super.setUp();
        
        address marketplaceImpl = address(new MarketplaceEntrypoint(address(123), address(weth)));
        bytes memory initData = abi.encodeCall(
              MarketplaceEntrypoint.initialize,
            (deployer, CONTRACT_URI, forwarders(), platformFeeRecipient, platformFeeBps)
        );
        address proxy = address(new TWProxy(marketplaceImpl, initData));
        marketplace = MarketplaceEntrypoint(payable(proxy));
    }

    function createERC721Listing(
        address to,
        address currency,
        uint256 price,
        IMarketplaceAlt.ListingType listingType
    ) public returns (uint256 listingId, MarketplaceEntrypoint.ListingParameters memory listing) {
        uint256 tokenId = erc721.nextTokenIdToMint();
        erc721.mint(to, 1);
        vm.prank(to);
        erc721.setApprovalForAll(address(marketplace), true);

        listing.assetContract = address(erc721);
        listing.tokenId = tokenId;
        listing.startTime = 0;
        listing.secondsUntilEndTime = 1 * 24 * 60 * 60; // 1 day
        listing.quantityToList = 1;
        listing.currencyToAccept = currency;
        listing.reservePricePerToken = 0;
        listing.buyoutPricePerToken = price;
        listing.listingType = listingType;

        listingId = marketplace.totalListings();
        vm.prank(to);
        marketplace.createListing(listing);
    }

    function getListing(uint256 _listingId) public view returns (MarketplaceEntrypoint.Listing memory listing) {
        listing = marketplace.listings(_listingId);
    }

    function getWinningBid(uint256 _listingId) public view returns (MarketplaceEntrypoint.Offer memory winningBid) {
        winningBid = marketplace.winningBid(_listingId);
    }

    function test_createListing_auctionListing() public {
        vm.warp(0);
        (uint256 createdListingId, MarketplaceEntrypoint.ListingParameters memory createdListing) = createERC721Listing(
            getActor(0),
            NATIVE_TOKEN,
            1 ether,
            IMarketplaceAlt.ListingType.Auction
        );

        MarketplaceEntrypoint.Listing memory listing = getListing(createdListingId);
        assertEq(createdListingId, listing.listingId);
        assertEq(createdListing.assetContract, listing.assetContract);
        assertEq(createdListing.tokenId, listing.tokenId);
        assertEq(createdListing.startTime, listing.startTime);
        assertEq(createdListing.startTime + createdListing.secondsUntilEndTime, listing.endTime);
        assertEq(createdListing.quantityToList, listing.quantity);
        assertEq(createdListing.currencyToAccept, listing.currency);
        assertEq(createdListing.reservePricePerToken, listing.reservePricePerToken);
        assertEq(createdListing.buyoutPricePerToken, listing.buyoutPricePerToken);
        assertEq(uint8(IMarketplaceAlt.TokenType.ERC721), uint8(listing.tokenType));
        assertEq(uint8(IMarketplaceAlt.ListingType.Auction), uint8(listing.listingType));
    }

    function test_offer_bidAuctionNativeToken() public {
        vm.deal(getActor(0), 100 ether);

        MarketplaceEntrypoint.Offer memory winningBid;
        vm.warp(0);
        (uint256 listingId, ) = createERC721Listing(
            getActor(0),
            NATIVE_TOKEN,
            123456 ether,
            IMarketplaceAlt.ListingType.Auction
        );

        assertEq(getActor(0).balance, 100 ether);

        vm.prank(getActor(0));
        vm.warp(1);
        marketplace.offer{ value: 1 ether }(listingId, 1, NATIVE_TOKEN, 1 ether, type(uint256).max);
        winningBid = getWinningBid(listingId);
        assertEq(getActor(0).balance, 99 ether);
        assertEq(winningBid.listingId, listingId);
        assertEq(winningBid.offeror, getActor(0));
        assertEq(winningBid.quantityWanted, 1);
        assertEq(winningBid.currency, NATIVE_TOKEN);
        assertEq(winningBid.pricePerToken, 1 ether);

        vm.prank(getActor(0));
        vm.warp(2);
        marketplace.offer{ value: 2 ether }(listingId, 1, NATIVE_TOKEN, 2 ether, type(uint256).max);
        winningBid = getWinningBid(listingId);
        assertEq(getActor(0).balance, 98 ether);
        assertEq(winningBid.listingId, listingId);
        assertEq(winningBid.offeror, getActor(0));
        assertEq(winningBid.quantityWanted, 1);
        assertEq(winningBid.currency, NATIVE_TOKEN);
        assertEq(winningBid.pricePerToken, 2 ether);
    }

    function test_closeAuctionForCreator_afterBuyout() public {
        vm.deal(getActor(0), 100 ether);
        vm.deal(getActor(1), 100 ether);

        // Actor-0 creates an auction listing.
        vm.prank(getActor(0));
        vm.warp(0);
        (uint256 listingId, ) = createERC721Listing(
            getActor(0),
            NATIVE_TOKEN,
            5 ether,
            IMarketplaceAlt.ListingType.Auction
        );

        MarketplaceEntrypoint.Listing memory listing = getListing(listingId);
        assertEq(erc721.ownerOf(listing.tokenId), address(marketplace));
        assertEq(weth.balanceOf(address(marketplace)), 0);

        /**
         *  Actor-1 bids with buyout price. Outcome:
         *      - Actor-1 receives auctioned items escrowed in Marketplace.
         *      - Winning bid amount is escrowed in the contract.
         */
        vm.prank(getActor(1));
        vm.warp(1);
        marketplace.offer{ value: 5 ether }(listingId, 1, NATIVE_TOKEN, 5 ether, type(uint256).max);

        assertEq(erc721.ownerOf(listing.tokenId), getActor(1));
        assertEq(weth.balanceOf(address(marketplace)), 5 ether);

        /**
         *  Auction is closed for the auction creator i.e. Actor-0. Outcome:
         *      - Actor-0 receives the escrowed buyout amount.
         */

        uint256 listerBalBefore = getActor(0).balance;

        vm.warp(2);
        vm.prank(getActor(2));
        marketplace.closeAuction(listingId, getActor(0));

        uint256 listerBalAfter = getActor(0).balance;
        uint256 winningBidPostFee = (5 ether * (MAX_BPS - platformFeeBps)) / MAX_BPS;

        assertEq(listerBalAfter - listerBalBefore, winningBidPostFee);
        assertEq(weth.balanceOf(address(marketplace)), 0);
    }

    function test_acceptOffer_whenListingAcceptsNativeToken() public {
        vm.deal(getActor(0), 100 ether);
        vm.deal(getActor(1), 100 ether);

        // Actor-0 creates a direct listing with NATIVE_TOKEN as accepted currency.
        vm.prank(getActor(0));
        vm.warp(0);
        (uint256 listingId, ) = createERC721Listing(
            getActor(0),
            NATIVE_TOKEN,
            5 ether,
            IMarketplaceAlt.ListingType.Direct
        );

        vm.startPrank(getActor(1));

        // Actor-1 mints 4 ether worth of WETH
        assertEq(weth.balanceOf(getActor(1)), 0);
        weth.deposit{ value: 4 ether }();
        assertEq(weth.balanceOf(getActor(1)), 4 ether);

        // Actor-1 makes an offer to the direct listing for 4 WETH.
        weth.approve(address(marketplace), 4 ether);

        vm.warp(1);
        marketplace.offer(listingId, 1, NATIVE_TOKEN, 4 ether, type(uint256).max);

        vm.stopPrank();

        // Actor-0 successfully accepts the offer.
        MarketplaceEntrypoint.Listing memory listing = getListing(listingId);
        assertEq(erc721.ownerOf(listing.tokenId), getActor(0));
        assertEq(weth.balanceOf(getActor(0)), 0);
        assertEq(weth.balanceOf(getActor(1)), 4 ether);

        uint256 offerValuePostFee = (4 ether * (MAX_BPS - platformFeeBps)) / MAX_BPS;

        vm.prank(getActor(0));
        vm.warp(2);
        marketplace.acceptOffer(listingId, getActor(1), address(weth), 4 ether);
        assertEq(erc721.ownerOf(listing.tokenId), getActor(1));
        assertEq(weth.balanceOf(getActor(0)), offerValuePostFee);
        assertEq(weth.balanceOf(getActor(1)), 0);
    }

    function test_acceptOffer_expiration() public {
        vm.deal(getActor(0), 100 ether);
        vm.deal(getActor(1), 100 ether);

        // Actor-0 creates a direct listing with NATIVE_TOKEN as accepted currency.
        vm.prank(getActor(0));
        (uint256 listingId, ) = createERC721Listing(
            getActor(0),
            NATIVE_TOKEN,
            5 ether,
            IMarketplaceAlt.ListingType.Direct
        );

        vm.startPrank(getActor(1));

        // Actor-1 mints 4 ether worth of WETH
        assertEq(weth.balanceOf(getActor(1)), 0);
        weth.deposit{ value: 4 ether }();
        assertEq(weth.balanceOf(getActor(1)), 4 ether);

        // Actor-1 makes an offer to the direct listing for 4 WETH.
        weth.approve(address(marketplace), 4 ether);

        vm.warp(2);
        marketplace.offer(listingId, 1, NATIVE_TOKEN, 4 ether, 0);

        vm.stopPrank();

        // Actor-0 successfully accepts the offer.
        MarketplaceEntrypoint.Listing memory listing = getListing(listingId);
        assertEq(erc721.ownerOf(listing.tokenId), getActor(0));
        assertEq(weth.balanceOf(getActor(0)), 0);
        assertEq(weth.balanceOf(getActor(1)), 4 ether);

        vm.prank(getActor(0));
        vm.expectRevert(bytes("EXPIRED"));
        marketplace.acceptOffer(listingId, getActor(1), address(weth), 4 ether);

        vm.prank(getActor(1));
        vm.warp(3);
        marketplace.offer(listingId, 1, NATIVE_TOKEN, 4 ether, 5);

        vm.prank(getActor(0));
        vm.warp(4);
        marketplace.acceptOffer(listingId, getActor(1), address(weth), 4 ether);
    }

    function test_createListing_startTime_past() public {
        address to = getActor(0);
        uint256 tokenId = erc721.nextTokenIdToMint();
        vm.startPrank(to);
        erc721.mint(to, 1);
        erc721.setApprovalForAll(address(marketplace), true);

        // initial block.timestamp
        vm.warp(100 days);

        MarketplaceEntrypoint.ListingParameters memory listing;
        listing.assetContract = address(erc721);
        listing.tokenId = tokenId;
        listing.startTime = 0;
        listing.secondsUntilEndTime = 1 * 24 * 60 * 60; // 1 day
        listing.quantityToList = 1;
        listing.currencyToAccept = NATIVE_TOKEN;
        listing.reservePricePerToken = 0;
        listing.buyoutPricePerToken = 1 ether;
        listing.listingType = IMarketplaceAlt.ListingType.Direct;

        vm.expectRevert(bytes("ST"));
        marketplace.createListing(listing);
    }

    function test_createListing_startTime_pastWithBuffer() public {
        address to = getActor(0);
        uint256 tokenId = erc721.nextTokenIdToMint();
        vm.startPrank(to);
        erc721.mint(to, 1);
        erc721.setApprovalForAll(address(marketplace), true);

        // initial block.timestamp
        vm.warp(100 days);

        MarketplaceEntrypoint.ListingParameters memory listing;
        listing.assetContract = address(erc721);
        listing.tokenId = tokenId;
        listing.startTime = block.timestamp - 30 minutes;
        listing.secondsUntilEndTime = 1 * 24 * 60 * 60; // 1 day
        listing.quantityToList = 1;
        listing.currencyToAccept = NATIVE_TOKEN;
        listing.reservePricePerToken = 0;
        listing.buyoutPricePerToken = 1 ether;
        listing.listingType = IMarketplaceAlt.ListingType.Direct;

        marketplace.createListing(listing);
    }

    function test_createListing_startTime_now() public {
        address to = getActor(0);
        uint256 tokenId = erc721.nextTokenIdToMint();
        vm.startPrank(to);
        erc721.mint(to, 1);
        erc721.setApprovalForAll(address(marketplace), true);

        // initial block.timestamp
        vm.warp(100 days);

        MarketplaceEntrypoint.ListingParameters memory listing;
        listing.assetContract = address(erc721);
        listing.tokenId = tokenId;
        listing.startTime = block.timestamp;
        listing.secondsUntilEndTime = 1 * 24 * 60 * 60; // 1 day
        listing.quantityToList = 1;
        listing.currencyToAccept = NATIVE_TOKEN;
        listing.reservePricePerToken = 0;
        listing.buyoutPricePerToken = 1 ether;
        listing.listingType = IMarketplaceAlt.ListingType.Direct;

        marketplace.createListing(listing);
    }

    function test_createListing_startTime_future() public {
        address to = getActor(0);
        uint256 tokenId = erc721.nextTokenIdToMint();
        vm.startPrank(to);
        erc721.mint(to, 1);
        erc721.setApprovalForAll(address(marketplace), true);

        // initial block.timestamp
        vm.warp(100 days);

        MarketplaceEntrypoint.ListingParameters memory listing;
        listing.assetContract = address(erc721);
        listing.tokenId = tokenId;
        listing.startTime = 200 days;
        listing.secondsUntilEndTime = 1 * 24 * 60 * 60; // 1 day
        listing.quantityToList = 1;
        listing.currencyToAccept = NATIVE_TOKEN;
        listing.reservePricePerToken = 0;
        listing.buyoutPricePerToken = 1 ether;
        listing.listingType = IMarketplaceAlt.ListingType.Direct;

        marketplace.createListing(listing);
    }

    function test_updateListing_startTime_past() public {
        address to = getActor(0);
        uint256 tokenId = erc721.nextTokenIdToMint();
        vm.startPrank(to);
        erc721.mint(to, 1);
        erc721.setApprovalForAll(address(marketplace), true);

        vm.warp(100 days);

        // future listing
        MarketplaceEntrypoint.ListingParameters memory listing;
        listing.assetContract = address(erc721);
        listing.tokenId = tokenId;
        listing.startTime = 200 days;
        listing.secondsUntilEndTime = 1 * 24 * 60 * 60; // 1 day
        listing.quantityToList = 1;
        listing.currencyToAccept = NATIVE_TOKEN;
        listing.reservePricePerToken = 0;
        listing.buyoutPricePerToken = 1 ether;
        listing.listingType = IMarketplaceAlt.ListingType.Direct;
        marketplace.createListing(listing);

        // update into the past
        vm.expectRevert(bytes("ST"));
        marketplace.updateListing(0, 1, 0, 1 ether, NATIVE_TOKEN, 99 days, 0);
    }

    function test_updateListing_startTime_future() public {
        address to = getActor(0);
        uint256 tokenId = erc721.nextTokenIdToMint();
        vm.startPrank(to);
        erc721.mint(to, 1);
        erc721.setApprovalForAll(address(marketplace), true);

        vm.warp(100 days);

        // future listing
        MarketplaceEntrypoint.ListingParameters memory listing;
        listing.assetContract = address(erc721);
        listing.tokenId = tokenId;
        listing.startTime = 200 days;
        listing.secondsUntilEndTime = 1 * 24 * 60 * 60; // 1 day
        listing.quantityToList = 1;
        listing.currencyToAccept = NATIVE_TOKEN;
        listing.reservePricePerToken = 0;
        listing.buyoutPricePerToken = 1 ether;
        listing.listingType = IMarketplaceAlt.ListingType.Direct;
        marketplace.createListing(listing);

        // future time
        marketplace.updateListing(0, 1, 0, 1 ether, NATIVE_TOKEN, 205 days, 0);
    }

    function test_updateListing_startTimeAndEndTime() public {
        address to = getActor(0);
        uint256 tokenId = erc721.nextTokenIdToMint();
        vm.startPrank(to);
        erc721.mint(to, 1);
        erc721.setApprovalForAll(address(marketplace), true);

        vm.warp(100 days);

        // future listing
        MarketplaceEntrypoint.ListingParameters memory listing;
        listing.assetContract = address(erc721);
        listing.tokenId = tokenId;
        listing.startTime = 200 days;
        listing.secondsUntilEndTime = 1 * 24 * 60 * 60; // 1 day
        listing.quantityToList = 1;
        listing.currencyToAccept = NATIVE_TOKEN;
        listing.reservePricePerToken = 0;
        listing.buyoutPricePerToken = 1 ether;
        listing.listingType = IMarketplaceAlt.ListingType.Direct;
        marketplace.createListing(listing);

        // future time
        marketplace.updateListing(0, 1, 0, 1 ether, NATIVE_TOKEN, 205 days, 1 days);
        MarketplaceEntrypoint.Listing memory updatedListing = getListing(0);
        assertEq(205 days, updatedListing.startTime);
        assertEq(205 days + 1 days, updatedListing.endTime);
    }
}
