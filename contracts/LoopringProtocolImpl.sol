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
pragma solidity ^0.4.15;

import "zeppelin-solidity/contracts/math/Math.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/token/ERC20.sol";

import "./lib/UintLib.sol";
import "./LoopringProtocol.sol";
import "./RinghashRegistry.sol";
import "./TokenRegistry.sol";
import "./TokenTransferDelegate.sol";

/// @title Loopring Token Exchange Protocol Implementation Contract v1
/// @author Daniel Wang - <daniel@loopring.org>,
/// @author Kongliang Zhong - <kongliang@loopring.org>
contract LoopringProtocolImpl is LoopringProtocol {
    using ErrorLib  for bool;
    using Math      for uint;
    using SafeMath  for uint;
    using UintLib   for uint;

    ////////////////////////////////////////////////////////////////////////////
    /// Variables                                                            ///
    ////////////////////////////////////////////////////////////////////////////

    address public  lrcTokenAddress             = address(0);
    address public  tokenRegistryAddress        = address(0);
    address public  ringhashRegistryAddress     = address(0);
    address public  delegateAddress             = address(0);

    uint    public  ringIndex                   = 0;
    bool    private entered                     = false;

    uint    public  constant RATE_RATIO_SCALE   = 1152921504606846976; // 2^^60
    uint    public  constant MAX_RING_SIZE      = 5;

    // The following two maps are used to keep trace of order fill and
    // cancellation history.
    mapping (bytes32 => uint) public filled;
    mapping (bytes32 => uint) public cancelled;

    // A map from address to its cutoff timestamp.
    mapping (address => uint) public cutoffs;


    ////////////////////////////////////////////////////////////////////////////
    /// Structs                                                              ///
    ////////////////////////////////////////////////////////////////////////////

    /// @param order        The original order
    /// @param orderHash    The hash of the ring.
    /// @param feeSelection -
    ///                     A miner-supplied value indicating if LRC (value = 0)
    ///                     or margin split is choosen by the miner (value = 1).
    ///                     We may support more fee model in the future.
    /// @param rate         The actual exhcnage rate, calculated by protocol.
    /// @param availableAmountS Current value of amountS.
    /// @param fillAmountS  Amount of tokenS to sell, calculated by protocol.
    /// @param lrcReward    The amount of LRC paid by miner to order owner in
    ///                     exchange for margin split.
    /// @param lrcFee       The amount of LR paid by order owner to miner.
    /// @param splitS      TokenS paid to miner.
    /// @param splitB      TokenB paid to miner.
    struct OrderState {
        Order   order;
        bytes32 orderHash;
        uint8   feeSelection;
        Rate    rate;
        uint    availableAmountS;
        uint    fillAmountS;
        uint    lrcReward;
        uint    lrcFee;
        uint    splitS;
        uint    splitB;
    }

    // @dev Used to represent an exchange rate instead of a float number.   
    struct Rate {
        uint amountS;
        uint amountB;
    }

    struct Ring {
        bytes32      ringhash;
        OrderState[] orders;
        address      miner;
        address      feeRecepient;
        bool         throwIfLRCIsInsuffcient;
    }


    ////////////////////////////////////////////////////////////////////////////
    /// Events                                                               ///
    ////////////////////////////////////////////////////////////////////////////

    event RingMined(
        uint                _ringIndex,
        uint                _time,
        uint                _blocknumber,
        bytes32     indexed _ringhash,
        address     indexed _miner,
        address     indexed _feeRecepient,
        bool                _ringhashFound);

    event OrderFilled(
        uint                _ringIndex,
        uint                _time,
        uint                _blocknumber,
        bytes32     indexed _ringhash,
        bytes32             _prevOrderHash,
        bytes32     indexed _orderHash,
        bytes32              _nextOrderHash,
        uint                _amountS,
        uint                _amountB,
        uint                _lrcReward,
        uint                _lrcFee);

    event OrderCancelled(
        uint                _time,
        uint                _blocknumber,
        bytes32     indexed _orderHash,
        uint                _amountCancelled);

    event CutoffTimestampChanged(
        uint                _time,
        uint                _blocknumber,
        address     indexed _address,
        uint                _cutoff);


    ////////////////////////////////////////////////////////////////////////////
    /// Constructor                                                          ///
    ////////////////////////////////////////////////////////////////////////////

    function LoopringProtocolImpl(
        address _lrcTokenAddress,
        address _tokenRegistryAddress,
        address _ringhashRegistryAddress,
        address _delegateAddress
        )
        public {

        require(address(0) != _lrcTokenAddress);
        require(address(0) != _tokenRegistryAddress);
        require(address(0) != _delegateAddress);

        lrcTokenAddress             = _lrcTokenAddress;
        tokenRegistryAddress        = _tokenRegistryAddress;
        ringhashRegistryAddress     = _ringhashRegistryAddress;
        delegateAddress             = _delegateAddress;
    }


    ////////////////////////////////////////////////////////////////////////////
    /// Public Functions                                                     ///
    ////////////////////////////////////////////////////////////////////////////

    /// @dev Disable default function.
    function () payable {
        revert();
    }

    /// @dev Submit a order-ring for validation and settlement.
    /// @param addressList  List of each order's tokenS. Note that next order's
    ///                     `tokenS` equals this order's `tokenB`.
    /// @param uintArgsList List of uint-type arguments in this order:
    ///                     amountS, amountB, timestamp, ttl, salt, lrcFee,
    ///                     rateAmountS.
    /// @param uint8ArgsList -
    ///                     List of unit8-type arguments, in this order:
    ///                     marginSplitPercentageList,feeSelectionList.
    /// @param vList        List of v for each order. This list is 1-larger than
    ///                     the previous lists, with the last element being the
    ///                     v value of the ring signature.
    /// @param rList        List of r for each order. This list is 1-larger than
    ///                     the previous lists, with the last element being the
    ///                     r value of the ring signature.
    /// @param sList        List of s for each order. This list is 1-larger than
    ///                     the previous lists, with the last element being the
    ///                     s value of the ring signature.
    /// @param ringminer    The address that signed this tx.
    /// @param feeRecepient The recepient address for fee collection. If this is
    ///                     '0x0', all fees will be paid to the address who had
    ///                     signed this transaction, not `msg.sender`. Noted if
    ///                     LRC need to be paid back to order owner as the result
    ///                     of fee selection model, LRC will also be sent from
    ///                     this address.
    /// @param throwIfLRCIsInsuffcient -
    ///                     If true, throw exception if any order's spendable
    ///                     LRC amount is smaller than requried; if false, ring-
    ///                     minor will give up collection the LRC fee.
    function submitRing(
        address[2][]    addressList,
        uint[6][]       uintArgsList,
        uint8[2][]      uint8ArgsList,
        bool[]          buyNoMoreThanAmountBList,
        uint8[]         vList,
        bytes32[]       rList,
        bytes32[]       sList,
        address         ringminer,
        address         feeRecepient,
        bool            throwIfLRCIsInsuffcient
        )
        public {

        (!entered).orThrow("attepted to re-ent submitRing function");
        entered = true;

        //Check ring size
        uint ringSize = addressList.length;
        (ringSize > 1 && ringSize <= MAX_RING_SIZE)
            .orThrow("invalid ring size");

        verifyInputDataIntegrity(
            ringSize,
            addressList,
            uintArgsList,
            uint8ArgsList,
            buyNoMoreThanAmountBList,
            vList,
            rList,
            sList);

        verifyTokensRegistered(addressList);


        var ringhashRegistry = RinghashRegistry(ringhashRegistryAddress);

        bytes32 ringhash = ringhashRegistry.calculateRinghash(
            ringSize,
            // feeRecepient,
            // throwIfLRCIsInsuffcient,
            vList,
            rList,
            sList
        );

        ringhashRegistry.canSubmit(ringhash, feeRecepient)
            .orThrow("Ring claimed by others");

        verifySignature(
            ringminer,
            ringhash,
            vList[ringSize],
            rList[ringSize],
            sList[ringSize]
        );

        // Assemble input data into a struct so we can pass it to functions.
        var orders = assembleOrders(
            ringSize,
            addressList,
            uintArgsList,
            uint8ArgsList,
            buyNoMoreThanAmountBList,
            vList,
            rList,
            sList);

        if (feeRecepient == address(0)) {
            feeRecepient = ringminer;
        }

        handleRing(
            ringhash,
            orders,
            ringminer,
            feeRecepient,
            throwIfLRCIsInsuffcient
        );

        entered = true;
    }

    /// @dev Cancel a order. Amount (amountS or amountB) to cancel can be
    ///                           specified using orderValues.
    /// @param addresses          owner, tokenS, tokenB
    /// @param orderValues        amountS, amountB, timestamp, ttl, salt,
    ///                           lrcFee, and cancelAmount
    /// @param buyNoMoreThanAmountB -
    ///                           If true, this order does not accept buying
    ///                           more than `amountB`.
    /// @param marginSplitPercentage -
    ///                           The percentage of margin paid to miner.
    /// @param v                  Order ECDSA signature parameter v.
    /// @param r                  Order ECDSA signature parameters r.
    /// @param s                  Order ECDSA signature parameters s.
    function cancelOrder(
        address[3] addresses,
        uint[7]    orderValues,
        bool       buyNoMoreThanAmountB,
        uint8      marginSplitPercentage,
        uint8      v,
        bytes32    r,
        bytes32    s
        )
        public {

        uint cancelAmount = orderValues[6];
        (cancelAmount > 0).orThrow("amount to cancel is zero");

        var order = Order(
            addresses[0],
            addresses[1],
            addresses[2],
            orderValues[0],
            orderValues[1],
            orderValues[2],
            orderValues[3],
            orderValues[4],
            orderValues[5],
            buyNoMoreThanAmountB,
            marginSplitPercentage,
            v,
            r,
            s
        );

        bytes32 orderHash = calculateOrderHash(order);
        cancelled[orderHash] = cancelled[orderHash].add(cancelAmount);

        OrderCancelled(
            block.timestamp,
            block.number,
            orderHash,
            cancelAmount
        );
    }


    /// @dev   Set a cutoff timestamp to invalidate all orders whose timestamp
    ///        is smaller than or equal to the new value of the address's cutoff
    ///        timestamp.
    /// @param cutoff The cutoff timestamp, will default to `block.timestamp`
    ///        if it is 0.
    function setCutoff(uint cutoff) public {
        uint t = cutoff;
        if (t == 0) {
            t = block.timestamp;
        }

        (cutoffs[msg.sender] < t)
            .orThrow("attempted to set cutoff to a smaller value");

        cutoffs[msg.sender] = t;

        CutoffTimestampChanged(
            block.timestamp,
            block.number,
            msg.sender,
            t
        );
    }


    ////////////////////////////////////////////////////////////////////////////
    /// Internal & Private Functions                                         ///
    ////////////////////////////////////////////////////////////////////////////

    /// @dev Validate a ring.
    function verifyRingHasNoSubRing(Ring ring)
        internal
        constant {

        uint ringSize = ring.orders.length;
        // Check the ring has no sub-ring.
        for (uint i = 0; i < ringSize -1; i++) {
            address tokenS = ring.orders[i].order.tokenS;
            for (uint j = i + 1; j < ringSize; j++){
                 (tokenS != ring.orders[j].order.tokenS)
                    .orThrow("found sub-ring");
            }
        }
    }

    function verifyTokensRegistered(address[2][] addressList) internal constant {
        var registryContract = TokenRegistry(tokenRegistryAddress);
        for (uint i = 0; i < addressList.length; i++) {
            registryContract.isTokenRegistered(addressList[i][1])
                .orThrow("token not registered");
        }
    }

    function handleRing(
        bytes32 ringhash,
        OrderState[] orders,
        address miner,
        address feeRecepient,
        bool throwIfLRCIsInsuffcient
        )
        internal {
        var ring = Ring(
            ringhash,
            orders,
            miner,
            feeRecepient,
            throwIfLRCIsInsuffcient);

        // Rings with sub-rings will enable miners to drain all margins. 
        // Therefore we have to verify no sub-ring to be found. 
        verifyRingHasNoSubRing(ring);

        // Calculate the fill exchange rates. We do this before updating order's
        // scale, so the exchange rates are always based on the original order
        // parameter values.
        calculateRingFillRate(ring);

        // Scale down each order independently by substracting amount-filled and
        // amount-cancelled. Order owner's current balance and allowance are
        // not taken into consideration in these operations.
        scaleRingBasedOnHistoricalRecords(ring);

        // Based on the already verified exchange rate provided by ring-miners,
        // we can furthur scale down orders based on token balance and allowance,
        // then find the smallest order of the ring, then calculate each order's
        // `fillAmountS`.
        calculateRingFillAmount(ring);

        // Calculate each order's `lrcFee` and `lrcRewrard` and splict how much
        // of `fillAmountS` shall be paid to matching order or miner as margin
        // split.
        calculateRingFees(ring);

        /// Make payments.
        settleRing(ring);

        RingMined(
            ringIndex++,
            block.timestamp,
            block.number,
            ring.ringhash,
            ring.miner,
            ring.feeRecepient,
            RinghashRegistry(ringhashRegistryAddress).ringhashFound(ring.ringhash)
            );
    }

    function settleRing(Ring ring) internal {
        uint ringSize = ring.orders.length;
        var delegate = TokenTransferDelegate(delegateAddress);

        for (uint i = 0; i < ringSize; i++) {
            var state = ring.orders[i];
            var prev = ring.orders[i.prev(ringSize)];
            var next = ring.orders[i.next(ringSize)];

            // Pay tokenS to previous order, or to miner as previous order's
            // margin split or/and this order's margin split.

            delegate.transferToken(
                state.order.tokenS,
                state.order.owner,
                prev.order.owner,
                state.fillAmountS - prev.splitB);

            if (prev.splitB + state.splitS > 0) {
                delegate.transferToken(
                    state.order.tokenS,
                    state.order.owner,
                    ring.feeRecepient,
                    prev.splitB + state.splitS);
            }

            // Pay LRC
            if (state.lrcReward > 0) {
                delegate.transferToken(
                    lrcTokenAddress,
                    ring.feeRecepient,
                    state.order.owner,
                    state.lrcReward);
            }

            if (state.lrcFee > 0) {
                 delegate.transferToken(
                    lrcTokenAddress,
                    state.order.owner,
                    ring.feeRecepient,
                    state.lrcFee);
            }

            // Update fill records
            if (state.order.buyNoMoreThanAmountB) {
                filled[state.orderHash] += next.fillAmountS;
            } else {
                filled[state.orderHash] += state.fillAmountS;
            }

            OrderFilled(
                ringIndex,
                block.timestamp,
                block.number,
                ring.ringhash,
                prev.orderHash,
                state.orderHash,
                next.orderHash,
                state.fillAmountS + state.splitS,
                next.fillAmountS - state.splitB,
                state.lrcReward,
                state.lrcFee
                );
        }

    }

    function calculateRingFillRate(Ring ring) internal constant {
        var orders = ring.orders;
        uint ringSize = orders.length;

        uint oneMinusLamda = RATE_RATIO_SCALE; // This is the (1- γ) value in the whitepaper.
        for (uint i = 0; i < ringSize; i++) {
            oneMinusLamda = oneMinusLamda
                .mul(orders[i].order.amountB)
                .div(orders[i].order.amountS);
        }

        oneMinusLamda = UintLib.nthRoot(oneMinusLamda, ringSize);
        uint scaleNthRoot = UintLib.nthRoot(RATE_RATIO_SCALE, ringSize);

        (oneMinusLamda <= scaleNthRoot)
            .orThrow("bad ring with unmatchable rates");

        for (i = 0; i < ringSize; i++) {
            var rate = orders[i].rate;
            rate.amountS = rate.amountB
                .mul(oneMinusLamda)
                .div(scaleNthRoot);
        }
    }

    function calculateRingFees(Ring ring) internal constant {
        uint minerLrcSpendable = getLRCSpendable(ring.feeRecepient);
        uint ringSize = ring.orders.length;

        for (uint i = 0; i < ringSize; i++) {
            var state = ring.orders[i];
            var next = ring.orders[i.next(ringSize)];

            if (state.feeSelection == FEE_SELECT_LRC) {

                uint lrcSpendable = getLRCSpendable(state.order.owner);

                if (lrcSpendable < state.lrcFee) {
                    (!ring.throwIfLRCIsInsuffcient)
                        .orThrow("order LRC balance insuffcient");

                    state.lrcFee = lrcSpendable;
                    minerLrcSpendable += lrcSpendable;
                }

            } else if (state.feeSelection == FEE_SELECT_MARGIN_SPLIT) {
                if (minerLrcSpendable >= state.lrcFee) {
                    if (state.order.buyNoMoreThanAmountB) {
                        uint splitS = next.fillAmountS
                            .mul(state.order.amountS)
                            .div(state.order.amountB)
                            .sub(state.fillAmountS);

                        state.splitS = splitS
                            .mul(state.order.marginSplitPercentage)
                            .div(MARGIN_SPLIT_PERCENTAGE_BASE);
                    } else {
                        uint splitB = next.fillAmountS.sub(
                            state.fillAmountS
                                .mul(state.order.amountB)
                                .div(state.order.amountS));

                        state.splitB = splitB
                            .mul(state.order.marginSplitPercentage)
                            .div(MARGIN_SPLIT_PERCENTAGE_BASE);
                    }

                    // This implicits order with smaller index in the ring will
                    // be paid LRC reward first, so the orders in the ring does
                    // mater.
                    if (state.splitS > 0 || state.splitB > 0) {
                        minerLrcSpendable = minerLrcSpendable.sub(state.lrcFee);
                        state.lrcReward = state.lrcFee;
                    }
                    state.lrcFee = 0;
                }
            } else {
                ErrorLib.error("unsupported fee selection value");
            }
        }

    }

    function calculateRingFillAmount(Ring ring) internal constant {

        uint ringSize = ring.orders.length;
        uint smallestIdx = 0;
        uint i;
        uint j;

        for (i = 0; i < ringSize; i++) {
            j = i.next(ring.orders.length);

            uint res = calculateOrderFillAmount(
                ring.orders[i],
                ring.orders[j]);

            if (res == 1) smallestIdx = i;
            else if (res == 2) smallestIdx = j;
        }

        for (i = 0; i < smallestIdx; i++) {
            j = i.next(ring.orders.length);
            (calculateOrderFillAmount(ring.orders[i], ring.orders[j]) == 0)
                .orThrow("unexpected exception in calculateRingFillAmount");
        }
    }

    /// @return 0 if neither order is the smallest one;
    ///         1 if 'state' is the smallest order;
    ///         2 if 'next' is the smallest order.
    function calculateOrderFillAmount(
        OrderState state,
        OrderState next
        )
        internal
        constant
        returns (uint state2IsSmaller) {

        // Update the amount of tokenB this order can buy, whose logic could be
        // a brain-burner:
        // We have `fillAmountB / state.fillAmountS = state.rate.amountB / state.rate.amountS`,
        // therefore, `fillAmountB = state.rate.amountB * state.fillAmountS / state.rate.amountS`,
        uint fillAmountB  = state.rate.amountB
            .mul(state.fillAmountS)
            .div(state.rate.amountS);

        if (state.order.buyNoMoreThanAmountB) {
            if (fillAmountB > state.order.amountB) {
                fillAmountB = state.order.amountB;

                state.fillAmountS = state.rate.amountS
                    .mul(fillAmountB)
                    .div(state.rate.amountB);

                state2IsSmaller = 1;
            }

            state.lrcFee = state.order.lrcFee
                .mul(fillAmountB)
                .div(next.order.amountS);
        } else {
            state.lrcFee = state.order.lrcFee
                .mul(state.fillAmountS)
                .div(state.order.amountS);
        }

        if (fillAmountB <= next.fillAmountS) {
            next.fillAmountS = fillAmountB;
        } else {
            state2IsSmaller = 2;
        }
    }


    /// @dev Scale down all orders based on historical fill or cancellation
    ///      stats but key the order's original exchange rate.
    function scaleRingBasedOnHistoricalRecords(Ring ring) internal constant {

        uint ringSize = ring.orders.length;
        for (uint i = 0; i < ringSize; i++) {
            var state = ring.orders[i];
            var order = state.order;

            if (order.buyNoMoreThanAmountB) {
                uint amountB = order.amountB
                    .sub(filled[state.orderHash])
                    .tolerantSub(cancelled[state.orderHash]);

                order.amountS = amountB.mul(order.amountS).div(order.amountB);
                order.lrcFee = amountB.mul(order.lrcFee).div(order.amountB);

                order.amountB = amountB;
            } else {
                uint amountS = order.amountS
                    .sub(filled[state.orderHash])
                    .tolerantSub(cancelled[state.orderHash]);

                order.amountB = amountS.mul(order.amountB).div(order.amountS);
                order.lrcFee = amountS.mul(order.lrcFee).div(order.amountS);

                order.amountS = amountS;
            }

            (order.amountS > 0).orThrow("amountS is zero");
            (order.amountB > 0).orThrow("amountB is zero");

            state.fillAmountS = order.amountS.min256(state.availableAmountS);
        }
    }

    /// @return Amount of ERC20 token that can be spent by this contract.
    function getSpendable(
        address tokenAddress,
        address tokenOwner
        )
        internal
        constant
        returns (uint) {

        return TokenTransferDelegate(delegateAddress)
            .getSpendable(tokenAddress, tokenOwner);
    }

    /// @return Amount of LRC token that can be spent by this contract.
    function getLRCSpendable(address tokenOwner)
        internal
        constant
        returns (uint) {

        return getSpendable(lrcTokenAddress, tokenOwner);
    }

    /// @dev verify input data's basic integrity.
    function verifyInputDataIntegrity(
        uint ringSize,
        address[2][]    addressList,
        uint[6][]       uintArgsList,
        uint8[2][]      uint8ArgsList,
        bool[]          buyNoMoreThanAmountBList,
        uint8[]         vList,
        bytes32[]       rList,
        bytes32[]       sList
        )
        internal
        constant {

        (ringSize == addressList.length)
            .orThrow("ring data is inconsistent - addressList");
        (ringSize == uintArgsList.length)
            .orThrow("ring data is inconsistent - uintArgsList");
        (ringSize == uint8ArgsList.length)
            .orThrow("ring data is inconsistent - uint8ArgsList");
        (ringSize == buyNoMoreThanAmountBList.length)
            .orThrow("ring data is inconsistent - buyNoMoreThanAmountBList");
        (ringSize + 1 == vList.length)
            .orThrow("ring data is inconsistent - vList");
        (ringSize + 1 == rList.length)
            .orThrow("ring data is inconsistent - rList");
        (ringSize + 1 == sList.length)
            .orThrow("ring data is inconsistent - sList");

        // Validate ring-mining related arguments.
        for (uint i = 0; i < ringSize; i++) {
            (uintArgsList[i][5] > 0).orThrow("order rateAmountS is zero");
            (uint8ArgsList[i][1] <= FEE_SELECT_MAX_VALUE).orThrow("invalid order fee selection ");
        }
    }

    /// @dev        assmble order parameters into Order struct.
    /// @return     A list of orders.
    function assembleOrders(
        uint            ringSize,
        address[2][]    addressList,
        uint[6][]       uintArgsList,
        uint8[2][]      uint8ArgsList,
        bool[]          buyNoMoreThanAmountBList,
        uint8[]         vList,
        bytes32[]       rList,
        bytes32[]       sList
        )
        internal
        constant
        returns (OrderState[]) {

        var orders = new OrderState[](ringSize);

        for (uint i = 0; i < ringSize; i++) {
            uint j = i.prev(ringSize);

            var order = Order(
                addressList[i][0],
                addressList[i][1],
                addressList[j][1],
                uintArgsList[i][0],
                uintArgsList[i][1],
                uintArgsList[i][2],
                uintArgsList[i][3],
                uintArgsList[i][4],
                uintArgsList[i][5],
                buyNoMoreThanAmountBList[i],
                uint8ArgsList[i][0],
                vList[i],
                rList[i],
                sList[i]);

            bytes32 orderHash = calculateOrderHash(order);

            verifySignature(
                order.owner,
                orderHash,
                order.v,
                order.r,
                order.s);

            validateOrder(order);

            orders[i] = OrderState(
                order,
                orderHash,
                uint8ArgsList[i][1],  // feeSelection
                Rate(order.amountS, order.amountB),
                getSpendable(order.tokenS, order.owner),
                0,   // fillAmountS
                0,   // lrcReward
                0,   // lrcFee
                0,   // splitS
                0    // splitB
                );

            /* (orders[i].availableAmountS > 0) */
            /*     .orThrow("order balance is zero"); */
        }

        return orders;
    }

    /// @dev validate order's parameters are OK.
    function validateOrder(Order order) internal constant {
        (order.owner != address(0))
            .orThrow("invalid order owner");
        (order.tokenS != address(0))
            .orThrow("invalid order tokenS");
        (order.tokenB != address(0))
            .orThrow("invalid order tokenB");
        (order.amountS > 0)
            .orThrow("invalid order amountS");
        (order.amountB > 0)
            .orThrow("invalid order amountB");
        /* (order.timestamp <= block.timestamp) */
        /*     .orThrow("order is too early to match"); */
        (order.timestamp > cutoffs[order.owner])
            .orThrow("order is cut off");
        (order.ttl > 0)
            .orThrow("order ttl is 0");
        (order.timestamp + order.ttl > block.timestamp)
            .orThrow("order is expired");
        (order.salt > 0)
            .orThrow("invalid order salt");
        (order.marginSplitPercentage <= MARGIN_SPLIT_PERCENTAGE_BASE)
            .orThrow("invalid order marginSplitPercentage");
    }

    /// @dev Get the Keccak-256 hash of order with specified parameters.
    function calculateOrderHash(Order order)
        internal
        constant
        returns (bytes32) {

        return keccak256(
            address(this),
            order.tokenS,
            order.tokenB,
            order.amountS,
            order.amountB,
            order.timestamp,
            order.ttl,
            order.salt,
            order.lrcFee,
            order.buyNoMoreThanAmountB,
            order.marginSplitPercentage);
    }

    /// @return The signer's address.
    function verifySignature(
        address signer,
        bytes32 hash,
        uint8   v,
        bytes32 r,
        bytes32 s)
        public
        constant
        {

        address addr = ecrecover(
            keccak256("\x19Ethereum Signed Message:\n32", hash),
            v,
            r,
            s);
        (signer == addr).orThrow("invalid signature");
    }

    function getOrderFilled(bytes32 orderHash)
        public
        constant
        returns (uint) {
        return filled[orderHash];
    }

    function getOrderCancelled(bytes32 orderHash)
        public
        constant
        returns (uint) {
        return cancelled[orderHash];
    }
}
