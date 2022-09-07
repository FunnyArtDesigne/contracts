// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { IMarketplace } from "../interfaces/marketplace/IMarketplace.sol";

library MarketplaceStorage{
    bytes32 constant MARKETPLACE_STORAGE_POSITION = keccak256("marketplace.storage");

    struct Data {
        uint256 totalListings;
        uint128 timeBuffer;
        uint128 bidBufferBps;

        mapping(uint256 => IMarketplace.Listing) listings;
        mapping(uint256 => mapping(address => IMarketplace.Offer)) offers;
        mapping(uint256 => IMarketplace.Offer) winningBid;
    }

    function marketplaceStorage() internal pure returns (Data storage marketplaceData) {
        bytes32 position = MARKETPLACE_STORAGE_POSITION;
        assembly {
            marketplaceData.slot := position
        }
    }
}