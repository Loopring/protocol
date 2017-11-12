pragma solidity 0.4.18;

import "./lib/MathUint.sol";
import "./TokenTransferDelegate.sol";
import "./CommonLib.sol";
import "./Order.sol";
import "./LoopringProtocol.sol";


library State {
    using MathUint for uint;
    using Order for uint[16];

    uint private constant MARGIN_SPLIT_PERCENTAGE_BASE = 100;
    uint private constant FEE_SELECT_LRC               = 0;
    uint private constant FEE_SELECT_MARGIN_SPLIT      = 1;

    uint private constant ORDER_OWNER                   = 0;
    uint private constant ORDER_TOKEN_S                 = 1;
    uint private constant ORDER_AMOUNT_S                = 3;
    uint private constant ORDER_AMOUNT_B                = 4;
    uint private constant ORDER_LRC_FEE                 = 5;
    uint private constant ORDER_LIMIT_BY_AMOUNT_B       = 6;
    uint private constant ORDER_MARGIN_SPLIT_PERCENTAGE = 7;
    uint private constant ORDER_FEE_SELECTION           = 14;
    uint private constant ORDER_RATE_AMOUNT_S           = 15;

    uint private constant ORDER_HASH       = 0;
    uint private constant BALANCE_AMOUNT_X = 1;
    uint private constant CURRENT_S        = 2;
    uint private constant CURRENT_B        = 3;
    uint private constant CURRENT_LRC_FEE  = 4;
    uint private constant FILL_AMOUNT_S    = 5;
    uint private constant LRC_REWARD       = 6;
    uint private constant SPLIT_S          = 7;
    uint private constant SPLIT_B          = 8;
    uint private constant LRC_AVAILABLE    = 9;

    struct History {
        // What was already filled or canceled by order
        mapping (uint => uint) balances;
    }

    function setupOrderHash(
        uint[10] memory state,
        uint[16] memory order
        )
        internal
        view
    {
        state[ORDER_HASH] = order.calculateHash();
        order.verifySignature(state[ORDER_HASH]);
    }

    function setupCurrentAmounts(
        uint[10] memory state,
        History storage history,
        uint[16] memory order
        )
        internal
        view
    {
        state[BALANCE_AMOUNT_X] = history.balances[state[ORDER_HASH]];

        if (order[ORDER_LIMIT_BY_AMOUNT_B] != 0) {
            state[CURRENT_B] = order[ORDER_AMOUNT_B].tolerantSub(state[BALANCE_AMOUNT_X]);
            state[CURRENT_S] = state[CURRENT_B].mul(
                order[ORDER_AMOUNT_S]
            ) / order[ORDER_AMOUNT_B];
            state[CURRENT_LRC_FEE] = state[CURRENT_B].mul(
                order[ORDER_LRC_FEE]
            ) / order[ORDER_AMOUNT_B];
        } else {
            state[CURRENT_S] = order[ORDER_AMOUNT_S].tolerantSub(state[BALANCE_AMOUNT_X]);
            state[CURRENT_B] = state[CURRENT_S].mul(
                order[ORDER_AMOUNT_B]
            ) / order[ORDER_AMOUNT_S];
            state[CURRENT_LRC_FEE] = state[CURRENT_S].mul(
                order[ORDER_LRC_FEE]
            ) / order[ORDER_AMOUNT_S];
        }

        require(state[CURRENT_B] != 0);
        require(state[CURRENT_S] != 0);
    }

    function setupFillAmountS(
        uint[10] memory state,
        TokenTransferDelegate delegate,
        uint[16] memory order
        )
        internal
        view
    {
        uint availableAmountS = order.getSpendableS(delegate);
        state[FILL_AMOUNT_S] = (
            availableAmountS < state[CURRENT_S]
            ? availableAmountS : state[CURRENT_S]
        );
    }

    function setupSpendableLrc(
        uint[10] memory state,
        TokenTransferDelegate delegate,
        address lrcTokenAddress,
        uint[16] memory order
        )
        internal
        view
    {
        state[LRC_AVAILABLE] = order.getSpendableLrc(delegate, lrcTokenAddress);
    }

    function exchangeWith(
        uint[10] memory state,
        uint[16] memory order,
        uint[10] memory nextState,
        uint i
    )
        internal
        pure
        returns (uint secondRoundTo)
    {
        uint fillAmountB = state[FILL_AMOUNT_S].mul(
            order[ORDER_AMOUNT_B]
        ) / order[ORDER_RATE_AMOUNT_S];

        if (order[ORDER_LIMIT_BY_AMOUNT_B] != 0) {
            if (fillAmountB > state[CURRENT_B]) {
                fillAmountB = state[CURRENT_B];

                state[FILL_AMOUNT_S] = fillAmountB.mul(
                    order[ORDER_RATE_AMOUNT_S]
                ) / order[ORDER_AMOUNT_B];

                secondRoundTo = i;
            }
        }

        state[CURRENT_LRC_FEE] = order[ORDER_LRC_FEE].mul(
            state[FILL_AMOUNT_S]
        ) / state[CURRENT_S];

        if (fillAmountB <= nextState[FILL_AMOUNT_S]) {
            nextState[FILL_AMOUNT_S] = fillAmountB;
        } else {
            secondRoundTo = i + 1;
        }
    }

    function splitWith(
        uint[10] memory state,
        uint[16] memory order,
        uint[10] memory nextState,
        uint minerAvailableLrc
    )
        internal
        pure
    {
        uint percentage = order[ORDER_MARGIN_SPLIT_PERCENTAGE];

        if (state[LRC_AVAILABLE] < state[CURRENT_LRC_FEE]) {
            state[CURRENT_LRC_FEE] = state[LRC_AVAILABLE];
            percentage = MARGIN_SPLIT_PERCENTAGE_BASE;
        }

        // When an order's LRC fee is 0 or smaller than the specified fee,
        // we help miner automatically select margin-split.
        if (state[CURRENT_LRC_FEE] == 0) {
            percentage = MARGIN_SPLIT_PERCENTAGE_BASE;
        }

        if (order[ORDER_FEE_SELECTION] == FEE_SELECT_MARGIN_SPLIT || state[CURRENT_LRC_FEE] == 0) {
            // Only calculate split when miner has enough LRC;
            // otherwise all splits are 0.
            if (minerAvailableLrc >= state[CURRENT_LRC_FEE]) {
                uint split;
                if (order[ORDER_LIMIT_BY_AMOUNT_B] != 0) {
                    split = (nextState[FILL_AMOUNT_S].mul(
                        state[CURRENT_S]
                    ) / state[CURRENT_B]).sub(
                        state[FILL_AMOUNT_S]
                    );
                } else {
                    split = nextState[FILL_AMOUNT_S].sub(
                        state[FILL_AMOUNT_S].mul(
                            state[CURRENT_B]
                        ) / state[CURRENT_S]
                    );
                }

                if (percentage != MARGIN_SPLIT_PERCENTAGE_BASE) {
                    split = split.mul(
                        order[ORDER_MARGIN_SPLIT_PERCENTAGE]
                    ) / MARGIN_SPLIT_PERCENTAGE_BASE;
                }

                if (order[ORDER_LIMIT_BY_AMOUNT_B] != 0) {
                    state[SPLIT_S] = split;
                } else {
                    state[SPLIT_B] = split;
                }

                // This implicits order with smaller index in the ring will
                // be paid LRC reward first, so the orders in the ring does
                // mater.
                if (split > 0) {
                    minerAvailableLrc = minerAvailableLrc.sub(state[CURRENT_LRC_FEE]);
                    state[LRC_REWARD] = state[CURRENT_LRC_FEE];
                }
                state[CURRENT_LRC_FEE] = 0;
            }
        } else if (order[ORDER_FEE_SELECTION] == FEE_SELECT_LRC) {
            minerAvailableLrc += state[CURRENT_LRC_FEE];
        } else {
            revert(); // "unsupported fee selection value");
        }
    }

    function createTransferItem(
        uint[10] memory state,
        uint[16] memory order,
        uint[10] memory prevState
    )
        internal
        pure
        returns (uint[6] memory item)
    {
        item[0] = order[ORDER_TOKEN_S];
        item[1] = order[ORDER_OWNER];
        item[2] = state[FILL_AMOUNT_S] - prevState[SPLIT_B];
        item[3] = prevState[SPLIT_B] + state[SPLIT_S];
        item[4] = state[LRC_REWARD];
        item[5] = state[CURRENT_LRC_FEE];
    }

    function updateBalance(
        uint[10] memory state,
        History storage history,
        uint[16] memory order,
        uint[10] memory nextState
        )
        internal
    {
        uint amount = (
            order[ORDER_LIMIT_BY_AMOUNT_B] != 0
            ? nextState[FILL_AMOUNT_S] : state[FILL_AMOUNT_S]
        );
        history.balances[state[ORDER_HASH]] = state[BALANCE_AMOUNT_X] + amount;
    }

    function increaseBalanceByOrderHash(
        History storage history,
        uint orderHash,
        uint amount
        )
        internal
    {
        history.balances[orderHash] += amount;
    }
}
