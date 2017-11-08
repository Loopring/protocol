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

import "./lib/Bytes32Lib.sol";
import "./lib/Uint8Lib.sol";


/// @title Ring Hash Registry Contract
/// @author Kongliang Zhong - <kongliang@loopring.org>,
/// @author Daniel Wang - <daniel@loopring.org>.
contract RinghashRegistry {
    using Bytes32Lib    for bytes32[];
    using Uint8Lib      for uint8[];

    uint public blocksToLive;

    struct Submission {
        address ringminer;
        uint block;
    }

    mapping (bytes32 => Submission) submissions;


    /// Events

    event RinghashSubmitted(
        address indexed _ringminer,
        bytes32 indexed _ringhash
    );

    /// Constructor

    function RinghashRegistry(uint _blocksToLive)
        public
    {
        require(_blocksToLive > 0);
        blocksToLive = _blocksToLive;
    }

    /// Public Functions

    function submitRinghash(
        uint        ringSize,
        address     ringminer,
        uint8[]     vList,
        bytes32[]   rList,
        bytes32[]   sList
        )
        public
    {
        bytes32 ringhash = calculateRinghash(
            ringSize,
            vList,
            rList,
            sList
        );

        require(canSubmit(ringhash, ringminer)); //, "Ringhash submitted");

        submissions[ringhash] = Submission(ringminer, block.number);
        RinghashSubmitted(ringminer, ringhash);
    }

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

     /// return value attributes[2] contains the following values in this order:
     /// canSubmit, isReserved.
    function computeAndGetRinghashInfo(
        uint        ringSize,
        address     ringminer,
        uint8[]     vList,
        bytes32[]   rList,
        bytes32[]   sList
        )
        public
        view
        returns (bytes32 ringhash, bool[2] memory attributes)
    {
        ringhash = calculateRinghash(
            ringSize,
            vList,
            rList,
            sList
        );

        attributes[0] = canSubmit(ringhash, ringminer);
        attributes[1] = isReserved(ringhash, ringminer);
    }

    /// @return true if a ring's hash can be submitted;
    /// false otherwise.
    function canSubmit(
        bytes32 ringhash,
        address ringminer)
        public
        view
        returns (bool)
    {
        var submission = submissions[ringhash];
        return (
            submission.ringminer == address(0) || (
            submission.block + blocksToLive < block.number) || (
            submission.ringminer == ringminer)
        );
    }

    /// @return true if a ring's hash was submitted and still valid;
    /// false otherwise.
    function isReserved(
        bytes32 ringhash,
        address ringminer)
        public
        view
        returns (bool)
    {
        var submission = submissions[ringhash];
        return (
            submission.block + blocksToLive >= block.number && (
            submission.ringminer == ringminer)
        );
    }
}
