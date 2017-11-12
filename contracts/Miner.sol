pragma solidity 0.4.18;

import "./RinghashRegistry.sol";
import "./Order.sol";
import "./CommonLib.sol";


library Miner {
    uint private constant ADDR          = 0;
    uint private constant EC_V          = 1;
    uint private constant EC_R          = 2;
    uint private constant EC_S          = 3;
    uint private constant FEE_RECIPIENT = 4;

    function getFeeRecipient(uint[5] memory miner)
        internal
        pure
        returns (address feeRecipient)
    {
        feeRecipient = address(miner[FEE_RECIPIENT]);
        if (feeRecipient == address(0)) {
            feeRecipient = address(miner[ADDR]);
        }
    }

    function verifyRinghash(
        uint[5] memory miner,
        RinghashRegistry ringhashRegistry,
        uint size,
        uint[16][] memory orders
        )
        internal
        view
        returns (bytes32, bool)
    {
        bytes32 ringhash = Order.calculateAllOrdersHash(size, orders);

        CommonLib.verifySignature(
            address(miner[ADDR]),
            ringhash,
            uint8(miner[EC_V]),
            bytes32(miner[EC_R]),
            bytes32(miner[EC_S])
        );

        var (ringSubmitted, ringReserved) = ringhashRegistry.getRinghashInfo(
            address(miner[ADDR]), ringhash
        );

        require(ringSubmitted == false);

        return (ringhash, ringReserved);
    }
}
