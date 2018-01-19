/*

  Copyright 2017 Loopring Project Ltd (Loopring Foundation).

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/
pragma solidity 0.4.18;

/// @title Ethereum Address Register Contract
/// @dev This contract maintains a name service for addresses and miner.
/// @author Kongliang Zhong - <kongliang@loopring.org>,
contract AddressRegistry {

    mapping (bytes12 => address) public namedAddressMap;
    mapping (address => string) public addressNameMap;

    mapping (bytes12 => MinerInfo) public minerMap;
    mapping (bytes12 => bool) public isMinerNameRegistered;
    mapping (address => string) public minerNameMap;

    struct MinerInfo {
        address signer;
        address feeRecipient;
    }

    event NameRegistered(string name, address addr);
    event MinerRegistered(string name, address signer, address feeRecipient);

    function registerAddress(string name) external {
        require(isValidName(name));
        require(namedAddressMap[stringToBytes12(name)] == 0x0);

        namedAddressMap[stringToBytes12(name)] = msg.sender;
        addressNameMap[msg.sender] = name;
        NameRegistered(name, msg.sender);
    }

    function registerMiner(string name, address feeRecipient) external {
        require(isValidName(name));
        require(feeRecipient != 0x0);
        require(!isMinerNameRegistered[stringToBytes12(name)]);

        MinerInfo memory minerInfo = MinerInfo(msg.sender, feeRecipient);
        minerMap[stringToBytes12(name)] = minerInfo;
        isMinerNameRegistered[stringToBytes12(name)] = true;
        minerNameMap[msg.sender] = name;

        MinerRegistered(name, msg.sender, feeRecipient);
    }

    function isValidName(string name) internal pure returns (bool) {
        bytes memory tempBs = bytes(name);

        // name's length should be greater than 0 and less than 13.
        return tempBs.length > 0 && tempBs.length < 13;
    }

    function stringToBytes12(string source) internal pure returns (bytes12 result) {
        bytes memory tempBs = bytes(source);
        if (tempBs.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 12))
        }
    }

}
