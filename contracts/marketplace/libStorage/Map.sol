// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Multicall.sol";

interface IMap {
    function setExtension(bytes4 _selector, address _extension) external;
    function getExtension(bytes4 _selector) external view returns (address);
}

contract Map is Multicall {
    // Simple permission control for proof of concept.
    address public deployer;

    mapping(bytes4 => address) private extension;

    constructor() {
        deployer = msg.sender;
    }

    function setExtension(bytes4 _selector, address _extension) external {
        require(msg.sender == deployer, "Only deployer");
        require(
            extension[_selector] == address(0),
            "Function already registered"
        );
        extension[_selector] = _extension;
    }

    function getExtension(bytes4 _selector) external view returns (address) {
        return extension[_selector];
    }
}