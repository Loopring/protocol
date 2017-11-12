pragma solidity 0.4.18;

import "./lib/MathUint.sol";
import "./TokenTransferDelegate.sol";
import "./TokenRegistry.sol";
import "./CommonLib.sol";


library Order {
    using MathUint for uint;

    uint private constant MARGIN_SPLIT_PERCENTAGE_BASE = 100;
    uint private constant RATE_RATIO_SCALE = 10000;
    uint private constant FEE_SELECT_MAX_VALUE    = 1;

    uint public constant OWNER                   = 0;
    uint public constant TOKEN_S                 = 1;
    uint public constant TOKEN_B                 = 2;
    uint public constant AMOUNT_S                = 3;
    uint public constant AMOUNT_B                = 4;
    uint public constant LRC_FEE                 = 5;
    uint public constant LIMIT_BY_AMOUNT_B       = 6;
    uint public constant MARGIN_SPLIT_PERCENTAGE = 7;
    uint public constant TIMESTAMP               = 8;
    uint public constant TTL                     = 9;
    uint public constant SALT                    = 10;
    uint public constant EC_V                    = 11;
    uint public constant EC_R                    = 12;
    uint public constant EC_S                    = 13;
    uint public constant FEE_SELECTION           = 14;
    uint public constant RATE_AMOUNT_S           = 15;

    struct Cutoff {
        mapping (address => uint) timestamps;
    }

    function setCutoffTimestamp(
        Cutoff storage cutoff,
        address owner,
        uint timestamp
        )
        internal
    {
        require(cutoff.timestamps[owner] < timestamp); // "attempted to set cutoff to a smaller value");
        cutoff.timestamps[owner] = timestamp;
    }

    function verifyInput(
        uint[16] memory order,
        Cutoff storage cutoff
        )
        internal
        view
    {
        // "invalid order owner");
        require(order[OWNER] != 0);
        // "invalid order tokenS");
        require(order[TOKEN_S] != 0);
        // "invalid order tokenB");
        require(order[TOKEN_B] != 0);
        // "invalid order amountS");
        require(order[AMOUNT_S] != 0);
        // "invalid order amountB");
        require(order[AMOUNT_B] != 0);
        // "order is too early to match");
        require(order[TIMESTAMP] <= block.timestamp);
        // "order is cut off");
        require(order[TIMESTAMP] > cutoff.timestamps[address(order[OWNER])]);
        // "order ttl is 0");
        require(order[TTL] != 0);
        // "order is expired");
        require(order[TIMESTAMP] + order[TTL] > block.timestamp);
        // "invalid order salt");
        require(order[SALT] != 0);
        // "invalid order marginSplitPercentage");
        require(order[MARGIN_SPLIT_PERCENTAGE] <= MARGIN_SPLIT_PERCENTAGE_BASE);

        require(order[RATE_AMOUNT_S] != 0);
        require(order[FEE_SELECTION] <= FEE_SELECT_MAX_VALUE);
    }

    function verifySignature(
        uint[16] memory order,
        uint orderHash
        )
        internal
        pure
    {
        CommonLib.verifySignature(
            address(order[OWNER]),
            bytes32(orderHash),
            uint8(order[EC_V]),
            bytes32(order[EC_R]),
            bytes32(order[EC_S])
        );
    }

    function calculateAndVerify(
        address[3] memory addresses,
        uint[7] memory orderValues,
        bool buyNoMoreThanAmountB,
        uint8 marginSplitPercentage,
        uint8 v,
        bytes32 r,
        bytes32 s
        )
        internal
        view
        returns (uint orderHash)
    {
        orderHash = uint(
            keccak256(
                address(this),
                addresses[0],
                addresses[1],
                addresses[2],
                orderValues[0],
                orderValues[1],
                orderValues[2], // timestamp
                orderValues[3], // ttl
                orderValues[4], // salt
                orderValues[5],
                buyNoMoreThanAmountB,
                marginSplitPercentage
            )
        );

        CommonLib.verifySignature(
            addresses[0],
            bytes32(orderHash),
            v,
            r,
            s
        );
    }

    function getSpendableS(
        uint[16] memory order,
        TokenTransferDelegate delegate
        )
        internal
        view
        returns (uint)
    {
        return CommonLib.getSpendable(
            delegate,
            address(order[OWNER]),
            address(order[TOKEN_S])
        );
    }

    function getSpendableLrc(
        uint[16] memory order,
        TokenTransferDelegate delegate,
        address lrcTokenAddress
        )
        internal
        view
        returns (uint)
    {
        return CommonLib.getSpendable(
            delegate,
            address(order[OWNER]),
            lrcTokenAddress
        );
    }

    function calculateHash(
        uint[16] memory order
        )
        internal
        view
        returns (uint)
    {
        return uint(
            keccak256(
                address(this),
                address(order[OWNER]),
                address(order[TOKEN_S]),
                address(order[TOKEN_B]),
                order[AMOUNT_S],
                order[AMOUNT_B],
                order[TIMESTAMP],
                order[TTL],
                order[SALT],
                order[LRC_FEE],
                order[LIMIT_BY_AMOUNT_B] != 0,
                uint8(order[MARGIN_SPLIT_PERCENTAGE])
            )
        );
    }

    function verifyRateRatio(
        uint threshold,
        uint size,
        uint[16][] memory orders
        )
        internal
        pure
    {
        uint[] memory ratios = new uint[](size);
        uint avg = 0;
        for (uint i = 0; i < size; i++) {
            uint s1b0 = orders[i][RATE_AMOUNT_S].mul(orders[i][AMOUNT_B]);
            uint s0b1 = orders[i][AMOUNT_S].mul(orders[i][AMOUNT_B]);
            // miner supplied exchange rate provides invalid discount
            require(s1b0 <= s0b1);
            ratios[i] = RATE_RATIO_SCALE.mul(s1b0) / s0b1;
            avg += ratios[i];
        }
        // Exchange rates calculation are performed by ring-miners as solidity
        // cannot get power-of-1/n operation, therefore we have to verify
        // these rates are correct.
        require(
            MathUint.cvsquare(
                avg / size,
                RATE_RATIO_SCALE,
                size,
                ratios
            ) <= threshold
        );
    }

    function verifyDuplicateTokenS(
        uint size,
        uint[16][] memory orders
        )
        internal
        pure
    {
        for (uint i = 0; i < size - 1; i++) {
            uint tokenS = orders[i][TOKEN_S];
            for (uint j = i + 1; j < size; j++) {
                require(tokenS != orders[j][TOKEN_S]);
            }
        }
    }

    function verifyTokensRegistered(
        TokenRegistry tokenRegistry,
        uint size,
        uint[16][] memory orders
        )
        internal
        view
    {
        address[] memory allTokensB = new address[](size);
        for (uint i = 0; i < size; i++) {
            allTokensB[i] = address(orders[i][TOKEN_B]);
        }
        require(tokenRegistry.areAllTokensRegistered(allTokensB));
    }

    function calculateAllOrdersHash(
        uint size,
        uint[16][] memory orders
        )
        internal
        pure
        returns (bytes32 ringhash)
    {
        // is the any reason not to just XOR addresses instead of v, r, s?
        //  it just requires more computation and stack space
        uint8 ringhashXorV = 0;
        uint ringhashXorR = 0;
        uint ringhashXorS = 0;

        for (uint i = 0; i < size; i++) {
            // alternative ringhash
            //  ringhashXor ^= address(order[ORDER_OWNER]);
            ringhashXorV ^= uint8(orders[i][EC_V]);
            ringhashXorR ^= orders[i][EC_R];
            ringhashXorS ^= orders[i][EC_S];
        }

        // alternative ringhash
        //  bytes32 ringhash = keccak256(ringhashXor);
        ringhash = keccak256(
            ringhashXorV,
            ringhashXorR,
            ringhashXorS
        );
    }
}
