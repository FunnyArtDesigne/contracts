// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import "@openzeppelin/contracts-upgradeable/interfaces/IERC2981Upgradeable.sol";

// Helper libraries
import "../../lib/CurrencyTransferLib.sol";

import { IMarketplaceAlt } from "./IMarketplaceAlt.sol";

import { IPermissions } from "../../extension/Permissions.sol";
import { IPlatformFee } from "./PlatformFee.sol";

import "./OpenOffersStorage.sol";

interface IERC2771Context {
    function isTrustedForwarder(address forwarder) external view returns (bool);
}

interface IOpenOffers {

    event NewOpenOffer(uint256 indexed offerId, address indexed offeror, GenericOffer offer);
    event OpenOfferAccepted(uint256 indexed offerId, address indexed offeror, address indexed tokenOwner, GenericOffer offer);
    event OpenOfferCancelled(uint256 indexed offerId, address indexed offeror);

    struct GenericOffer {
        uint256 offerId;
        address offeror;
        address assetContract;
        uint256 tokenId;
        IMarketplaceAlt.TokenType tokenType;
        uint256 quantityWanted;
        address currency;
        uint256 pricePerToken;
        uint256 expirationTimestamp;
    }

    function offerGeneric(
        address assetContract,
        uint256 tokenId,
        IMarketplaceAlt.TokenType _tokenType,
        uint256 quantityWanted,
        address currency,
        uint256 pricePerToken,
        uint256 expirationTimestamp
    ) external returns (uint256 offerId);

    function acceptGenericOffer(uint256 offerId) external;

    function cancelOffer(uint256 offerId) external;

    function totalOpenOffers() external view returns (uint256);

    function getAllOpenOffers() external view returns (GenericOffer[] memory);
}

