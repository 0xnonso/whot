// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {WhotCard} from "./WhotCard.sol";
import {GameData, GameStatus} from "../libraries/WhotLib.sol";

struct GameCache {
    address gameCreator;
    WhotCard callCard;
    uint8 playerTurnIndex;
    GameStatus status;
    uint40 lastMoveTimestamp;
    uint8 playersLeftToJoin;
    uint8 maxPlayers;
}

using GameCacheManager for GameCache global;

library GameCacheManager {
    function toMem(GameData storage gameData)
        internal
        view
        returns (GameCache memory $, uint256 slot)
    {
        assembly ("memory-safe") {
            slot := gameData.slot
        }
        return (toMem(slot), slot);
    }

    function toMem(uint256 slot) internal view returns (GameCache memory $) {
        assembly ("memory-safe") {
            let data := sload(slot)
            mstore($, and(data, 0xffffffffffffffff))
            mstore(add($, 32), and(shr(160, data), 0xff))
            mstore(add($, 64), and(shr(168, data), 0xff))
            mstore(add($, 96), and(shr(176, data), 0xff))
            mstore(add($, 128), and(shr(184, data), 0xffffffffff))
            mstore(add($, 160), and(shr(224, data), 0xff))
            mstore(add($, 192), shr(232, data))
        }
    }

    function toStorage(GameCache memory $, uint256 slot) internal {
        assembly ("memory-safe") {
            let data := mload($)
            data := or(shl(160, mload(add($, 32))), data)
            data := or(shl(168, mload(add($, 64))), data)
            data := or(shl(176, mload(add($, 96))), data)
            data := or(shl(184, mload(add($, 128))), data)
            data := or(shl(224, mload(add($, 160))), data)
            data := or(shl(232, mload(add($, 192))), data)
            sstore(slot, data)
        }
    }
}
