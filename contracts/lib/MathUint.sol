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


/// @title UintUtil
/// @author Daniel Wang - <daniel@loopring.org>
/// @dev uint utility functions
library MathUint {

    function mul(uint a, uint b) internal pure returns (uint c) {
        c = a * b;
        require(a == 0 || c / a == b);
    }

    function sub(uint a, uint b) internal pure returns (uint) {
        require(b <= a);
        return a - b;
    }

    function add(uint a, uint b) internal pure returns (uint c) {
        c = a + b;
        require(c >= a);
    }

    function tolerantSub(uint a, uint b) internal pure returns (uint c) {
        return (a >= b) ? a - b : 0;
    }

    /// @dev calculate the square of Coefficient of Variation (CV)
    /// https://en.wikipedia.org/wiki/Coefficient_of_variation
    function cvsquare(
        uint avg,
        uint scale,
        uint size,
        uint[] arr
        )
        internal
        pure
        returns (uint)
    {
        if (avg == 0) {
            return 0;
        }

        uint cvs = 0;
        uint s = 0;
        for (uint i = 0; i < size; i++) {
            s = arr[i] > avg ? arr[i] - avg : avg - arr[i];
            cvs += mul(s, s);
        }

        return (mul(mul(cvs, scale) / avg, scale) / avg) / (size - 1);
    }
}