contract OpenOffers is IOpenOffers {

    uint256 public constant MAX_BPS = 10_000;
    address private immutable nativeTokenWrapper;
    bytes32 private constant ASSET_ROLE = keccak256("ASSET_ROLE");

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(address _nativeTokenWrapper) {
        nativeTokenWrapper = _nativeTokenWrapper;
    }

    function offerGeneric(
        address _assetContract,
        uint256 _tokenId,
        IMarketplaceAlt.TokenType _tokenType,
        uint256 _quantityWanted,
        address _currency,
        uint256 _pricePerToken,
        uint256 _expirationTimestamp
    ) 
        external 
        returns (uint256 offerId)
    {
        OpenOffersStorage.Data storage data = OpenOffersStorage.openOffersStorage();

        require(
            IPermissions(address(this)).hasRole(ASSET_ROLE, _assetContract),
            "!ASSET_ROLE"
        );

        address offeror = _msgSender();
        validateERC20BalAndAllowance(offeror, _currency, _quantityWanted * _pricePerToken);

        offerId = data.totalOpenOffers;
        data.totalOpenOffers += 1;        

        uint256 safeQuantity = _tokenType == IMarketplaceAlt.TokenType.ERC721 ? 1 : _quantityWanted;
        GenericOffer memory newOffer = GenericOffer({
            offerId: offerId,
            offeror: offeror,
            assetContract: _assetContract,
            tokenId: _tokenId,
            tokenType: _tokenType,
            quantityWanted: safeQuantity,
            currency: _currency,
            pricePerToken: _pricePerToken,
            expirationTimestamp: _expirationTimestamp
        });

        data.openOffer[offerId] = newOffer;

        emit NewOpenOffer(offerId, offeror, newOffer);
    }

    function acceptGenericOffer(uint256 _offerId) external {

        OpenOffersStorage.Data storage data = OpenOffersStorage.openOffersStorage();
        
        GenericOffer memory offer = data.openOffer[_offerId];
        require(block.timestamp < offer.expirationTimestamp, "Offer expired");
        
        address tokenOwner = _msgSender();
        validateOwnershipAndApproval(tokenOwner, offer.assetContract, offer.tokenId, offer.quantityWanted, offer.tokenType);
        validateERC20BalAndAllowance(offer.offeror, offer.currency, offer.pricePerToken * offer.quantityWanted);

        delete data.openOffer[_offerId];

        transferListingTokens(tokenOwner, offer.offeror, offer);
        payout(offer.offeror, tokenOwner, offer.currency, offer.pricePerToken * offer.quantityWanted, offer);
        
        emit OpenOfferAccepted(_offerId, offer.offeror, tokenOwner, offer);
    }

    function cancelOffer(uint256 _offerId) external {
        OpenOffersStorage.Data storage data = OpenOffersStorage.openOffersStorage();

        address offeror = _msgSender();
        require(data.openOffer[_offerId].offeror == offeror, "Can't cancel others' offers.");

        delete data.openOffer[_offerId];

        emit OpenOfferCancelled(_offerId, offeror);
    }

    function totalOpenOffers() external view returns (uint256) {
        OpenOffersStorage.Data storage data = OpenOffersStorage.openOffersStorage();
        return data.totalOpenOffers;
    }

    function getAllOpenOffers() external view returns (GenericOffer[] memory offers) {

        OpenOffersStorage.Data storage data = OpenOffersStorage.openOffersStorage();
        
        uint256 len;
        uint256 totalOffersWithEmpty = data.totalOpenOffers;

        for(uint256 i = 0; i < totalOffersWithEmpty; i += 1) {
            if(data.openOffer[i].assetContract == address(0)) {
                continue;
            } else {
                len += 1;
            }
        }

        offers = new GenericOffer[](len);
        uint256 idx;

        for(uint256 j = 0; j < totalOffersWithEmpty; j += 1) {
            if(data.openOffer[j].assetContract == address(0)) {
                continue;
            } else {
                offers[idx] = data.openOffer[j];
            }
        }
    }

    /// @dev Validates that `_addrToCheck` owns and has approved markeplace to transfer the appropriate amount of currency
    function validateERC20BalAndAllowance(
        address _addrToCheck,
        address _currency,
        uint256 _currencyAmountToCheckAgainst
    ) internal view {
        require(
            IERC20Upgradeable(_currency).balanceOf(_addrToCheck) >= _currencyAmountToCheckAgainst &&
                IERC20Upgradeable(_currency).allowance(_addrToCheck, address(this)) >= _currencyAmountToCheckAgainst,
            "!BAL20"
        );
    }

    /// @dev Validates that `_tokenOwner` owns and has approved Market to transfer NFTs.
    function validateOwnershipAndApproval(
        address _tokenOwner,
        address _assetContract,
        uint256 _tokenId,
        uint256 _quantity,
        IMarketplaceAlt.TokenType _tokenType
    ) internal view {
        address market = address(this);
        bool isValid;

        if (_tokenType == IMarketplaceAlt.TokenType.ERC1155) {
            isValid =
                IERC1155Upgradeable(_assetContract).balanceOf(_tokenOwner, _tokenId) >= _quantity &&
                IERC1155Upgradeable(_assetContract).isApprovedForAll(_tokenOwner, market);
        } else if (_tokenType == IMarketplaceAlt.TokenType.ERC721) {
            isValid =
                IERC721Upgradeable(_assetContract).ownerOf(_tokenId) == _tokenOwner &&
                (IERC721Upgradeable(_assetContract).getApproved(_tokenId) == market ||
                    IERC721Upgradeable(_assetContract).isApprovedForAll(_tokenOwner, market));
        }

        require(isValid, "!BALNFT");
    }

    /// @dev Transfers tokens listed for sale in a direct or auction listing.
    function transferListingTokens(
        address _from,
        address _to,
        GenericOffer memory _offer
    ) internal {
        if (_offer.tokenType == IMarketplaceAlt.TokenType.ERC1155) {
            IERC1155Upgradeable(_offer.assetContract).safeTransferFrom(_from, _to, _offer.tokenId, _offer.quantityWanted, "");
        } else if (_offer.tokenType == IMarketplaceAlt.TokenType.ERC721) {
            IERC721Upgradeable(_offer.assetContract).safeTransferFrom(_from, _to, _offer.tokenId, "");
        }
    }

    /// @dev Pays out stakeholders in a sale.
    function payout(
        address _payer,
        address _payee,
        address _currencyToUse,
        uint256 _totalPayoutAmount,
        GenericOffer memory _offer
    ) internal {

        (address platformFeeRecipient, uint16 platformFeeBps) = IPlatformFee(address(this)).getPlatformFeeInfo();

        uint256 platformFeeCut = (_totalPayoutAmount * platformFeeBps) / MAX_BPS;

        uint256 royaltyCut;
        address royaltyRecipient;

        // Distribute royalties. See Sushiswap's https://github.com/sushiswap/shoyu/blob/master/contracts/base/BaseExchange.sol#L296
        try IERC2981Upgradeable(_offer.assetContract).royaltyInfo(_offer.tokenId, _totalPayoutAmount) returns (
            address royaltyFeeRecipient,
            uint256 royaltyFeeAmount
        ) {
            if (royaltyFeeRecipient != address(0) && royaltyFeeAmount > 0) {
                require(royaltyFeeAmount + platformFeeCut <= _totalPayoutAmount, "fees exceed the price");
                royaltyRecipient = royaltyFeeRecipient;
                royaltyCut = royaltyFeeAmount;
            }
        } catch {}

        // Distribute price to token owner
        address _nativeTokenWrapper = nativeTokenWrapper;

        CurrencyTransferLib.transferCurrencyWithWrapper(
            _currencyToUse,
            _payer,
            platformFeeRecipient,
            platformFeeCut,
            _nativeTokenWrapper
        );
        CurrencyTransferLib.transferCurrencyWithWrapper(
            _currencyToUse,
            _payer,
            royaltyRecipient,
            royaltyCut,
            _nativeTokenWrapper
        );
        CurrencyTransferLib.transferCurrencyWithWrapper(
            _currencyToUse,
            _payer,
            _payee,
            _totalPayoutAmount - (platformFeeCut + royaltyCut),
            _nativeTokenWrapper
        );
    }

    function _msgSender() internal view virtual returns (address sender) {
        if (IERC2771Context(address(this)).isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return msg.sender;
        }
    }
}