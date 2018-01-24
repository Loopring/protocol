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
contract NameRegistry {
    uint64 nextId = 1;

    mapping (uint64  => AddressSet) public addressSetMap;
    mapping (address => NameInfo)   public nameInfoMap;
    mapping (bytes12 => address)    public nameMap;
    mapping (address => uint64)     public feeRecipientMap;

    struct NameInfo {
        bytes12 name;
        uint64  rootId;
    }

    struct AddressSet {
        address signer;
        address feeRecipient;
        uint64  nextId;
    }

    event NameRegistered(
        string            name,
        address   indexed addr
    );

    event AddressSetRegistered(
        bytes12           name,
        address   indexed owner,
        uint64    indexed addressSetId,
        address           singer,
        address           feeRecipient
    );

    function registerName(string name) external {
        require(isNameValid(name));

        bytes12 nameBytes = stringToBytes12(name);

        require(nameMap[nameBytes] == 0x0);
        require(nameInfoMap[msg.sender].name.length == 0);

        nameMap[nameBytes] = msg.sender;
        nameInfoMap[msg.sender] = NameInfo(nameBytes, 0);

        NameRegistered(name, msg.sender);
    }

    function addAddressSet(address feeRecipient) external {
        addAddressSet(0x0, feeRecipient);
    }

    function addAddressSet(address singer, address feeRecipient) public {
        require(nameInfoMap[msg.sender].name.length > 0);
        require(feeRecipient != 0x0);

        uint64 addrSetId = nextId++;
        AddressSet memory addrSet = AddressSet(singer, feeRecipient, 0);

        var _nameInfo = nameInfoMap[msg.sender];
        if (_nameInfo.rootId == 0) {
            _nameInfo.rootId = addrSetId;
        } else {
            var _addrSet = addressSetMap[_nameInfo.rootId];
            while (_addrSet.nextId != 0) {
                _addrSet = addressSetMap[_addrSet.nextId];
            }
            _addrSet.nextId == addrSetId;
        }

        addressSetMap[addrSetId] = addrSet;

        AddressSetRegistered(
            _nameInfo.name,
            msg.sender,
            addrSetId,
            singer,
            feeRecipient
        );
    }

    function getAddressesById(uint64 addrSetId) external view returns (address[2]) {
        var _addressSet = addressSetMap[addrSetId];

        return [_addressSet.signer, _addressSet.feeRecipient];
    }

    function isNameValid(string name) internal pure returns (bool) {
        bytes memory tempBs = bytes(name);
        return tempBs.length >= 6 && tempBs.length <= 12;
    }

    function stringToBytes12(string str) internal pure returns (bytes12 result) {
        bytes memory temp = bytes(str);
        if (temp.length == 0) {
            result = 0x0;
        }

        assembly {
            result := mload(add(str, 12))
        }
    }

}
