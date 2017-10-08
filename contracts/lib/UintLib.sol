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

    /// @dev calculate the square of Coefficient of Variation (CV)
    /// https://en.wikipedia.org/wiki/Coefficient_of_variation
    function cvsquare(
        uint[] arr,
        uint scale
        )
        public
        constant
        returns (uint) {

        uint len = arr.length;
        require(len > 1);
        require(scale > 0);

        uint avg = 0;
        for (uint i = 0; i < len; i++) {
            avg += arr[i];
        }

        avg = avg.div(len);

        if (avg == 0) {
            return 0;
        }

        uint cvs = 0;
        for (i = 0; i < len; i++) {
            uint sub = 0;
            if (arr[i] > avg) {
                sub = arr[i] - avg;
            } else {
                sub = avg - arr[i];
            }
            cvs += sub.mul(sub);
        }
        return cvs
            .mul(scale)
            .div(avg)
            .mul(scale)
            .div(avg)
            .div(len - 1);
    }

    function pow(uint x, uint n) public constant returns (uint result) {
        if (x == 0) result = 0;
        else if (x == 1 || n == 0) result = 1;
        else {
            result = 1;
            for (uint i = 0; i < n; i++) {
                result *= x;
            }
            // assert(result >= x); 
        }
    }

    function bitCount(uint x) public constant returns (uint result) {
        result = 0;
        uint xx = x;
        while(xx > 0) {
            xx >>= 1;
            result += 1;
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
            y = ((n-1) * x + k / pow(x, n-1)) / n;
        }
        return x;
    }
}
