// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.0 (metatx/ERC2771Context.sol)

pragma solidity ^0.8.11;

import "./ERC2771ContextStorage.sol";

/**
 * @dev Context variant with ERC2771 support.
 */
abstract contract ERC2771Context {

    function __ERC2771Context_init(address[] memory _trustedForwarder) internal  {
        __ERC2771Context_init_unchained(_trustedForwarder);
    }

    function __ERC2771Context_init_unchained(address[] memory _trustedForwarder) internal  {
        ERC2771ContextStorage.Data storage data = ERC2771ContextStorage.erc2771ContextStorage();

        for (uint256 i = 0; i < _trustedForwarder.length; i++) {
            data.trustedForwarder[_trustedForwarder[i]] = true;
        }
    }

    function isTrustedForwarder(address forwarder) public view virtual returns (bool) {
        ERC2771ContextStorage.Data storage data = ERC2771ContextStorage.erc2771ContextStorage();
        return data.trustedForwarder[forwarder];
    }

    function _msgSender() internal view virtual returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            // The assembly code is more direct than the Solidity version using `abi.decode`.
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            return msg.sender;
        }
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        if (isTrustedForwarder(msg.sender)) {
            return msg.data[:msg.data.length - 20];
        } else {
            return msg.data;
        }
    }

    uint256[49] private __gap;
}
