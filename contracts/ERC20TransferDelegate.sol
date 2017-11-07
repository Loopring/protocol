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

import "zeppelin-solidity/contracts/math/Math.sol";
import "zeppelin-solidity/contracts/token/ERC20.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";


/// @title ERC20TransferDelegate - Acts as a middle man to transfer ERC20 tokens
/// on behalf of different versions of Loopring protocol to avoid ERC20
/// re-authorization.
/// @author Daniel Wang - <daniel@loopring.org>.
contract ERC20TransferDelegate is Ownable {
    using Math for uint;

    ////////////////////////////////////////////////////////////////////////////
    /// Variables                                                            ///
    ////////////////////////////////////////////////////////////////////////////

    mapping (address => bool) public authorizedAddresses;


    ////////////////////////////////////////////////////////////////////////////
    /// Modifiers                                                            ///
    ////////////////////////////////////////////////////////////////////////////

    modifier onlyAuthorized() {
        if (authorizedAddresses[msg.sender] == false) {
            revert();
        }
        _;
    }


    ////////////////////////////////////////////////////////////////////////////
    /// Events                                                               ///
    ////////////////////////////////////////////////////////////////////////////

    event AddressAuthorized(address indexed addr);

    event AddressUnauthorized(address indexed addr);


    ////////////////////////////////////////////////////////////////////////////
    /// Public Functions                                                     ///
    ////////////////////////////////////////////////////////////////////////////

    /// @dev Add a Loopring protocol address.
    /// @param addr A loopring protocol address.
    function authorizeAddress(address addr)
        onlyOwner
        public
    {
        authorizedAddresses[addr] = true;
        AddressAuthorized(addr);
    }

    /// @dev Remove a Loopring protocol address.
    /// @param addr A loopring protocol address.
    function unauthorizeAddress(address addr)
        onlyOwner
        public
    {
        delete authorizedAddresses[addr];
        AddressUnauthorized(addr);
    }

    /// @dev Invoke ERC20 transferFrom method.
    /// @param token Address of token to transfer.
    /// @param from Address to transfer token from.
    /// @param to Address to transfer token to.
    /// @param value Amount of token to transfer.
    function transferToken(
        address token,
        address from,
        address to,
        uint value)
        onlyAuthorized
        public
    {
        if (from != to) {
            require(
                ERC20(token).transferFrom(from, to, value)
            );
        }
    }

    function transferTokenBatch(bytes32[] batch)
        onlyAuthorized
        public
    {
        uint len = batch.length;
        for (uint i = 0; i < len; i += 4) {
            address token = address(batch[i]);
            address from = address(batch[i + 1]);
            address to = address(batch[i + 2]);
            uint value = uint(batch[i + 3]);

            if (from != to) {
                require(
                    ERC20(token).transferFrom(from, to, value)
                );
            }
        }
    }
}
