// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IMap} from "./Map.sol";
import {MarketplaceAlt, MarketplaceStorage} from "./MarketplaceAlt.sol";

library InitStorage {
    /// @dev The location of the storage of the entrypoint contract's data.
    bytes32 constant INIT_STORAGE_POSITION = keccak256("init.storage");

    /// @dev Layout of the entrypoint contract's storage.
    struct Data {
        bool initialized;
    }

    /// @dev Returns the entrypoint contract's data at the relevant storage location.
    function initStorage() internal pure returns (Data storage initData) {
        bytes32 position = INIT_STORAGE_POSITION;
        assembly {
            initData.slot := position
        }
    }
}

contract MarketplaceEntrypoint is MarketplaceAlt {
    address public immutable functionMap;

    constructor(address _functionMap, address _nativeTokenWrapper) MarketplaceAlt(_nativeTokenWrapper) {
        functionMap = _functionMap;
    }

    /// @dev Initializes the proxy smart contract that points to this entrypoint contract.
    function initialize(
        address _defaultAdmin,
        string memory _contractURI,
        address[] memory _trustedForwarders,
        address _platformFeeRecipient,
        uint256 _platformFeeBps
    ) external {
        InitStorage.Data storage data = InitStorage.initStorage();

        require(!data.initialized, "Already initialized.");
        data.initialized = true;

        // Initialize inherited contracts, most base-like -> most derived.
        __ReentrancyGuard_init();
        __ERC2771Context_init(_trustedForwarders);

        // Initialize this contract's state.
        MarketplaceStorage.Data storage marketplaceData = MarketplaceStorage.marketplaceStorage();
        
        marketplaceData.timeBuffer = 15 minutes;
        marketplaceData.bidBufferBps = 500;

        _setupContractURI(_contractURI);
        _setupPlatformFeeInfo(_platformFeeRecipient, _platformFeeBps);

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(LISTER_ROLE, address(0));
        _setupRole(ASSET_ROLE, address(0));
    }

    fallback() external payable virtual {
        address extension = IMap(functionMap).getExtension(msg.sig);
        require(extension != address(0), "Function does not exist");

        _delegate(extension);
    }

    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(
                gas(),
                implementation,
                0,
                calldatasize(),
                0,
                0
            )

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }
}