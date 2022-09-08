// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import { IMarketplaceAlt } from "./IMarketplaceAlt.sol";

library MarketplaceStorage{
    bytes32 constant MARKETPLACE_STORAGE_POSITION = keccak256("marketplace.storage");

    struct Data {
        uint256 totalListings;
        uint128 timeBuffer;
        uint128 bidBufferBps;

        mapping(uint256 => IMarketplaceAlt.Listing) listings;
        mapping(uint256 => mapping(address => IMarketplaceAlt.Offer)) offers;
        mapping(uint256 => IMarketplaceAlt.Offer) winningBid;
    }

    function marketplaceStorage() internal pure returns (Data storage marketplaceData) {
        bytes32 position = MARKETPLACE_STORAGE_POSITION;
        assembly {
            marketplaceData.slot := position
        }
    }
}