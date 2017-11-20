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

import "./lib/AddressMap.sol";
import "./lib/Ownable.sol";


/// @title Token Register Contract
/// @dev This contract maintains a list of tokens the Protocol supports.
/// @author Kongliang Zhong - <kongliang@loopring.org>,
/// @author Daniel Wang - <daniel@loopring.org>.
contract TokenRegistry is Ownable {
    AddressMapping.AddressMap tokenMap;

    function registerToken(address _token, string _symbol)
        external
        onlyOwner
    {
        require(_token != address(0));
        require(!isTokenRegistered(_token));
        AddressMapping.insert(tokenMap, _token, keccak256(_symbol));
    }

    function unregisterToken(address _token)
        external
        onlyOwner
    {
        require(_token != address(0));
        require(AddressMapping.contains(tokenMap, _token));
        AddressMapping.remove(tokenMap, _token);
    }

    function isTokenRegistered(address _token)
        public
        view
        returns (bool)
    {
        return AddressMapping.contains(tokenMap, _token);
    }

    function areAllTokensRegistered(address[] tokenList)
        external
        view
        returns (bool)
    {
        for (uint i = 0; i < tokenList.length; i++) {
            if (!AddressMapping.contains(tokenMap, tokenList[i])) {
                return false;
            }
        }
        return true;
    }

    function getAddressBySymbol(string symbol)
        external
        constant
        returns (address)
    {
        for (uint i = AddressMapping.iterateStart(tokenMap);
            AddressMapping.iterateValid(tokenMap, i);
            i = AddressMapping.iterateNext(tokenMap, i)
        ) {
            var (key, value) = AddressMapping.iterateGet(tokenMap, i);
            if (keccak256(symbol) == value) {
                return key;
            }
        }

    }
}
