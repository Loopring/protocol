# Optimization Bounty Submissions

We'll be collecting optimization bounty submissions and their responses here. Please be sure to take a look before making a submission. Thank you!

## #01 [Merged]

- From: Brecht Devos <brechtp.devos@gmail.com>
- Time: 11:22 29/10/2017 Beijing Time
- PR: https://github.com/Loopring/protocol/pull/35
- Result: reduced gas usage from 508406 to 462621 (=45785), a 8.95% reduction of 511465.



## #02 [Merged]

- From: Kecheng Yue <yuekec@gmail.com>
- Time: 00:46 01/11/2017 Beijing Time
- PR: https://github.com/Loopring/protocol/pull/37
- Result: reduced gas usage from 462621 to 447740 (=14881), a 2.91% reduction of 511465.


## #03 [TBD]

- From: Brecht Devos <brechtp.devos@gmail.com>
- Time: 00:55 01/11/2017 Beijing Time
- PR: TBD
- Result: TBD

Hi,
 
I reduced the number of necessary SSTORE (and SLOAD) instructions in submitRing. The idea is pretty simple: 2 storage variables are always updated in the function: ‘entered’ and ‘ringIndex’.
'entered’ is used to check for reentrancy of the function, so it’s updated once at the very beginning and once at the very end (2 SSTORES). ‘ringIndex’ is also read in the function and updated at the end (1 SSTORE).
You can reduce the number of SSTORES by combining these 2 storage variables in 1. Instead of setting ‘entered’ to true at the beginning, you can set ‘ringIndex’ to an invalid value (uint(-1)). So the reentrance check becomes ‘ringIndex != uint(-1)’.
At the end of the function ‘ringIndex’ is updated again with it’s original value incremented by 1. This also signals that the function has reached its end (‘ringIndex’ != uint(-1)). This is where the SSTORE instruction is saved, before the change 2 SSTORE instructions were needed to update ‘entered’ and ‘ringIndex’.
 
Some thoughts about the change:
Reading the storage variable ‘ringIndex’ while submitRing is running will not return the correct value (as it is set to uint(-1)). This shouldn’t be a problem because (as far as I know) this can only be done in a reentrance scenario.
But this still could be fixed by reserving a single bit of ‘ringIndex’ as a sort of ‘busy bit’. This bit could be set at the start of the function (‘ringIndex |= (1 << 255)’) without destroying the actual index bits. The actual ‘ringIndex’ could then be read by ignoring the busy bit.
Extra care needs to be given to not accedentially read from the ‘ringIndex’ storage variable in the submitRing function. This isn’t that big of a problem because it’s used only twice.
 
This change saves a bit more than 1% in gas (which is what I expected calculating the theoretical gas costs).
 
Let me know what you think of this optimization. For completeness’ sake I pasted the git diff below with all necessary changes. If you’re alright with the change I could make a pull request if you want.
I had to put the calculateRinghash inside its own function to save on local variables inside submitRing(). Otherwise it’s some very small changes in a couple of places.
 
Brecht Devos

## #04 [Duplicate of #2]

- From: Brecht Devos <brechtp.devos@gmail.com>
- Time: 04:35 01/11/2017 Beijing Time
- PR: TBD
- Result: TBD

Hi,
 
I’ve done a pretty straight forward optimization (and code simplification) in TokenRegistry. I’ve changed the tokens array to a mapping like this: mapping (address => bool) tokenAddressMap.
This makes isTokenRegistered() faster because the tokens array doesn’t need to be searched for the matching address
This simplifies the code in unregisterToken() and  isTokenRegistered()
 
This makes the verifyTokensRegistered() function that calls isTokenRegistered() a couple of times quite a bit faster. In total this change reduces the gas usage about 2%.
 
I’ve pasted the complete updated code for the TokenRegistry contract below.
 
Let me know if you’ve got any questions/thoughts about this.
 
Brecht Devos
 
 
TokenRegistry.sol:
 
/// @title Token Register Contract
/// @author Kongliang Zhong - <kongliang@loopring.org>,
/// @author Daniel Wang - <daniel@loopring.org>.
contract TokenRegistry is Ownable {
 
    mapping (string => address) tokenSymbolMap;
    mapping (address => bool) tokenAddressMap;
 
    function registerToken(address _token, string _symbol)
        public
        onlyOwner
    {
        require(_token != address(0));
        require(!isTokenRegisteredBySymbol(_symbol));
        require(!isTokenRegistered(_token));
        tokenSymbolMap[_symbol] = _token;
        tokenAddressMap[_token] = true;
    }
 
    function unregisterToken(address _token, string _symbol)
        public
        onlyOwner
    {
        require(tokenSymbolMap[_symbol] == _token);
        require(tokenAddressMap[_token] == true);
        delete tokenSymbolMap[_symbol];
        delete tokenAddressMap[_token];
    }
 
    function isTokenRegisteredBySymbol(string symbol)
        public
        constant
        returns (bool)
    {
        return tokenSymbolMap[symbol] != address(0);
    }
 
    function isTokenRegistered(address _token)
        public
        constant
        returns (bool)
    {
       return tokenAddressMap[_token];
    }
 
    function getAddressBySymbol(string symbol)
        public
        constant
        returns (address)
    {
        return tokenSymbolMap[symbol];
    }
 }

## #05 [TBD]

- From: Akash Bansal <akash.bansal2504@gmail.com>
- Time: 21:58 01/11/2017 Beijing Time
- PR: https://github.com/Loopring/protocol/pull/38

Description : Adding and removing loopring protocol Address in TokenTransferDelegate.sol in O(1)
I think this will reduce gas significantly.

Thanks.

## #06 [TBD]

- From: Brecht Devos <brechtp.devos@gmail.com>
- Time: 23:00 01/11/2017 Beijing Time
- PR: https://github.com/Loopring/protocol/pull/39

Hi,
 
Shouldn’t the return value of delegate.transferToken() be checked in settleRing()? Even if you’ve done some checks before, it still seems like a good idea to check the return value of the function because it seems like it could fail for multiple reasons. It’s also a very critical part of the codebase.
I haven’t thought that much yet if or how it could be abused, though I don’t see any reason not to check the return value.
 
Brecht Devos


## #07 [TBD]

- From: Akash Bansal <akash.bansal2504@gmail.com>
- Time: 01:57 03/11/2017 Beijing Time
- PR: https://github.com/Loopring/protocol/pull/41


## #07 [TBD]

- From: Brecht Devos <brechtp.devos@gmail.com>
- Time: 10:01 03/11/2017 Beijing Time
- PR: 

Hi,
 
Currently there are 2 storage fields for filled and cancelled separately. The code as is it works now does not need to have separate lists for both because they are only used added together like this:
uint amountB = order.amountB.sub(filled[state.orderHash]).tolerantSub(cancelled[state.orderHash]);
 
If the amount cancelled is simply added to filled the code would simply become:
uint amountB = order.amountB. tolerantSub (filled[state.orderHash]);
 
Of course this is only possible when future features don’t depend on having these separate.
 
In the 3 order test case this saves 3 SLOADs, which is currently about 0.25% in gas, which is pretty minor. Though it can also reduce future expensive SSTOREs (zero to non-zero) when either the filled or cancelled amount is already non-zero
(e.g. when the filled amount is already non-zero but the cancelled amount is still zero, cancelling an order would not bring about an expensive SSTORE to bring the cancelled amount to non-zero -> this would save 15000 gas).
 
Brecht Devos
