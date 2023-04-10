// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library ArrayForAddressUtils {

    function removeByIndex(address[] storage array, uint index) internal{
    	require(index < array.length, "ArrayForUint256: index out of bounds");

        for (uint i = index; i < array.length - 1; i++){
            array[i] = array[i + 1];
        }
        array.pop();
    }

    function removeByValue(address[] storage array, address value) internal{
        uint index;
        bool isIn;
        (isIn, index) = firstIndexOf(array, value);
        if(isIn){
          removeByIndex(array, index);
        }
    }
    
    function firstIndexOf(address[] storage array, address key) internal view returns (bool, uint256) {

    	if(array.length == 0){
    		return (false, 0);
    	}

    	for(uint256 i = 0; i < array.length; i++){
    		if(array[i] == key){
    			return (true, i);
    		}
    	}
    	return (false, 0);
    }

    function ModifyValue(address[] storage array, address oldValue, address newValue) internal {
        uint index;
        bool isIn;
        (isIn, index) = firstIndexOf(array, oldValue);
        if(isIn){
            array[index] = newValue;
        }
    }

}