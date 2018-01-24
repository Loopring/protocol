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
    mapping (address => NameInfo)   public ownerMap;
    mapping (bytes12 => address)    public nameMap;
    mapping (address => uint64)     public feeRecipientMap;

    struct NameInfo {
        bytes12 name;
        uint64  rootId;
    }

    struct AddressSet {
        address feeRecipient;
        address signer;
        uint64  nextId;
    }

    event NameRegistered (
        string            name,
        address   indexed addr
    );

    event AddressSetRegistered (
        bytes12           name,
        address   indexed owner,
        uint64    indexed addressSetId,
        address           singer,
        address           feeRecipient
    );

    function registerName(string name)
        external
    {
        require(isNameValid(name));

        bytes12 nameBytes = stringToBytes12(name);

        require(nameMap[nameBytes] == 0x0);
        require(ownerMap[msg.sender].name.length == 0);

        nameMap[nameBytes] = msg.sender;
        ownerMap[msg.sender] = NameInfo(nameBytes, 0);

        NameRegistered(name, msg.sender);
    }

    function addAddressSet(address feeRecipient)
        external
    {
        addAddressSet(feeRecipient, feeRecipient);
    }

    function addAddressSet(
        address feeRecipient,
        address singer
        )
        public
    {
        require(feeRecipient != 0x0);
        require(singer != 0x0);
        require(ownerMap[msg.sender].name.length > 0);

        uint64 addrSetId = nextId++;
        AddressSet memory addrSet = AddressSet(feeRecipient, singer, 0);

        NameInfo storage nameInfo = ownerMap[msg.sender];

        if (nameInfo.rootId == 0) {
            nameInfo.rootId = addrSetId;
        } else {
            var _addrSet = addressSetMap[nameInfo.rootId];
            while (_addrSet.nextId != 0) {
                _addrSet = addressSetMap[_addrSet.nextId];
            }
            _addrSet.nextId == addrSetId;
        }

        addressSetMap[addrSetId] = addrSet;

        AddressSetRegistered(
            nameInfo.name,
            msg.sender,
            addrSetId,
            singer,
            feeRecipient
        );
    }

    function getParticipantById(uint64 id)
        external
        view
        returns (address feeRecipient, address signer)
    {
        AddressSet storage addressSet = addressSetMap[id];

        feeRecipient = addressSet.feeRecipient;
        signer = addressSet.signer;
    }

    function isNameValid(string name)
        internal
        pure
        returns (bool)
    {
        bytes memory temp = bytes(name);
        return temp.length >= 6 && temp.length <= 12;
    }

    function stringToBytes12(string str)
        internal
        pure
        returns (bytes12 result)
    {
        assembly {
            result := mload(add(str, 12))
        }
    }

}
