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
pragma solidity 0.4.21;


/// @title Loopring Token Exchange Protocol Contract Interface
/// @author Daniel Wang - <daniel@loopring.org>
/// @author Kongliang Zhong - <kongliang@loopring.org>
contract LoopringProtocol {
    uint8   public constant MARGIN_SPLIT_PERCENTAGE_BASE = 100;

    /// @dev Event to emit if a ring is successfully mined.
    /// _amountsList is an array of:
    /// [_amountS, _amountB, _lrcReward, _lrcFee, splitS, splitB].
    event RingMined(
        uint            _ringIndex,
        bytes32 indexed _ringHash,
        address         _miner,
        uint[]          _orderInfoList
    );

    event OrderCancelled(
        bytes32 indexed _orderHash,
        uint            _amountCancelled
    );

    event AllOrdersCancelled(
        address indexed _address,
        uint            _cutoff
    );

    event OrdersCancelled(
        address indexed _address,
        address         _token1,
        address         _token2,
        uint            _cutoff
    );

    /// @dev Cancel a order. cancel amount(amountS or amountB) can be specified
    ///      in orderValues.
    /// @param addresses          owner, tokenS, tokenB, wallet, authAddr
    /// @param orderValues        amountS, amountB, validSince (second),
    ///                           validUntil (second), lrcFee, and cancelAmount.
    /// @param buyNoMoreThanAmountB -
    ///                           This indicates when a order should be considered
    ///                           as 'completely filled'.
    /// @param marginSplitPercentage -
    ///                           Percentage of margin split to share with miner.
    /// @param v                  Order ECDSA signature parameter v.
    /// @param r                  Order ECDSA signature parameters r.
    /// @param s                  Order ECDSA signature parameters s.
    function cancelOrder(
        address[5] addresses,
        uint[6]    orderValues,
        bool       buyNoMoreThanAmountB,
        uint8      marginSplitPercentage,
        uint8      v,
        bytes32    r,
        bytes32    s
        )
        external;

    /// @dev   Set a cutoff timestamp to invalidate all orders whose timestamp
    ///        is smaller than or equal to the new value of the address's cutoff
    ///        timestamp, for a specific trading pair.
    /// @param cutoff The cutoff timestamp, will default to `block.timestamp`
    ///        if it is 0.
    function cancelAllOrdersByTradingPair(
        address token1,
        address token2,
        uint cutoff
        )
        external;

    /// @dev   Set a cutoff timestamp to invalidate all orders whose timestamp
    ///        is smaller than or equal to the new value of the address's cutoff
    ///        timestamp.
    /// @param cutoff The cutoff timestamp, will default to `block.timestamp`
    ///        if it is 0.
    function cancelAllOrders(
        uint cutoff
        )
        external;

    /// @dev Submit a order-ring for validation and settlement.
    /// @param addressList  List of each order's owner, tokenS, wallet, authAddr.
    ///                     Note that next order's `tokenS` equals this order's
    ///                     `tokenB`.
    /// @param uintArgsList List of uint-type arguments in this order:
    ///                     amountS, amountB, validSince (second),
    ///                     validUntil (second), lrcFee, and rateAmountS.
    /// @param uint8ArgsList -
    ///                     List of unit8-type arguments, in this order:
    ///                     marginSplitPercentageList. Bits 0-6 represent the marginSplitPercentage,
    ///                     bits 7 represents the buyNoMoreThanAmountB as Boolean
    ///                     bits 8 represents the feeSelection
    ///                     also indicates when a order should be considered
    /// @param vList        List of v for each order. This list is 1-larger than
    ///                     the previous lists, with the last element being the
    ///                     v value of the ring signature.
    /// @param rList        List of r for each order. This list is 1-larger than
    ///                     the previous lists, with the last element being the
    ///                     r value of the ring signature.
    /// @param sList        List of s for each order. This list is 1-larger than
    ///                     the previous lists, with the last element being the
    ///                     s value of the ring signature.
    /// @param miner        Miner address.

    function submitRing(
        address[4][]    addressList,
        uint[6][]       uintArgsList,
        uint16[]        uint8ArgsList,
        uint8[]         vList,
        bytes32[]       rList,
        bytes32[]       sList,
        address         miner
        )
        public;
}
