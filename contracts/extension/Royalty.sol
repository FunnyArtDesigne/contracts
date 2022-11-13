// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@thirdweb-dev/contracts/extension/Royalty.sol";

contract MyContract is Royalty {
    /**
     *  We store the contract deployer's address only for the purposes of the example
     *  in the code comment below.
     *
     *  Doing this is not necessary to use the `Royalty` extension.
     */
    address public deployer;

    constructor() {
        deployer = msg.sender;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        returns (bool)
    {
        return type(IERC2981).interfaceId == interfaceId;
    }

    /**
     *  This function returns who is authorized to set royalty info for your NFT contract.
     *
     *  As an EXAMPLE, we'll only allow the contract deployer to set the royalty info.
     *
     *  You MUST complete the body of this function to use the `Royalty` extension.
     */
    function _canSetRoyaltyInfo()
        internal
        view
        virtual
        override
        returns (bool)
    {
        return msg.sender == deployer;
    }
}
