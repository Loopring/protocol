/*
  https://github.com/christianlundkvist/simple-multisig/blob/master/contracts/SimpleMultiSig.sol
*/
pragma solidity 0.4.18;

contract SimpleMultiSig {
    uint public nonce;                  // (only) mutable state
    uint public threshold;              // immutable state
    mapping (address => bool) isOwner;  // immutable state
    address[] public owners;            // immutable state

    function SimpleMultiSig(
        uint      _threshold,
        address[] _owners
        )
        public
    {
        require(_owners.length <= 10);
        require(_threshold <= _owners.length);
        require(_threshold != 0);

        address lastAdd = address(0); 
        for (uint i=0; i<_owners.length; i++) {
            require(_owners[i] > lastAdd);
            isOwner[_owners[i]] = true;
            lastAdd = _owners[i];
        }
        owners = _owners;
        threshold = _threshold;
    }

    function () payable public {}

    // Note that address recovered from signatures must be strictly increasing.
    function execute(
        uint8[]   sigV,
        bytes32[] sigR,
        bytes32[] sigS,
        address   destination,
        uint      value,
        bytes     data
        )
        public
    {
        uint len = sigR.length;
        require(len == threshold);
        require(len == sigS.length);
        require(len == sigV.length);

        // Follows ERC191 signature scheme:
        //    https://github.com/ethereum/EIPs/issues/191
        bytes32 txHash = keccak256(
            byte(0x19),
            byte(0),
            this,
            destination,
            value,
            data,
            nonce
          );

        address lastAdd = address(0); // cannot have address(0) as an owner

        for (uint i = 0; i < threshold; i++) {
            address recovered = ecrecover(txHash, sigV[i], sigR[i], sigS[i]);
            require(recovered > lastAdd && isOwner[recovered]);
            lastAdd = recovered;
        }

        // If we make it here all signatures are accounted for
        nonce = nonce + 1;
        require(destination.call.value(value)(data));
    }
}