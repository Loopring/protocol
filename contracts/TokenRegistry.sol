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

import "./lib/Claimable.sol";


/// @title Token Register Contract
/// @dev This contract maintains a list of tokens the Protocol supports.
/// @author Kongliang Zhong - <kongliang@loopring.org>,
/// @author Daniel Wang - <daniel@loopring.org>.
contract TokenRegistry is Claimable {

    address lastAddress;
    uint    numOfTokens;

    mapping (address => TokenInfo) addressMap;
    mapping (string => address) symbolMap;


    ////////////////////////////////////////////////////////////////////////////
    /// Structs                                                              ///
    ////////////////////////////////////////////////////////////////////////////

    struct TokenInfo {
        bool    registered;
        address previous;
        address next;
        string  symbol;
    }

    ////////////////////////////////////////////////////////////////////////////
    /// Events                                                               ///
    ////////////////////////////////////////////////////////////////////////////

    event TokenRegistered(address indexed addr, string symbol, uint numOfTokens);

    event TokenUnregistered(address indexed addr, string symbol, uint numOfTokens);


    ////////////////////////////////////////////////////////////////////////////
    /// Public Functions                                                     ///
    ////////////////////////////////////////////////////////////////////////////

    function registerToken(
        address _address,
        string _symbol
        )
        external
        onlyOwner
    {
        require(_address != 0x0);
        require(!addressMap[_address].registered);
        require(bytes(_symbol).length > 0);
        require(symbolMap[_symbol] == 0x0);

        address _lastAddress = lastAddress;
        if (_lastAddress != 0x0) {
            addressMap[_lastAddress].next = _address;
        }
        addressMap[_address] = TokenInfo(true, _lastAddress, 0x0, _symbol);
        symbolMap[_symbol] = _address;
        lastAddress = _address;

        numOfTokens++;
        TokenRegistered(_address, _symbol, numOfTokens);
    }

    function unregisterToken(
        address _address,
        string _symbol
        )
        external
        onlyOwner
    {
        require(_address != 0x0);
        require(addressMap[_address].registered);
        require(bytes(_symbol).length > 0);
        require(symbolMap[_symbol] == _address);

        var tokenInfo = addressMap[_address];
        address nextAddr = addressMap[_address].next;
        address prevAddr = addressMap[_address].previous;
        if (nextAddr != 0x0) {
            addressMap[nextAddr].previous = prevAddr;
        }
        if (prevAddr != 0x0) {
            addressMap[nextAddr].next = nextAddr;
        }
        if (_address == lastAddress) {
            lastAddress = prevAddr;
        }

        addressMap[_address].registered = false;
        symbolMap[tokenInfo.symbol] = 0x0;

        numOfTokens--;
        TokenRegistered(_address, _symbol, numOfTokens);
    }

    function getRegisteredTokens(
        uint skip,
        uint max
        )
        external
        view
        returns (
        address[] memory addresses)
    {
        addresses = new address[](max);
        address addr = lastAddress;
        uint i = 0;
        TokenInfo memory info;
        while(addr != 0x0 && i < skip) {
             info = addressMap[addr];
             if (!info.registered) {
                break;
             }
             addr = info.previous;
             i++;
        }

        i = 0;
        while(addr != 0x0 && i < max) {
             info = addressMap[addr];
             if (!info.registered) {
                break;
             }
             addresses[i] = addr;
             addr = info.previous;
        }
    }

    function isTokenRegisteredByAddress(address addr)
        public
        view
        returns (bool)
    {
        return addressMap[addr].registered;
    }

    function isTokenRegisteredBySymbol(string symbol)
        public
        view
        returns (bool)
    {
        return addressMap[symbolMap[symbol]].registered;
    }

    function areAllTokensRegistered(address[] addresses)
        external
        view
        returns (bool)
    {
        for (uint i = 0; i < addresses.length; i++) {
            if (!addressMap[addresses[i]].registered) {
                return false;
            }
        }
        return true;
    }

    function getAddressBySymbol(string symbol)
        external
        view
        returns (address)
    {
        require(isTokenRegisteredBySymbol(symbol));
        return symbolMap[symbol];
    }

    function getSymbolByAddress(address addr)
        external
        view
        returns (string)
    {
        require(isTokenRegisteredByAddress(addr));
        return addressMap[addr].symbol;
    }
}
