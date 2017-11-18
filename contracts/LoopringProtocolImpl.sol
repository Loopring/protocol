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


/// @title Loopring Token Exchange Protocol Implementation Contract v1
/// @author Daniel Wang - <daniel@loopring.org>,
/// @author Kongliang Zhong - <kongliang@loopring.org>
contract LoopringProtocolImpl is LoopringProtocol {
    using MathUint      for uint;
    using MathBytes32   for bytes32[];
    using MathUint8     for uint8[];
    
    uint8 private constant IDX_OWNER = 0;
    uint8 private constant IDX_TOKEN_S = 1;
    uint8 private constant IDX_AMOUNT_S = 2;
    uint8 private constant IDX_AMOUNT_B = 3;
    uint8 private constant IDX_TIMESTAMP = 4;
    uint8 private constant IDX_TTL = 5;
    uint8 private constant IDX_SALT = 6;
    uint8 private constant IDX_LRCFEE = 7;
    uint8 private constant IDX_RATEAMOUNT_S = 8;
    

    ////////////////////////////////////////////////////////////////////////////
    /// Variables                                                            ///
    ////////////////////////////////////////////////////////////////////////////

    address public  lrcTokenAddress             = address(0);
    address public  tokenRegistryAddress        = address(0);
    address public  ringhashRegistryAddress     = address(0);
    address public  delegateAddress             = address(0);

    uint    public  maxRingSize                 = 0;
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
    uint    public  rateRatioCVSThreshold       = 0;

    uint    public constant RATE_RATIO_SCALE    = 10000;

    uint64  public constant ENTERED_MASK        = 1 << 63;

    // The following map is used to keep trace of order fill and cancellation
    // history.
    mapping (bytes32 => uint) public cancelledOrFilled;

    // A map from address to its cutoff timestamp.
    mapping (address => uint) public cutoffs;

    ////////////////////////////////////////////////////////////////////////////
    /// Structs                                                              ///
    ////////////////////////////////////////////////////////////////////////////

    struct Rate {
        uint amountS;
        uint amountB;
    }

    /// @param tokenS       Token to sell.
    /// @param tokenB       Token to buy.
    /// @param amountS      Maximum amount of tokenS to sell.
    /// @param amountB      Minimum amount of tokenB to buy if all amountS sold.
    /// @param timestamp    Indicating when this order is created/signed.
    /// @param ttl          Indicating after how many seconds from `timestamp`
    ///                     this order will expire.
    /// @param salt         A random number to make this order's hash unique.
    /// @param lrcFee       Max amount of LRC to pay for miner. The real amount
    ///                     to pay is proportional to fill amount.
    /// @param buyNoMoreThanAmountB -
    ///                     If true, this order does not accept buying more
    ///                     than `amountB`.
    /// @param marginSplitPercentage -
    ///                     The percentage of margin paid to miner.
    /// @param v            ECDSA signature parameter v.
    /// @param r            ECDSA signature parameters r.
    /// @param s            ECDSA signature parameters s.
    /*struct Order {
        address owner;
        address tokenS;
        address tokenB;
        uint    amountS;
        uint    amountB;
        uint    lrcFee;
        bool    buyNoMoreThanAmountB;
        uint8   marginSplitPercentage;
    }*/

    /// @param order        The original order
    /// @param orderHash    The order's hash
    /// @param feeSelection -
    ///                     A miner-supplied value indicating if LRC (value = 0)
    ///                     or margin split is choosen by the miner (value = 1).
    ///                     We may support more fee model in the future.
    /// @param rate         Exchange rate provided by miner.
    ///                     The actual spendable amountS.
    /// @param fillAmountS  Amount of tokenS to sell, calculated by protocol.
    /// @param lrcReward    The amount of LRC paid by miner to order owner in
    ///                     exchange for margin split.
    /// @param lrcFee       The amount of LR paid by order owner to miner.
    /// @param splitS      TokenS paid to miner.
    /// @param splitB      TokenB paid to miner.
    struct OrderState {
        uint8   marginSplitPercentage;
        uint8   feeSelection;
        bool    buyNoMoreThanAmountB;
        
        bytes32 orderHash;
        Rate    rate;
        uint    fillAmountS;
        uint    lrcReward;
        uint    lrcFee;
        uint    splitS;
        uint    splitB;
    }

    ////////////////////////////////////////////////////////////////////////////
    /// Constructor                                                          ///
    ////////////////////////////////////////////////////////////////////////////

    function LoopringProtocolImpl(
        address _lrcTokenAddress,
        address _tokenRegistryAddress,
        address _ringhashRegistryAddress,
        address _delegateAddress,
        uint    _maxRingSize,
        uint    _rateRatioCVSThreshold
        )
        public
    {
        require(address(0) != _lrcTokenAddress);
        require(address(0) != _tokenRegistryAddress);
        require(address(0) != _ringhashRegistryAddress);
        require(address(0) != _delegateAddress);

        require(_maxRingSize > 1);
        require(_rateRatioCVSThreshold > 0);

        lrcTokenAddress = _lrcTokenAddress;
        tokenRegistryAddress = _tokenRegistryAddress;
        ringhashRegistryAddress = _ringhashRegistryAddress;
        delegateAddress = _delegateAddress;
        maxRingSize = _maxRingSize;
        rateRatioCVSThreshold = _rateRatioCVSThreshold;
    }

    ////////////////////////////////////////////////////////////////////////////
    /// Public Functions                                                     ///
    ////////////////////////////////////////////////////////////////////////////

    /// @dev Disable default function.
    function ()
        payable
        public
    {
        revert();
    }
    
    /// @dev Submit a order-ring for validation and settlement.
    /// @param orders List of uint-type arguments in this order:
    ///                     amountS, amountB, timestamp, ttl, salt, lrcFee,
    ///                     rateAmountS.
    /// @param uint8ArgsList -
    ///                     List of unit8-type arguments, in this order:
    ///                     marginSplitPercentageList,feeSelectionList.
    /// @param buyNoMoreThanAmountBList -
    ///                     This indicates when a order should be considered
    ///                     as 'completely filled'.
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
    /// @param feeRecipient The Recipient address for fee collection. If this is
    ///                     '0x0', all fees will be paid to the address who had
    ///                     signed this transaction, not `msg.sender`. Noted if
    ///                     LRC need to be paid back to order owner as the result
    ///                     of fee selection model, LRC will also be sent from
    ///                     this address.
    function submitRing(
        uint[9][]     orders,
        uint8[2][]    uint8ArgsList,
        bool[]        buyNoMoreThanAmountBList,
        uint8[]       vList,
        bytes32[]     rList,
        bytes32[]     sList,
        address       ringminer,
        address       feeRecipient
        )
        public
    {
        // Check if the highest bit of ringIndex is '1'.
        require(ringIndex & ENTERED_MASK != ENTERED_MASK); // "attempted to re-ent submitRing function");

        // Set the highest bit of ringIndex to '1'.
        ringIndex |= ENTERED_MASK;

        //Check ring size
        uint ringSize = orders.length;
        require(ringSize > 1 && ringSize <= maxRingSize); // "invalid ring size");
        
        verifyInputDataIntegrity(
            ringSize,
            orders,
            uint8ArgsList,
            buyNoMoreThanAmountBList,
            vList,
            rList,
            sList
        );

        verifyTokensRegistered(ringSize, orders);

        var ringhash = calculateRinghash(
            ringSize,
            vList,
            rList,
            sList
        );
        
        var ringhashAttributes = RinghashRegistry(
            ringhashRegistryAddress
        ).getRinghashInfo(
            ringhash,
            ringminer
        );

        //Check if we can submit this ringhash.
        require(ringhashAttributes[0]); // "Ring claimed by others");

        verifySignature(
            ringminer,
            ringhash,
            vList[ringSize],
            rList[ringSize],
            sList[ringSize]
        );

        //Assemble input data into structs so we can pass them to other functions.
        var orderStates = assembleOrders(
            ringSize,
            orders,
            uint8ArgsList,
            buyNoMoreThanAmountBList,
            vList,
            rList,
            sList
        );

        if (feeRecipient == address(0)) {
            feeRecipient = ringminer;
        }

        handleRing(
            ringSize,
            ringhash,
            orders,
            orderStates,
            ringminer,
            feeRecipient,
            ringhashAttributes[1]
        );

        ringIndex = ringIndex ^ ENTERED_MASK + 1;
    }
    
    

    /// @dev Cancel a order. cancel amount(amountS or amountB) can be specified
    ///      in orderValues.
    /// @param addresses          owner, tokenS, tokenB
    /// @param orderValues        amountS, amountB, timestamp, ttl, salt, lrcFee,
    ///                           cancelAmountS, and cancelAmountB.
    /// @param buyNoMoreThanAmountB -
    ///                           This indicates when a order should be considered
    ///                           as 'completely filled'.
    /// @param marginSplitPercentage -
    ///                           Percentage of margin split to share with miner.
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
        public
    {
        /*uint cancelAmount = orderValues[6];

        require(cancelAmount > 0); // "amount to cancel is zero");

        var order = Order(
            addresses[0],
            addresses[1],
            addresses[2],
            orderValues[0],
            orderValues[1],
            orderValues[5],
            buyNoMoreThanAmountB,
            marginSplitPercentage
        );

        require(msg.sender == order.owner); // "cancelOrder not submitted by order owner");

        bytes32 orderHash = calculateOrderHash(
            order,
            orderValues[2], // timestamp
            orderValues[3], // ttl
            orderValues[4]  // salt
        );


        verifySignature(
            order.owner,
            orderHash,
            v,
            r,
            s
        );

        cancelledOrFilled[orderHash] = cancelledOrFilled[orderHash].add(cancelAmount);

        OrderCancelled(
            block.timestamp,
            block.number,
            orderHash,
            cancelAmount
        );*/
    }

    /// @dev   Set a cutoff timestamp to invalidate all orders whose timestamp
    ///        is smaller than or equal to the new value of the address's cutoff
    ///        timestamp.
    /// @param cutoff The cutoff timestamp, will default to `block.timestamp`
    ///        if it is 0.
    function setCutoff(uint cutoff)
        public
    {
        uint t = cutoff;
        if (t == 0) {
            t = block.timestamp;
        }

        require(cutoffs[msg.sender] < t); // "attempted to set cutoff to a smaller value");

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
    
     /// @dev Calculate the hash of a ring.
    function calculateRinghash(
        uint        ringSize,
        uint8[]     vList,
        bytes32[]   rList,
        bytes32[]   sList
        )
        public
        pure
        returns (bytes32)
    {
        require(
            ringSize == vList.length - 1 && (
            ringSize == rList.length - 1 && (
            ringSize == sList.length - 1))
        ); //, "invalid ring data");

        return keccak256(
            vList.xorReduce(ringSize),
            rList.xorReduce(ringSize),
            sList.xorReduce(ringSize)
        );
    }

    /// @dev Validate a ring.
    function verifyRingHasNoSubRing(
        uint          ringSize,
        uint[9][]     orders
        )
        private
        pure
    {
        // Check the ring has no sub-ring.
        for (uint i = 0; i < ringSize - 1; i++) {
            uint tokenS = orders[i][IDX_TOKEN_S];
            for (uint j = i + 1; j < ringSize; j++) {
                require(tokenS != orders[j][IDX_TOKEN_S]); // "found sub-ring");
            }
        }
    }

    function verifyTokensRegistered(
        uint         ringSize,
        uint[9][]    orders
        )
        private
        view
    {
        // Extract the token addresses
        var tokens = new address[](ringSize);
        for (uint i = 0; i < ringSize; i++) {
            tokens[i] = address(orders[i][IDX_TOKEN_S]);
        }

        // Test all token addresses at once
        require(
            TokenRegistry(tokenRegistryAddress).areAllTokensRegistered(tokens)
        ); // "token not registered");
    }

    function handleRing(
        uint          ringSize,
        bytes32       ringhash,
        uint[9][]     orders,
        OrderState[]  orderStates,
        address       miner,
        address       feeRecipient,
        bool          isRinghashReserved
        )
        private
    {
        uint64 _ringIndex = ringIndex ^ ENTERED_MASK;
        TokenTransferDelegate delegate = TokenTransferDelegate(delegateAddress);
        address _lrcTokenAddress = lrcTokenAddress;
    
        // Do the hard work.
        verifyRingHasNoSubRing(ringSize, orders);

        // Exchange rates calculation are performed by ring-miners as solidity
        // cannot get power-of-1/n operation, therefore we have to verify
        // these rates are correct.
        verifyMinerSuppliedFillRates(ringSize, orders, orderStates);

        // Scale down each order independently by substracting amount-filled and
        // amount-cancelled. Order owner's current balance and allowance are
        // not taken into consideration in these operations.
        scaleRingBasedOnHistoricalRecords(delegate, ringSize, orders, orderStates);

        // Based on the already verified exchange rate provided by ring-miners,
        // we can furthur scale down orders based on token balance and allowance,
        // then find the smallest order of the ring, then calculate each order's
        // `fillAmountS`.
        calculateRingFillAmount(ringSize, orders, orderStates);

        // Calculate each order's `lrcFee` and `lrcRewrard` and splict how much
        // of `fillAmountS` shall be paid to matching order or miner as margin
        // split.
        calculateRingFees(
            delegate,
            ringSize,
            orders,
            orderStates,
            feeRecipient,
            _lrcTokenAddress
        );

        /// Make payments.
        settleRing(
            delegate,
            ringSize,
            orders,
            orderStates,
            ringhash,
            feeRecipient,
            _lrcTokenAddress,
            _ringIndex
        );

        RingMined(
            _ringIndex,
            block.timestamp,
            block.number,
            ringhash,
            miner,
            feeRecipient,
            isRinghashReserved
        );
    }

    function settleRing(
        TokenTransferDelegate delegate,
        uint          ringSize,
        uint[9][]     orders,
        OrderState[]  orderStates,
        bytes32       ringhash,
        address       feeRecipient,
        address       _lrcTokenAddress,
        uint64        _ringIndex
        )
        private
    {
        bytes32[] memory batch = new bytes32[](ringSize * 6); // ringSize * (owner + tokenS + 4 amounts)
        uint p = 0;
        for (uint i = 0; i < ringSize; i++) {
            var orderState = orderStates[i];
            var prev = orderStates[(i + ringSize - 1) % ringSize];
            var next = orderStates[(i + 1) % ringSize];

            // Store owner and tokenS of every order
            batch[p] = bytes32(orders[i][IDX_OWNER]);
            batch[p+1] = bytes32(orders[i][IDX_TOKEN_S]);

            // Store all amounts
            batch[p+2] = bytes32(orderState.fillAmountS - prev.splitB);
            batch[p+3] = bytes32(prev.splitB + orderState.splitS);
            batch[p+4] = bytes32(orderState.lrcReward);
            batch[p+5] = bytes32(orderState.lrcFee);
            p += 6;

            // Update fill records
            if (orderState.buyNoMoreThanAmountB) {
                cancelledOrFilled[orderState.orderHash] += next.fillAmountS;
            } else {
                cancelledOrFilled[orderState.orderHash] += orderState.fillAmountS;
            }

            OrderFilled(
                _ringIndex,
                block.timestamp,
                block.number,
                ringhash,
                prev.orderHash,
                orderState.orderHash,
                next.orderHash,
                orderState.fillAmountS + orderState.splitS,
                next.fillAmountS - orderState.splitB,
                orderState.lrcReward,
                orderState.lrcFee
            );
        }

        // Do all transactions
        delegate.batchTransferToken(_lrcTokenAddress, feeRecipient, batch);
    }

    /// @dev Verify miner has calculte the rates correctly.
    function verifyMinerSuppliedFillRates(
        uint          ringSize,
        uint[9][]     orders,
        OrderState[]  orderStates
        )
        private
        view
    {
        var rateRatios = new uint[](ringSize);
        uint _rateRatioScale = RATE_RATIO_SCALE;

        for (uint i = 0; i < ringSize; i++) {
            uint s1b0 = orderStates[i].rate.amountS.mul(orders[i][IDX_AMOUNT_B]);
            uint s0b1 = orders[i][IDX_AMOUNT_S].mul(orderStates[i].rate.amountB);

            require(s1b0 <= s0b1); // "miner supplied exchange rate provides invalid discount");

            rateRatios[i] = _rateRatioScale.mul(s1b0) / s0b1;
        }

        uint cvs = MathUint.cvsquare(rateRatios, _rateRatioScale);

        require(cvs <= rateRatioCVSThreshold); // "miner supplied exchange rate is not evenly discounted");
    }

    /// @dev Calculate each order's fee or LRC reward.
    function calculateRingFees(
        TokenTransferDelegate delegate,
        uint            ringSize,
        uint[9][]       orders,
        OrderState[]    orderStates,
        address         feeRecipient,
        address         _lrcTokenAddress
        )
        private
        view
    {
        bool checkedMinerLrcSpendable = false;
        uint minerLrcSpendable = 0;
        //uint8 _marginSplitPercentageBase = MARGIN_SPLIT_PERCENTAGE_BASE;
        
        //uint minerLrcSpendable = getSpendable(delegate, _lrcTokenAddress, feeRecipient);

        for (uint i = 0; i < ringSize; i++) {
        
            var orderState = orderStates[i];
            var next = (i + 1) % ringSize;
            uint lrcReceiable = 0;

            if (orderState.lrcFee == 0) {
                // When an order's LRC fee is 0 or smaller than the specified fee,
                // we help miner automatically select margin-split.
                orderState.feeSelection = FEE_SELECT_MARGIN_SPLIT;
                orderState.marginSplitPercentage = MARGIN_SPLIT_PERCENTAGE_BASE;
            } else {
                uint lrcSpendable = getSpendable(
                    delegate,
                    _lrcTokenAddress,
                    address(orders[i][IDX_OWNER])
                );

                // If the order is selling LRC, we need to calculate how much LRC
                // is left that can be used as fee.
                if (address(orders[i][IDX_TOKEN_S]) == _lrcTokenAddress) {
                    lrcSpendable -= orderState.fillAmountS;
                }

                // If the order is buyign LRC, it will has more to pay as fee.
                if (address(orders[next][IDX_TOKEN_S]) == _lrcTokenAddress) {
                    lrcReceiable = orderStates[next].fillAmountS;
                }

                uint lrcTotal = lrcSpendable + lrcReceiable;

                // If order doesn't have enough LRC, set margin split to 100%.
                if (lrcTotal < orderState.lrcFee) {
                    orderState.lrcFee = lrcTotal;
                    orderState.marginSplitPercentage = MARGIN_SPLIT_PERCENTAGE_BASE;
                }

                if (orderState.lrcFee == 0) {
                    orderState.feeSelection = FEE_SELECT_MARGIN_SPLIT;
                }
            }

            if (orderState.feeSelection == FEE_SELECT_LRC) {
                if (lrcReceiable > 0) {
                    if (lrcReceiable >= orderState.lrcFee) {
                        orderState.splitB = orderState.lrcFee;
                        orderState.lrcFee = 0;
                    } else {
                        orderState.splitB = lrcReceiable;
                        orderState.lrcFee -= lrcReceiable;
                    }
                }
            } else if (orderState.feeSelection == FEE_SELECT_MARGIN_SPLIT) {

                // Only check the available miner balance when absolutely needed
                if (!checkedMinerLrcSpendable && minerLrcSpendable < orderState.lrcFee) {
                    checkedMinerLrcSpendable = true;
                    minerLrcSpendable = getSpendable(delegate, _lrcTokenAddress, feeRecipient);
                }

                // Only calculate split when miner has enough LRC;
                // otherwise all splits are 0.
                if (minerLrcSpendable >= orderState.lrcFee) {
                    // HACK: reuse 'next' here to save on a local variable to stay below stack limit
                    if (orderState.buyNoMoreThanAmountB) {
                        next = (orderStates[next].fillAmountS.mul(
                            orders[i][IDX_AMOUNT_S]
                        ) / orders[i][IDX_AMOUNT_B]).sub(
                            orderState.fillAmountS
                        );
                    } else {
                        next = orderStates[next].fillAmountS.sub(
                            orderState.fillAmountS.mul(
                                orders[i][IDX_AMOUNT_B]
                            ) / orders[i][IDX_AMOUNT_S]
                        );
                    }

                    if (orderState.marginSplitPercentage != MARGIN_SPLIT_PERCENTAGE_BASE) {
                        next = next.mul(
                            orderState.marginSplitPercentage
                        ) / MARGIN_SPLIT_PERCENTAGE_BASE;
                    }

                    if (orderState.buyNoMoreThanAmountB) {
                        orderState.splitS = next;
                    } else {
                        orderState.splitB = next;
                    }

                    // This implicits order with smaller index in the ring will
                    // be paid LRC reward first, so the orders in the ring does
                    // mater.
                    if (next > 0) {
                        minerLrcSpendable -= orderState.lrcFee;
                        orderState.lrcReward = orderState.lrcFee;
                    }
                }

                orderState.lrcFee = 0;
            } else {
                revert(); // "unsupported fee selection value");
            }
        }
    }

    /// @dev Calculate each order's fill amount.
    function calculateRingFillAmount(
        uint          ringSize,
        uint[9][]     orders,
        OrderState[]  orderStates
        )
        private
        pure
    {
        uint smallestIdx = 0;
        uint i;
        uint j;

        for (i = 0; i < ringSize; i++) {
            j = (i + 1) % ringSize;
            smallestIdx = calculateOrderFillAmount(
                orders[i],
                orderStates[i],
                orderStates[j],
                i,
                j,
                smallestIdx
            );
        }

        for (i = 0; i < smallestIdx; i++) {
            calculateOrderFillAmount(
                orders[i],
                orderStates[i],
                orderStates[(i + 1) % ringSize],
                0,               // Not needed
                0,               // Not needed
                0                // Not needed
            );
        }
    }

    /// @return The smallest order's index.
    function calculateOrderFillAmount(
        uint[9]           order,
        OrderState        orderState,
        OrderState        nextOrderState,
        uint              i,
        uint              j,
        uint              smallestIdx
        )
        private
        pure
        returns (uint newSmallestIdx)
    {
        // Default to the same smallest index
        newSmallestIdx = smallestIdx;

        uint fillAmountB = orderState.fillAmountS.mul(
            orderState.rate.amountB
        ) / orderState.rate.amountS;

        if (orderState.buyNoMoreThanAmountB) {
            if (fillAmountB > order[IDX_AMOUNT_B]) {
                fillAmountB = order[IDX_AMOUNT_B];

                orderState.fillAmountS = fillAmountB.mul(
                    orderState.rate.amountS
                ) / orderState.rate.amountB;

                newSmallestIdx = i;
            }
        }

        orderState.lrcFee = order[IDX_LRCFEE].mul(
            orderState.fillAmountS
        ) / order[IDX_AMOUNT_S];

        if (fillAmountB <= nextOrderState.fillAmountS) {
            nextOrderState.fillAmountS = fillAmountB;
        } else {
            newSmallestIdx = j;
        }
    }

    /// @dev Scale down all orders based on historical fill or cancellation
    ///      stats but key the order's original exchange rate.
    function scaleRingBasedOnHistoricalRecords(
        TokenTransferDelegate delegate,
        uint          ringSize,
        uint[9][]     orders,
        OrderState[]  orderStates
        )
        private
        view
    {
        for (uint i = 0; i < ringSize; i++) {
            uint amount;
            var order = orders[i];
            var orderState = orderStates[i];

            if (orderState.buyNoMoreThanAmountB) {
                amount = order[IDX_AMOUNT_B].tolerantSub(
                    cancelledOrFilled[orderState.orderHash]
                );

                order[IDX_AMOUNT_S] = amount.mul(order[IDX_AMOUNT_S]) / order[IDX_AMOUNT_B];
                order[IDX_LRCFEE] = amount.mul(order[IDX_LRCFEE]) / order[IDX_AMOUNT_B];

                order[IDX_AMOUNT_B] = amount;
            } else {
                amount = order[IDX_AMOUNT_S].tolerantSub(
                    cancelledOrFilled[orderState.orderHash]
                );

                order[IDX_AMOUNT_B] = amount.mul(order[IDX_AMOUNT_B]) / order[IDX_AMOUNT_S];
                order[IDX_LRCFEE] = amount.mul(order[IDX_LRCFEE]) / order[IDX_AMOUNT_S];

                order[IDX_AMOUNT_S] = amount;
            }

            require(order[IDX_AMOUNT_S] > 0); // "amountS is zero");
            require(order[IDX_AMOUNT_B] > 0); // "amountB is zero");
            
            uint availableAmountS = getSpendable(delegate, address(order[IDX_TOKEN_S]), address(order[IDX_OWNER]));
            require(availableAmountS > 0); // "order spendable amountS is zero");

            orderState.fillAmountS = (
                order[IDX_AMOUNT_S] < availableAmountS ?
                order[IDX_AMOUNT_S] : availableAmountS
            );
        }
    }

    /// @return Amount of ERC20 token that can be spent by this contract.
    function getSpendable(
        TokenTransferDelegate delegate,
        address tokenAddress,
        address tokenOwner
        )
        private
        view
        returns (uint)
    {
        var token = ERC20(tokenAddress);
        uint allowance = token.allowance(
            tokenOwner,
            address(delegate)
        );
        uint balance = token.balanceOf(tokenOwner);
        return (allowance < balance ? allowance : balance);
    }

    /// @dev verify input data's basic integrity.
    function verifyInputDataIntegrity(
        uint          ringSize,
        uint[9][]     orders,
        uint8[2][]    uint8ArgsList,
        bool[]        buyNoMoreThanAmountBList,
        uint8[]       vList,
        bytes32[]     rList,
        bytes32[]     sList
        )
        private
        pure
    {
        require(ringSize == orders.length); // "ring data is inconsistent - addressList");
        require(ringSize == uint8ArgsList.length); // "ring data is inconsistent - uint8ArgsList");
        require(ringSize == buyNoMoreThanAmountBList.length); // "ring data is inconsistent - buyNoMoreThanAmountBList");
        require(ringSize + 1 == vList.length); // "ring data is inconsistent - vList");
        require(ringSize + 1 == rList.length); // "ring data is inconsistent - rList");
        require(ringSize + 1 == sList.length); // "ring data is inconsistent - sList");

        // Validate ring-mining related arguments.
        for (uint i = 0; i < ringSize; i++) {
            require(orders[i][IDX_RATEAMOUNT_S] > 0); // "order rateAmountS is zero");
            require(uint8ArgsList[i][1] <= FEE_SELECT_MAX_VALUE); // "invalid order fee selection");
        }
    }

    /// @dev        assmble order parameters into Order struct.
    /// @return     A list of orders.
    function assembleOrders(
        uint            ringSize,
        uint[9][]       orders,
        uint8[2][]      uint8ArgsList,
        bool[]          buyNoMoreThanAmountBList,
        uint8[]         vList,
        bytes32[]       rList,
        bytes32[]       sList
        )
        private
        view
        returns (OrderState[] orderStates)
    {
        orderStates = new OrderState[](ringSize);
        for (uint i = 0; i < ringSize; i++) {
        
            var order = orders[i];
            
            address tokenB = address(orders[(i + 1) % ringSize][IDX_TOKEN_S]);
    
            bytes32 orderHash = calculateOrderHash(
                order,
                tokenB,
                uint8ArgsList[i][0],          // marginSplitPercentage
                buyNoMoreThanAmountBList[i]   // buyNoMoreThanAmountB
            );

            verifySignature(
                address(order[IDX_OWNER]),
                orderHash,
                vList[i],
                rList[i],
                sList[i]
            );

            validateOrder(
                order,
                tokenB,
                uint8ArgsList[i][0]          // marginSplitPercentage
            );

            orderStates[i] = OrderState(
                uint8ArgsList[i][0],         // marginSplitPercentage
                uint8ArgsList[i][1],         // feeSelection
                buyNoMoreThanAmountBList[i], // buyNoMoreThanAmountB
                
                orderHash,
                Rate(order[IDX_RATEAMOUNT_S], order[IDX_AMOUNT_B]),
                0,   // fillAmountS
                0,   // lrcReward
                0,   // lrcFee
                0,   // splitS
                0    // splitB
            );
        }
    }

    /// @dev validate order's parameters are OK.
    function validateOrder(
        uint[9] order,
        address tokenB,
        uint8   marginSplitPercentage
        )
        private
        view
    {
        require(address(order[IDX_OWNER]) != address(0)); // "invalid order owner");
        require(address(order[IDX_TOKEN_S]) != address(0)); // "invalid order tokenS");
        require(tokenB != address(0)); // "invalid order tokenB");
        require(order[IDX_AMOUNT_S] != 0); // "invalid order amountS");
        require(order[IDX_AMOUNT_B] != 0); // "invalid order amountB");
        require(order[IDX_TIMESTAMP] <= block.timestamp); // "order is too early to match");
        require(order[IDX_TIMESTAMP] > cutoffs[address(order[IDX_OWNER])]); // "order is cut off");
        require(order[IDX_TTL] != 0); // "order ttl is 0");
        require(order[IDX_TIMESTAMP] + order[IDX_TTL] > block.timestamp); // "order is expired");
        require(order[IDX_SALT] != 0); // "invalid order salt");
        require(marginSplitPercentage <= MARGIN_SPLIT_PERCENTAGE_BASE); // "invalid order marginSplitPercentage");
    }

    /// @dev Get the Keccak-256 hash of order with specified parameters.
    function calculateOrderHash(
        uint[9] order,
        address tokenB,
        uint8   marginSplitPercentage,
        bool    buyNoMoreThanAmountB
        )
        private
        view
        returns (bytes32)
    {
        return keccak256(
            address(this),
            address(order[IDX_OWNER]),
            address(order[IDX_TOKEN_S]),
            tokenB,
            order[IDX_AMOUNT_S],
            order[IDX_AMOUNT_B],
            order[IDX_TIMESTAMP],
            order[IDX_TTL],
            order[IDX_SALT],
            order[IDX_LRCFEE],
            buyNoMoreThanAmountB,
            marginSplitPercentage
        );
    }

    /// @dev Verify signer's signature.
    function verifySignature(
        address signer,
        bytes32 hash,
        uint8   v,
        bytes32 r,
        bytes32 s
        )
        private
        pure
    {
        require(
            signer == ecrecover(
                keccak256("\x19Ethereum Signed Message:\n32", hash),
                v,
                r,
                s
            )
        ); // "invalid signature");
    }

}

