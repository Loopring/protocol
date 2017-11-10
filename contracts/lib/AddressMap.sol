pragma solidity 0.4.18;


/// @dev iterable address mapping
library AddressMapping {
    struct AddressMap {
        mapping(address => IndexValue) data;
        KeyFlag[] keys;
        uint size;
    }
    struct IndexValue { uint keyIndex; bytes32 value; }
    struct KeyFlag { address key; bool deleted; }

    function insert(AddressMap storage self, address key, bytes32 value)
    internal
    returns (bool replaced)
    {
        uint keyIndex = self.data[key].keyIndex;
        self.data[key].value = value;
        if (keyIndex > 0) {
            return true;
        } else {
            keyIndex = self.keys.length++;
            self.data[key].keyIndex = keyIndex + 1;
            self.keys[keyIndex].key = key;
            self.size++;
            return false;
        }
    }

    function remove(AddressMap storage self, address key)
    internal
    returns (bool success)
    {
        uint keyIndex = self.data[key].keyIndex;
        if (keyIndex == 0)
            return false;
        delete self.data[key];
        self.keys[keyIndex - 1].deleted = true;
        self.size --;
    }

    function contains(AddressMap storage self, address key)
    internal
    view
    returns (bool)
    {
        return self.data[key].keyIndex > 0;
    }

    function iterateStart(AddressMap storage self)
    internal
    view
    returns (uint keyIndex)
    {
        return iterateNext(self, uint(-1));
    }

    function iterateValid(AddressMap storage self, uint keyIndex)
    internal
    view
    returns (bool)
    {
        return keyIndex < self.keys.length;
    }

    function iterateNext(AddressMap storage self, uint keyIndex)
    internal
    view
    returns (uint rkeyIndex)
    {
        keyIndex++;
        while (keyIndex < self.keys.length && self.keys[keyIndex].deleted) {
            keyIndex++;
        }
        return keyIndex;
    }

    function iterateGet(AddressMap storage self, uint keyIndex)
    internal
    view
    returns (address key, bytes32 value)
    {
        key = self.keys[keyIndex].key;
        value = self.data[key].value;
    }
}