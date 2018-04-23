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

import "./lib/AddressUtil.sol";
import "./lib/ERC20.sol";
import "./lib/MathUint.sol";
import "./lib/MultihashUtil.sol";
import "./BrokerRegistry.sol";
import "./BrokerTracker.sol";
import "./LoopringProtocol.sol";
import "./TokenRegistry.sol";
import "./TokenTransferDelegate.sol";


/// @title An Implementation of LoopringProtocol.
/// @author Daniel Wang - <daniel@loopring.org>,
/// @author Kongliang Zhong - <kongliang@loopring.org>
///
/// Recognized contributing developers from the community:
///     https://github.com/Brechtpd
///     https://github.com/rainydio
///     https://github.com/BenjaminPrice
///     https://github.com/jonasshen
///     https://github.com/Hephyrius
contract LoopringProtocolImpl is LoopringProtocol {
    using AddressUtil   for address;
    using MathUint      for uint;

    address public  lrcTokenAddress             = 0x0;
    address public  tokenRegistryAddress        = 0x0;
    address public  delegateAddress             = 0x0;
    address public  brokerRegistryAddress       = 0x0;

    uint64  public  ringIndex                   = 0;

    // Exchange rate (rate) is the amount to sell or sold divided by the amount
    // to buy or bought.
    //
    // Rate ratio is the ratio between executed rate and an order's original
    // rate.
    //
    // To require all orders' rate ratios to have coefficient ofvariation (CV)
    // smaller than 2.5%, for an example , rateRatioCVSThreshold should be:
    //     `(0.025 * RATE_RATIO_SCALE)^2` or 62500.
    uint    public rateRatioCVSThreshold        = 0;

    uint    public constant MAX_RING_SIZE       = 8;

    uint    public constant RATE_RATIO_SCALE    = 10000;

    struct Order {
        address owner;
        address signer;
        address tokenS;
        address tokenB;
        address wallet;
        address authAddr;
        uint    amountS;
        uint    amountB;
        uint    validSince;
        uint    validUntil;
        uint    lrcFee;
        uint8   option;
        bool    capByAmountB;
        bool    marginSplitAsFee;
        bytes32 orderHash;
        address trackerAddr;
        uint    rateS;
        uint    rateB;
        uint    fillAmountS;
        uint    lrcReward;
        uint    lrcFeeState;
        uint    splitS;
        uint    splitB;
    }

    /// @dev A struct to capture parameters passed to submitRing method and
    ///      various of other variables used across the submitRing core logics.
    struct Context {
        address[5][]  addressesList;
        uint[6][]     valuesList;
        uint8[]       optionList;
        bytes[]       sigList;
        address       miner;
        uint8         feeSelections;
        uint64        ringIndex;
        uint          ringSize;         // computed
        TokenTransferDelegate delegate;
        BrokerRegistry        brokerRegistry;
        Order[]  orders;
        bytes32       ringHash;         // computed
    }

    constructor(
        address _lrcTokenAddress,
        address _tokenRegistryAddress,
        address _delegateAddress,
        address _brokerRegistryAddress,
        uint    _rateRatioCVSThreshold
        )
        public
    {
        require(_lrcTokenAddress.isContract());
        require(_tokenRegistryAddress.isContract());
        require(_delegateAddress.isContract());
        require(_brokerRegistryAddress.isContract());

        require(_rateRatioCVSThreshold > 0);

        lrcTokenAddress = _lrcTokenAddress;
        tokenRegistryAddress = _tokenRegistryAddress;
        delegateAddress = _delegateAddress;
        brokerRegistryAddress = _brokerRegistryAddress;
        rateRatioCVSThreshold = _rateRatioCVSThreshold;
    }

    /// @dev Disable default function.
    function ()
        payable
        external
    {
        revert();
    }

    function cancelOrder(
        address[6] addresses,
        uint[6]    orderValues,
        uint8      option,
        bytes      sig
        )
        external
    {
        uint cancelAmount = orderValues[5];

        require(cancelAmount > 0, "invalid cancelAmount");
        Order memory order = Order(
            addresses[0],
            addresses[1],
            addresses[2],
            addresses[3],
            addresses[4],
            addresses[5],
            orderValues[0],
            orderValues[1],
            orderValues[2],
            orderValues[3],
            orderValues[4],
            option,
            option & OPTION_MASK_CAP_BY_AMOUNTB > 0 ? true : false,
            false,
            0x0,
            0x0,
            0,
            0,
            0,
            0,
            0,
            0,
            0
        );
        require(
            msg.sender == order.signer,
            "cancelOrder not submitted by signer"
        );

        bytes32 orderHash = calculateOrderHash(order);

        MultihashUtil.verifySignature(
            order.signer,
            orderHash,
            sig
        );

        if (order.signer != order.owner) {
            BrokerRegistry brokerRegistry = BrokerRegistry(brokerRegistryAddress);
            bool registered;
            address tracker;
            (registered, tracker) = brokerRegistry.getBroker(
                order.owner,
                order.signer
            );
            require(registered, "invalid broker");
        }

        TokenTransferDelegate delegate = TokenTransferDelegate(delegateAddress);
        delegate.addCancelled(orderHash, cancelAmount);
        delegate.addCancelledOrFilled(orderHash, cancelAmount);

        emit OrderCancelled(orderHash, cancelAmount);
    }

    function cancelAllOrdersByTradingPair(
        address token1,
        address token2,
        uint    cutoff
        )
        external
    {
        uint t = (cutoff == 0 || cutoff >= block.timestamp) ? block.timestamp : cutoff;

        bytes20 tokenPair = bytes20(token1) ^ bytes20(token2);
        TokenTransferDelegate delegate = TokenTransferDelegate(delegateAddress);

        require(
            delegate.tradingPairCutoffs(msg.sender, tokenPair) < t,
            "cutoff too small"
        );

        delegate.setTradingPairCutoffs(tokenPair, t);
        emit OrdersCancelled(
            msg.sender,
            token1,
            token2,
            t
        );
    }

    function cancelAllOrders(
        uint cutoff
        )
        external
    {
        uint t = (cutoff == 0 || cutoff >= block.timestamp) ? block.timestamp : cutoff;
        TokenTransferDelegate delegate = TokenTransferDelegate(delegateAddress);

        require(
            delegate.cutoffs(msg.sender) < t,
            "cutoff too small"
        );

        delegate.setCutoffs(t);
        emit AllOrdersCancelled(msg.sender, t);
    }

    function submitRing(
        address[5][]  addressesList,
        uint[6][]     valuesList,
        uint8[]       optionList,
        bytes[]       sigList,
        address       miner,
        uint8         feeSelections
        )
        public
    {
        Context memory ctx = Context(
            addressesList,
            valuesList,
            optionList,
            sigList,
            miner,
            feeSelections,
            ringIndex,
            addressesList.length,
            TokenTransferDelegate(delegateAddress),
            BrokerRegistry(brokerRegistryAddress),
            new Order[](addressesList.length),
            0x0 // ringHash
        );

        // Check if the highest bit of ringIndex is '1'.
        require((ringIndex >> 63) == 0, "reentry");

        // Set the highest bit of ringIndex to '1'.
        ringIndex |= (uint64(1) << 63);

        verifyInputDataIntegrity(ctx);

        assembleOrders(ctx);

        validateOrdersCutoffs(ctx);

        verifyRingSignatures(ctx);

        verifyTokensRegistered(ctx);

        verifyRingHasNoSubRing(ctx);

        verifyMinerSuppliedFillRates(ctx);

        scaleRingBasedOnHistoricalRecords(ctx);

        calculateRingFillAmount(ctx);

        calculateRingFees(ctx);

        settleRing(ctx);

        ringIndex = ctx.ringIndex + 1;
    }

    /// @dev verify input data's basic integrity.
    function verifyInputDataIntegrity(
        Context ctx
        )
        private
        pure
    {
        require(ctx.miner != 0x0, "bad miner");

        require(
            ctx.ringSize == ctx.addressesList.length,
            "wrong addressesList size"
        );

        require(
            ctx.ringSize == ctx.valuesList.length,
            "wrong valuesList size"
        );

        require(
            ctx.ringSize == ctx.optionList.length,
            "wrong optionList size"
        );

        // Validate ring-mining related arguments.
        for (uint i = 0; i < ctx.ringSize; i++) {
            require(ctx.valuesList[i][5] > 0, "rateAmountS is 0");
        }

        //Check ring size
        require(
            ctx.ringSize > 1 && ctx.ringSize <= MAX_RING_SIZE,
            "invalid ring size"
        );

        require(
            (ctx.ringSize << 1) == ctx.sigList.length,
            "invalid signature size"
        );
    }

    /// @dev Assemble input data into structs so we can pass them to other functions.
    /// This method also calculates ringHash, therefore it must be called before
    /// calling `verifyRingSignatures`.
    function assembleOrders(
        Context ctx
        )
        private
        view
    {
        for (uint i = 0; i < ctx.ringSize; i++) {

            uint[6] memory uintArgs = ctx.valuesList[i];
            bool marginSplitAsFee = (ctx.feeSelections & (uint8(1) << i)) > 0;

            Order memory order = Order(
                ctx.addressesList[i][0],
                ctx.addressesList[i][1],
                ctx.addressesList[i][2],
                ctx.addressesList[(i + 2) % ctx.ringSize][1],
                ctx.addressesList[i][3],
                ctx.addressesList[i][4],
                uintArgs[0],
                uintArgs[1],
                uintArgs[2],
                uintArgs[3],
                uintArgs[4],
                ctx.optionList[i],
                ctx.optionList[i] & OPTION_MASK_CAP_BY_AMOUNTB > 0 ? true : false,
                marginSplitAsFee,
                0x0,
                0x0,  // brokderTracker
                uintArgs[5],
                uintArgs[1],
                0,   // fillAmountS
                0,   // lrcReward
                0,   // lrcFee
                0,   // splitS
                0.   // splitB
            );

            validateOrder(order);

            order.orderHash = calculateOrderHash(order);

            MultihashUtil.verifySignature(
                order.signer,
                order.orderHash,
                ctx.sigList[i]
           );

            if (order.signer != order.owner) {
                BrokerRegistry brokerRegistry = BrokerRegistry(brokerRegistryAddress);
                bool authenticated;
                (authenticated, order.trackerAddr) = brokerRegistry.getBroker(
                    order.owner,
                    order.signer
                );

                require(authenticated, "invalid broker");
            }

            ctx.orders[i] = order;
            ctx.ringHash ^= order.orderHash;
        }

        ctx.ringHash = keccak256(
            ctx.ringHash,
            ctx.miner,
            ctx.feeSelections
        );
    }

   function validateOrdersCutoffs(
        Context ctx
        )
        private
        view
    {
        address[] memory owners = new address[](ctx.ringSize);
        bytes20[] memory tradingPairs = new bytes20[](ctx.ringSize);
        uint[] memory validSinceTimes = new uint[](ctx.ringSize);

        for (uint i = 0; i < ctx.ringSize; i++) {
            owners[i] = ctx.orders[i].owner;
            tradingPairs[i] = bytes20(ctx.orders[i].tokenS) ^ bytes20(ctx.orders[i].tokenB);
            validSinceTimes[i] = ctx.orders[i].validSince;
        }

        ctx.delegate.checkCutoffsBatch(
            owners,
            tradingPairs,
            validSinceTimes
        );
    }

    /// @dev Verify the ringHash has been signed with each order's auth private
    ///      keys as well as the miner's private key.
    function verifyRingSignatures(
        Context ctx
        )
        private
        pure
    {
        uint j;
        for (uint i = 0; i < ctx.ringSize; i++) {
            j = i + ctx.ringSize;

            MultihashUtil.verifySignature(
                ctx.orders[i].authAddr,
                ctx.ringHash,
                ctx.sigList[i]
            );
        }
    }

    function verifyTokensRegistered(
        Context ctx
        )
        private
        view
    {
        // Extract the token addresses
        address[] memory tokens = new address[](ctx.ringSize);
        for (uint i = 0; i < ctx.ringSize; i++) {
            tokens[i] = ctx.orders[i].tokenS;
        }

        // Test all token addresses at once
        require(
            TokenRegistry(tokenRegistryAddress).areAllTokensRegistered(tokens),
            "token not registered"
        );
    }

    /// @dev Validate a ring.
    function verifyRingHasNoSubRing(
        Context ctx
        )
        private
        pure
    {
        // Check the ring has no sub-ring.
        for (uint i = 0; i < ctx.ringSize - 1; i++) {
            address tokenS = ctx.orders[i].tokenS;
            for (uint j = i + 1; j < ctx.ringSize; j++) {
                require(tokenS != ctx.orders[j].tokenS, "subring found");
            }
        }
    }

    /// @dev Exchange rates calculation are performed by ring-miners as solidity
    /// cannot get power-of-1/n operation, therefore we have to verify
    /// these rates are correct.
    function verifyMinerSuppliedFillRates(
        Context ctx
        )
        private
        view
    {
        uint[] memory rateRatios = new uint[](ctx.ringSize);
        uint _rateRatioScale = RATE_RATIO_SCALE;

        for (uint i = 0; i < ctx.ringSize; i++) {
            uint s1b0 = ctx.orders[i].rateS.mul(ctx.orders[i].amountB);
            uint s0b1 = ctx.orders[i].amountS.mul(ctx.orders[i].rateB);

            require(s1b0 <= s0b1, "invalid discount");

            rateRatios[i] = _rateRatioScale.mul(s1b0) / s0b1;
        }

        uint cvs = MathUint.cvsquare(rateRatios, _rateRatioScale);

        require(cvs <= rateRatioCVSThreshold, "uneven discount");
    }

    /// @dev Scale down all orders based on historical fill or cancellation
    ///      stats but key the order's original exchange rate.
    function scaleRingBasedOnHistoricalRecords(
        Context ctx
        )
        private
        view
    {
        uint ringSize = ctx.ringSize;
        Order[] memory orders = ctx.orders;

        for (uint i = 0; i < ringSize; i++) {
            Order memory order = orders[i];
            uint amount;

            if (order.capByAmountB) {
                amount = order.amountB.tolerantSub(
                    ctx.delegate.cancelledOrFilled(order.orderHash)
                );

                order.amountS = amount.mul(order.amountS) / order.amountB;
                order.lrcFee = amount.mul(order.lrcFee) / order.amountB;

                order.amountB = amount;
            } else {
                amount = order.amountS.tolerantSub(
                    ctx.delegate.cancelledOrFilled(order.orderHash)
                );

                order.amountB = amount.mul(order.amountB) / order.amountS;
                order.lrcFee = amount.mul(order.lrcFee) / order.amountS;

                order.amountS = amount;
            }

            require(order.amountS > 0, "amountS scaled to 0");
            require(order.amountB > 0, "amountB scaled to 0");

            uint availableAmountS = getSpendable(
                ctx.delegate,
                order.tokenS,
                order.owner,
                order.signer,
                order.trackerAddr
            );
            require(availableAmountS > 0, "spendable is 0");

            order.fillAmountS = (
                order.amountS < availableAmountS ?
                order.amountS : availableAmountS
            );
        }
    }

    /// @dev Based on the already verified exchange rate provided by ring-miners,
    /// we can furthur scale down orders based on token balance and allowance,
    /// then find the smallest order of the ring, then calculate each order's
    /// `fillAmountS`.
    function calculateRingFillAmount(
        Context ctx
        )
        private
        pure
    {
        uint smallestIdx = 0;

        for (uint i = 0; i < ctx.ringSize; i++) {
            uint j = (i + 1) % ctx.ringSize;
            smallestIdx = calculateOrderFillAmount(
                ctx.orders[i],
                ctx.orders[j],
                i,
                j,
                smallestIdx
            );
        }

        for (uint i = 0; i < smallestIdx; i++) {
            calculateOrderFillAmount(
                ctx.orders[i],
                ctx.orders[(i + 1) % ctx.ringSize],
                0,               // Not needed
                0,               // Not needed
                0                // Not needed
            );
        }
    }

    /// @dev  Calculate each order's `lrcFee` and `lrcRewrard` and splict how much
    /// of `fillAmountS` shall be paid to matching order or miner as margin
    /// split.
    function calculateRingFees(
        Context ctx
        )
        private
        view
    {
        uint ringSize = ctx.ringSize;
        bool checkedMinerLrcSpendable = false;
        uint minerLrcSpendable = 0;
        uint nextFillAmountS;

        for (uint i = 0; i < ringSize; i++) {
            Order memory order = ctx.orders[i];
            uint lrcReceiable = 0;

            if (order.lrcFeeState == 0) {
                // When an order's LRC fee is 0 or smaller than the specified fee,
                // we help miner automatically select margin-split.
                order.marginSplitAsFee = true;
            } else {
                uint lrcSpendable = getSpendable(
                    ctx.delegate,
                    lrcTokenAddress,
                    order.owner,
                    order.signer,
                    order.trackerAddr
                );

                // If the order is selling LRC, we need to calculate how much LRC
                // is left that can be used as fee.
                if (order.tokenS == _lrcTokenAddress) {
                    lrcSpendable = lrcSpendable.sub(order.fillAmountS);
                }

                // If the order is buyign LRC, it will has more to pay as fee.
                if (order.tokenB == lrcTokenAddress) {
                    nextFillAmountS = ctx.orders[(i + 1) % ringSize].fillAmountS;
                    lrcReceiable = nextFillAmountS;
                }

                uint lrcTotal = lrcSpendable.add(lrcReceiable);

                // If order doesn't have enough LRC, set margin split to 100%.
                if (lrcTotal < order.lrcFeeState) {
                    order.lrcFeeState = lrcTotal;
                }

                if (order.lrcFeeState == 0) {
                    order.marginSplitAsFee = true;
                }
            }

            if (!order.marginSplitAsFee) {
                if (lrcReceiable > 0) {
                    if (lrcReceiable >= order.lrcFeeState) {
                        order.splitB = order.lrcFeeState;
                        order.lrcFeeState = 0;
                    } else {
                        order.splitB = lrcReceiable;
                        order.lrcFeeState = order.lrcFeeState.sub(lrcReceiable);
                    }
                }
            } else {

                // Only check the available miner balance when absolutely needed
                if (!checkedMinerLrcSpendable && minerLrcSpendable < order.lrcFeeState) {
                    checkedMinerLrcSpendable = true;
                    minerLrcSpendable = getSpendable(
                        ctx.delegate,
                        lrcTokenAddress,
                        ctx.miner,
                        0x0,
                        0x0
                    );
                }

                // Only calculate split when miner has enough LRC;
                // otherwise all splits are 0.
                if (minerLrcSpendable >= order.lrcFeeState) {
                    nextFillAmountS = ctx.orders[(i + 1) % ringSize].fillAmountS;
                    uint split;
                    if (order.capByAmountB) {
                        split = (nextFillAmountS.mul(
                            order.amountS
                        ) / order.amountB).sub(
                            order.fillAmountS
                        ) / 2;
                    } else {
                        split = nextFillAmountS.sub(
                            order.fillAmountS.mul(
                                order.amountB
                            ) / order.amountS
                        ) / 2;
                    }

                    if (order.capByAmountB) {
                        order.splitS = split;
                    } else {
                        order.splitB = split;
                    }

                    // This implicits order with smaller index in the ring will
                    // be paid LRC reward first, so the orders in the ring does
                    // mater.
                    if (split > 0) {
                        minerLrcSpendable = minerLrcSpendable.sub(state.lrcFeeState);
                        state.lrcReward = state.lrcFeeState;
                    }
                }

                order.lrcFeeState = 0;
            }
        }
    }

    function settleRing(
        Context ctx
        )
        private
    {
        bytes32[] memory batch = new bytes32[](ctx.ringSize * 7);
        bytes32[] memory historyBatch = new bytes32[](ctx.ringSize * 2);
        Fill[] memory fills = new Fill[](ctx.ringSize);

        uint p = 0;
        uint q = 0;
        uint prevSplitB = ctx.orders[ctx.ringSize - 1].splitB;
        for (uint i = 0; i < ctx.ringSize; i++) {
            Order memory order = ctx.orders[i];
            uint nextFillAmountS = ctx.orders[(i + 1) % ctx.ringSize].fillAmountS;

            // Store owner and tokenS of every order
            batch[p++] = bytes32(order.owner);
            batch[p++] = bytes32(order.signer);
            batch[p++] = bytes32(order.trackerAddr);
            batch[p++] = bytes32(order.tokenS);

            // Store all amounts
            batch[p++] = bytes32(order.fillAmountS - prevSplitB);
            batch[p++] = bytes32(prevSplitB + order.splitS);
            batch[p++] = bytes32(order.lrcReward);
            batch[p++] = bytes32(order.lrcFeeState);
            batch[p++] = bytes32(order.wallet);

            historyBatch[q++] = order.orderHash;
            historyBatch[q++] =
                bytes32(order.capByAmountB ? nextFillAmountS : order.fillAmountS);

            fills[i]  = Fill(
                order.orderHash,
                order.fillAmountS,
                order.lrcReward,
                order.lrcFeeState,
                order.splitS,
                order.splitB
            );

            prevSplitB = order.splitB;
        }

        ctx.delegate.batchUpdateHistoryAndTransferTokens(
            lrcTokenAddress,
            ctx.miner,
            historyBatch,
            batch
        );

        emit RingMined(
            ctx.ringIndex,
            ctx.miner,
            fills
        );
    }

    /// @return The smallest order's index.
    function calculateOrderFillAmount(
        Order order,
        Order next,
        uint  i,
        uint  j,
        uint  smallestIdx
        )
        private
        pure
        returns (uint newSmallestIdx)
    {
        // Default to the same smallest index
        newSmallestIdx = smallestIdx;

        uint fillAmountB = order.fillAmountS.mul(
            order.rateB
        ) / order.rateS;

        if (order.capByAmountB) {
            if (fillAmountB > order.amountB) {
                fillAmountB = order.amountB;

                order.fillAmountS = fillAmountB.mul(
                    order.rateS
                ) / order.rateB;

                newSmallestIdx = i;
            }
            order.lrcFeeState = order.lrcFee.mul(
                fillAmountB
            ) / order.amountB;
        } else {
            order.lrcFeeState = order.lrcFee.mul(
                order.fillAmountS
            ) / order.amountS;
        }

        if (fillAmountB <= next.fillAmountS) {
            next.fillAmountS = fillAmountB;
        } else {
            newSmallestIdx = j;
        }
    }

    /// @return Amount of ERC20 token that can be spent by this contract.
    function getSpendable(
        TokenTransferDelegate delegate,
        address tokenAddress,
        address tokenOwner,
        address broker,
        address trackerAddr
        )
        private
        view
        returns (uint spendable)
    {
        ERC20 token = ERC20(tokenAddress);
        spendable = token.allowance(
            tokenOwner,
            address(delegate)
        );
        if (spendable == 0) {
            return;
        }
        uint amount = token.balanceOf(tokenOwner);
        if (amount < spendable) {
            spendable = amount;
            if (spendable == 0) {
                return;
            }
        }

        if (trackerAddr != 0x0) {
            amount = BrokerTracker(trackerAddr).getAllowance(
                tokenOwner,
                broker,
                tokenAddress
            );
            if (amount < spendable) {
                spendable = amount;
            }
        }
    }

    /// @dev validate order's parameters are OK.
    function validateOrder(
        Order order
        )
        private
        view
    {
        require(order.owner != 0x0, "invalid owner");
        require(order.tokenS != 0x0, "invalid tokenS");
        require(order.tokenB != 0x0, "nvalid tokenB");
        require(order.amountS != 0, "invalid amountS");
        require(order.amountB != 0, "invalid amountB");
        require(order.validSince <= block.timestamp, "immature");
        require(order.validUntil > block.timestamp, "expired");
    }

    /// @dev Get the Keccak-256 hash of order with specified parameters.
    function calculateOrderHash(
        Order order
        )
        private
        view
        returns (bytes32)
    {
        return keccak256(
            delegateAddress,
            order.owner,
            order.signer,
            order.tokenS,
            order.tokenB,
            order.wallet,
            order.authAddr,
            order.amountS,
            order.amountB,
            order.validSince,
            order.validUntil,
            order.lrcFee,
            order.option
        );
    }

    function getTradingPairCutoffs(
        address orderOwner,
        address token1,
        address token2
        )
        public
        view
        returns (uint)
    {
        bytes20 tokenPair = bytes20(token1) ^ bytes20(token2);
        TokenTransferDelegate delegate = TokenTransferDelegate(delegateAddress);
        return delegate.tradingPairCutoffs(orderOwner, tokenPair);
    }
}
