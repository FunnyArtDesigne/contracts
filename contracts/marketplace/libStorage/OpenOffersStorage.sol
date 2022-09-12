// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./OpenOffers.sol";

library OpenOffersStorage{
    bytes32 constant OPEN_OFFERS_STORAGE_POSITION = keccak256("open.offers.storage");

    struct Data {
        uint256 totalOpenOffers;
        mapping(uint256 => IOpenOffers.GenericOffer) openOffer;
    }

    function openOffersStorage() internal pure returns (Data storage openOffersData) {
        bytes32 position = OPEN_OFFERS_STORAGE_POSITION;
        assembly {
            openOffersData.slot := position
        }
    }
}