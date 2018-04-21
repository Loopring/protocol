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
pragma solidity 0.4.23;
pragma experimental "v0.5.0";
pragma experimental "ABIEncoderV2";


/// @title ERC20 Token Mint
/// @dev This contract deploys ERC20 token contract and registered the contract
///      so the token can be traded with Loopring Protocol.
/// @author Kongliang Zhong - <kongliang@loopring.org>,
/// @author Daniel Wang - <daniel@loopring.org>.
contract TradeBroker {
    event BrokerRegistered(
        address owner,
        address broker,
        address tracker
    );

    event BrokerUnregistered(
        address owner,
        address broker
    );

    function getBroker(
        address owner,
        address broker
        )
        external
        view
        returns(
            bool authenticated,
            address tracker
        );

    function getBrokers(
        uint start,
        uint count
        )
        public
        view
        returns (
            address[] brokers,
            address[] trackers
        );

    function registerBroker(
        address broker,
        address tracker  // 0x0 allowed
        )
        external;
    
    function unregisterBroker(
        address broker
        )
        external;
}
