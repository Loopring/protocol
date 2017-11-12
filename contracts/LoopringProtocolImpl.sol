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

import "./lib/ERC20.sol";
import "./lib/MathUint.sol";
import "./LoopringProtocol.sol";
import "./RinghashRegistry.sol";
import "./TokenRegistry.sol";
import "./TokenTransferDelegate.sol";
import "./CommonLib.sol";
import "./Miner.sol";
import "./Order.sol";
import "./State.sol";


/// @title Loopring Token Exchange Protocol Implementation Contract v1
/// @author Daniel Wang - <daniel@loopring.org>,
/// @author Kongliang Zhong - <kongliang@loopring.org>
contract LoopringProtocolImpl is LoopringProtocol {
    using MathUint for uint;
    using Miner for uint[5];
    using Order for uint[16];
    using State for uint[10];

    uint64 private constant ENTERED_MASK = 1 << 63;

    uint private constant STATE_ORDER_HASH      = 0;
    uint private constant STATE_FILL_AMOUNT_S   = 5;
    uint private constant STATE_LRC_REWARD      = 6;
    uint private constant STATE_SPLIT_S         = 7;
    uint private constant STATE_SPLIT_B         = 8;
    uint private constant STATE_CURRENT_LRC_FEE = 4;


    address private  _lrcTokenAddress          = address(0);
    address private  _tokenRegistryAddress     = address(0);
    address private  _ringhashRegistryAddress  = address(0);
    address private  _delegateAddress          = address(0);
    uint    private  _maxRingSize              = 0;
    uint64  private  _ringIndex                = 0;
    uint    private  _rateRatioCVSThreshold    = 0;

    State.History private _history = State.History();
    Order.Cutoff private _cutoff = Order.Cutoff();

    function LoopringProtocolImpl(
        address lrcTokenAddress,
        address tokenRegistryAddress,
        address ringhashRegistryAddress,
        address delegateAddress,
        uint    maxRingSize,
        uint    rateRatioCVSThreshold
        )
        public
    {
        require(address(0) != lrcTokenAddress);
        require(address(0) != tokenRegistryAddress);
        require(address(0) != ringhashRegistryAddress);
        require(address(0) != delegateAddress);

        require(maxRingSize > 1);
        require(rateRatioCVSThreshold > 0);

        _lrcTokenAddress = lrcTokenAddress;
        _tokenRegistryAddress = tokenRegistryAddress;
        _ringhashRegistryAddress = ringhashRegistryAddress;
        _delegateAddress = delegateAddress;
        _maxRingSize = maxRingSize;
        _rateRatioCVSThreshold = rateRatioCVSThreshold;
    }

    function () payable public { revert(); }

    function submitRing(
        uint[5]    miner,
        uint[16][] orders
        )
        public
    {
        uint size = orders.length;
        uint64 ringIndex = _ringIndex;

        require(size > 1);
        require(size <= _maxRingSize);
        require(ringIndex & ENTERED_MASK != ENTERED_MASK);

        ringIndex |= ENTERED_MASK;
        _ringIndex = ringIndex;

        TokenTransferDelegate delegate = TokenTransferDelegate(_delegateAddress);
        address lrcTokenAddress = _lrcTokenAddress;
        address feeRecipient = miner.getFeeRecipient();

        uint[10][] memory states = _prepareRing(delegate, size, orders);

        _loop(size, orders, states);

        _splitFees(
            delegate,
            lrcTokenAddress,
            feeRecipient,
            size,
            orders,
            states
        );

        uint[6][] memory batch = _prepareTransfer(size, orders, states);

        var (ringhash, ringReserved) = _finalize(
            delegate,
            lrcTokenAddress,
            feeRecipient,
            miner,
            size,
            orders,
            batch
        );

        _fireEvents(
            ringhash,
            ringReserved,
            ringIndex ^ ENTERED_MASK,
            address(miner[0]),
            feeRecipient,
            size,
            states
        );

        _ringIndex = ringIndex ^ ENTERED_MASK + 1;
    }

    function _prepareRing(
        TokenTransferDelegate delegate,
        uint size,
        uint[16][] memory orders
    )
        private
        view
        returns (uint[10][] memory states)
    {
        TokenRegistry tokenRegistry = TokenRegistry(_tokenRegistryAddress);
        states = new uint[10][](size);

        // Checks that need to access whole list of orders
        Order.verifyRateRatio(_rateRatioCVSThreshold, size, orders);
        Order.verifyDuplicateTokenS(size, orders);
        Order.verifyTokensRegistered(tokenRegistry, size, orders);

        for (uint i = 0; i < size; i++) {
            orders[i].verifyInput(_cutoff);
            states[i].setupOrderHash(orders[i]);
            states[i].setupCurrentAmounts(_history, orders[i]);
            states[i].setupFillAmountS(delegate, orders[i]);
        }
    }

    function _loop(uint size, uint[16][] orders, uint[10][] states)
        private
        pure
    {
        uint rerunTo;
        uint i;

        for (i = 0; i < size; i++) {
            uint newRerunTo = states[i].exchangeWith(
                orders[i], states[(i + 1) % size], i
            );
            if (newRerunTo != 0) {
                rerunTo = newRerunTo;
            }
        }
        for (i = 0; i < rerunTo; i++) {
            states[i].exchangeWith(orders[i], states[(i + 1) % size], i);
        }
    }

    function _splitFees(
        TokenTransferDelegate delegate,
        address lrcTokenAddress,
        address feeRecipient,
        uint size,
        uint[16][] memory orders,
        uint[10][] memory states
    )
        private
        view
    {
        uint minerAvailableLrc = CommonLib.getSpendable(
            delegate,
            feeRecipient,
            lrcTokenAddress
        );

        for (uint i = 0; i < size; i++) {
            states[i].setupSpendableLrc(delegate, lrcTokenAddress, orders[i]);
            states[i].splitWith(orders[i], states[(i + 1) % size], minerAvailableLrc);
        }
    }

    function _prepareTransfer(
        uint size,
        uint[16][] memory orders,
        uint[10][] memory states
    )
        private
        returns (uint[6][] memory batch)
    {
        batch = new uint[6][](size);
        for (uint i = 0; i < size; i++) {
            states[i].updateBalance(
                _history,
                orders[i],
                states[(i + size - 1) % size]
            );
            batch[i] = states[i].createTransferItem(
                orders[i],
                states[(i + size - 1) % size]
            );
        }
    }

    function _finalize(
        TokenTransferDelegate delegate,
        address lrcTokenAddress,
        address feeRecipient,
        uint[5] memory miner,
        uint size,
        uint[16][] memory orders,
        uint[6][] memory batch
        )
        private
        returns (bytes32, bool)
    {

        RinghashRegistry ringhashRegistry = RinghashRegistry(_ringhashRegistryAddress);
        var (ringhash, ringReserved) = miner.verifyRinghash(
            ringhashRegistry,
            size,
            orders
        );

        delegate.batchTransferToken(
            lrcTokenAddress,
            feeRecipient,
            batch
        );

        return (ringhash, ringReserved);
    }

    function _fireEvents(
        bytes32 ringhash,
        bool ringReserved,
        uint64 ringIndex,
        address minerAddress,
        address feeRecipient,
        uint size,
        uint[10][] memory states
        )
        private
    {
        for (uint i = 0; i < size; i++) {
            OrderFilled(
                ringIndex,
                block.timestamp,
                block.number,
                ringhash,
                bytes32(states[(i + size - 1) % size][STATE_ORDER_HASH]),
                bytes32(states[i][STATE_ORDER_HASH]),
                bytes32(states[(i + 1) % size][STATE_ORDER_HASH]),
                states[i][STATE_FILL_AMOUNT_S] + states[i][STATE_SPLIT_S],
                states[(i + 1) % size][STATE_FILL_AMOUNT_S] - states[i][STATE_SPLIT_B],
                states[i][STATE_LRC_REWARD],
                states[i][STATE_CURRENT_LRC_FEE]
            );
        }

        RingMined(
            ringIndex,
            block.timestamp,
            block.number,
            ringhash,
            minerAddress,
            feeRecipient,
            ringReserved
        );
    }

    function cancelOrder(
        address[3] addresses,
        uint[7]    orderValues,
        bool       buyNoMoreThanAmountB,
        uint8      marginSplitPercentage,
        uint8      v,
        bytes32    r,
        bytes32    s
        )
        public
    {
        uint cancelAmount = orderValues[6];
        require(cancelAmount != 0); // "amount to cancel is zero");
        require(msg.sender == addresses[0]);

        uint orderHash = Order.calculateAndVerify(
            addresses,
            orderValues,
            buyNoMoreThanAmountB,
            marginSplitPercentage,
            v,
            r,
            s
        );

        State.increaseBalanceByOrderHash(
            _history,
            orderHash,
            cancelAmount
        );

        OrderCancelled(
            block.timestamp,
            block.number,
            bytes32(orderHash),
            cancelAmount
        );
    }

    function setCutoff(uint timestamp)
        public
    {
        if (timestamp == 0) {
            timestamp = block.timestamp;
        }

        Order.setCutoffTimestamp(_cutoff, msg.sender, timestamp);

        CutoffTimestampChanged(
            block.timestamp,
            block.number,
            msg.sender,
            timestamp
        );
    }

    function cancelledOrFilled(bytes32 orderHash)
        public
        view
        returns (uint)
    {
        return _history.balances[uint(orderHash)];
    }

    function cutoffs(address sender)
        public
        view
        returns (uint)
    {
        return _cutoff.timestamps[sender];
    }
}
