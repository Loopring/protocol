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

/// @title UintUtil
/// @author Daniel Wang - <daniel@loopring.org>
/// @dev uint utility functions

import "zeppelin-solidity/contracts/math/SafeMath.sol";

library UintLib {
    using SafeMath  for uint;

    function tolerantSub(uint x, uint y) public constant returns (uint z) {
        if (x >= y) z = x - y; 
        else z = 0;
    }

    function next(uint i, uint size) internal constant returns (uint) {
        return (i + 1) % size;
    }

    function prev(uint i, uint size) internal constant returns (uint) {
        return (i + size - 1) % size;
    }

    function pow(uint x, uint n) public constant returns (uint result) {
        if (x == 0) result = 0;
        else if (x == 1 || n == 0) result = 1;
        else {
            result = 1;
            for (uint i = 0; i < n; i++) {
                result *= x;
            }
            assert(result >= x); 
        }
    }

    /// Based on the nth root algorithm derived from Newton's method
    /// (https://en.wikipedia.org/wiki/Nth_root_algorithm)
    /// @return the integer root (the largest integer x for with x**n <= k)
    function nthRoot(uint k, uint n) constant returns(uint) {
        uint x = k;
        uint y = (x + 1) / 2;
        while (y < x) {
            x = y;
            y = ((n - 1) * x + k / pow(x, n - 1)) / n;
        }
        return x;
    }
}
