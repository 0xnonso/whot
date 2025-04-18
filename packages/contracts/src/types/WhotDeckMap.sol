// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

type WhotDeckMap is uint64;

using WhotDeckMapLib for WhotDeckMap global;

library WhotDeckMapLib {
    function isEmpty(WhotDeckMap deckMap, uint8 index) internal pure returns (bool) {
        return WhotDeckMap.unwrap(deckMap) & (1 << (index + 10)) == 0;
    }

    function isNotEmpty(WhotDeckMap deckMap, uint8 index) internal pure returns (bool) {
        return WhotDeckMap.unwrap(deckMap) & (1 << (index + 10)) != 0;
    }

    function isMapEmpty(WhotDeckMap deckMap) internal pure returns (bool) {
        return WhotDeckMap.unwrap(deckMap) == 0;
    }

    function isMapNotEmpty(WhotDeckMap deckMap) internal pure returns (bool) {
        return WhotDeckMap.unwrap(deckMap) != 0;
    }

    function len(WhotDeckMap deckMap) internal pure returns (uint256) {
        return WhotDeckMap.unwrap(deckMap) & 0x3FF;
    }

    function getNonEmptyIndexes(WhotDeckMap deckMap) internal pure returns (uint8[] memory) {
        uint8[] memory indexes = new uint8[](deckMap.len());
        uint256 currentIndex;
        uint256 _deckMap = WhotDeckMap.unwrap(deckMap);
        for (uint256 i; _deckMap != 0; _deckMap >> 1) {
            if (_deckMap & 1 != 0) {
                indexes[currentIndex++] = uint8(i);
            }
            unchecked {
                i++;
            }
        }
        return indexes;
    }

    function getNonEmptyIndexes(WhotDeckMap deckMap, uint8 amount)
        internal
        pure
        returns (uint8[] memory)
    {
        uint8[] memory indexes = new uint8[](amount);
        uint256 currentIndex;
        uint256 _deckMap = WhotDeckMap.unwrap(deckMap) >> 10;
        for (uint256 i = 0; _deckMap != 0; i++) {
            if (_deckMap & 1 != 0) {
                indexes[currentIndex++] = uint8(i);
            }
            _deckMap = _deckMap >> 1;
            if (amount == currentIndex) break;
        }

        return indexes;
    }

    function set(WhotDeckMap deckMap, uint8 index, bool empty)
        internal
        pure
        returns (WhotDeckMap)
    {
        if (index > 53) revert();
        uint256 rawMap = empty
            ? (WhotDeckMap.unwrap(deckMap) + 1) | (1 << (index + 10))
            : (WhotDeckMap.unwrap(deckMap) - 1) & ~(1 << (index + 10));

        return WhotDeckMap.wrap(uint64(rawMap));
    }

    function setToEmpty(WhotDeckMap deckMap, uint8 index) internal pure returns (WhotDeckMap) {
        if (deckMap.isEmpty(index)) revert();
        return deckMap.set(index, false);
    }

    function fill(WhotDeckMap deckMap, uint8 index) internal pure returns (WhotDeckMap) {
        if (deckMap.isNotEmpty(index)) revert();
        return set(deckMap, index, true);
    }

    function deal(WhotDeckMap marketDeckMap, WhotDeckMap playerDeckMap, uint8[] memory indexes)
        internal
        pure
        returns (WhotDeckMap, WhotDeckMap)
    {
        for (uint256 i; i < indexes.length; i++) {
            marketDeckMap = marketDeckMap.setToEmpty(indexes[i]);
            playerDeckMap = playerDeckMap.fill(indexes[i]);
        }
        return (marketDeckMap, playerDeckMap);
    }

    function deal(WhotDeckMap marketDeckMap, WhotDeckMap playerDeckMap)
        internal
        pure
        returns (WhotDeckMap, WhotDeckMap, uint8)
    {
        uint8 index = marketDeckMap.getNonEmptyIndexes(1)[0];

        marketDeckMap = marketDeckMap.setToEmpty(index);
        playerDeckMap = playerDeckMap.fill(index);

        return (marketDeckMap, playerDeckMap, index);
    }
}
