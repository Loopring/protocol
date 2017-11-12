pragma solidity 0.4.18;

import "./lib/ERC20.sol";
import "./TokenTransferDelegate.sol";


library CommonLib {
    function getSpendable(
        TokenTransferDelegate delegate,
        address tokenOwner,
        address tokenAddress
    )
        internal
        view
        returns (uint)
    {
        ERC20 token = ERC20(tokenAddress);
        uint allowance = token.allowance(tokenOwner, delegate);
        uint balance = token.balanceOf(tokenOwner);
        return allowance < balance ? allowance : balance;
    }

    function verifySignature(
        address signer,
        bytes32 hash,
        uint8   v,
        bytes32 r,
        bytes32 s
        )
        internal
        pure
    {
        require(
            signer == ecrecover(
                keccak256("\x19Ethereum Signed Message:\n32", hash),
                v,
                r,
                s
            )
        );
    }
}
