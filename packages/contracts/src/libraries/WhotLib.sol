// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";

import {WhotCard, WhotCardLib} from "../types/WhotCard.sol";
import {WhotDeckMap, WhotDeckMapLib} from "../types/WhotDeckMap.sol";

enum Action {
    Play,
    Defend,
    GoToMarket,
    Pick
}

enum PendingAction {
    None,
    PickTwo,
    PickThree,
    PickFour
}

enum GameStatus {
    None,
    Started,
    Ended
}

struct PlayerData {
    address playerAddr;
    WhotDeckMap deckMap;
    PendingAction pAction;
    bool isActive;
    uint16 score;
    euint256[2] whotCardDeck;
}

struct GameData {
    address gameCreator;
    WhotCard callCard;
    uint8 playerTurnIndex;
    GameStatus status;
    uint40 lastMoveTimestamp;
    uint8 playersLeftToJoin;
    uint8 maxPlayers;
    euint256[2] marketDeck;
    WhotDeckMap marketDeckMap;
    // uint8 indexMap
    // WhotDeck marketDeck;
    PlayerData[] players;
    address[] proposedPlayers;
    // mapping(address => bool) isActive;
    // mapping(address => uint32) score;
    // Todo: might remove.
    // Allows for easier retrieval of player's data index;
    mapping(address => uint256) playerIndex;
}

using WhotLib for GameData global;
using WhotLib for PlayerData global;

library WhotLib {
    using TFHE for *;

    uint16 constant MAX_UINT16 = type(uint16).max;
    uint64 constant INITIAL_MARKET_DECK_MAP = 0xfffffffffffffc36;
    uint256 constant INITIAL_HAND_SIZE = 6;

    function isActive(GameData storage $) internal view returns (bool) {
        uint256 playerIndex = $.playerIndex[msg.sender];
        if (playerIndex == 0 && $.players.length == 0) {
            return false;
        }
        PlayerData memory player = $.players[playerIndex];
        return player.playerAddr == msg.sender && player.isActive;
    }

    function getPlayerIndex(GameData storage $, address player) internal view returns (uint256) {
        // uint256 index = $.playerIndex[msg.sender];
        // return $.players[index].playerAddr == msg.sender;
        return $.playerIndex[player];
    }

    function isProposedPlayer(GameData storage $) internal view returns (bool _isProposedPlayer) {
        address[] memory proposedPlayers = $.proposedPlayers;
        for (uint256 i; i < proposedPlayers.length; i++) {
            if (proposedPlayers[i] == msg.sender) {
                _isProposedPlayer = true;
                break;
            }
        }
    }

    function shufflePlayers(GameData storage $) internal {
        // get random number.
        uint256 rand = block.prevrandao;

        uint256 lastIndex = $.players.length - 1;
        uint256 randIndex;
        while (lastIndex != 0) {
            randIndex = rand % lastIndex;
            PlayerData memory temp1 = $.players[randIndex];
            PlayerData memory temp2 = $.players[lastIndex];

            $.players[randIndex] = temp2;
            $.playerIndex[temp2.playerAddr] = randIndex;
            $.players[lastIndex] = temp1;
            $.playerIndex[temp1.playerAddr] = lastIndex;
            lastIndex--;
        }
    }

    function turn(GameData storage $, uint256 index) internal view returns (bool) {
        return $.players[index].playerAddr == msg.sender;
    }

    function turn(PlayerData memory pData) internal view returns (bool) {
        return pData.playerAddr == msg.sender;
    }

    function setPlayerScoreToMin(GameData storage $, uint256 index) internal {
        $.setPlayerScore(index, MAX_UINT16);
    }

    function setPlayerScore(GameData storage $, uint256 index, uint16 score) internal {
        $.players[index].score = score;
    }

    function deactivatePlayer(GameData storage $, uint256 index) internal {
        $.players[index].isActive = false;
    }

    function calculatePlayerScore(GameData storage $, uint256 index) internal returns (euint16) {
        PlayerData memory player = $.players[index];
        WhotDeckMap playerDeckMap = player.deckMap;
        uint8[] memory cardIndexes = playerDeckMap.getNonEmptyIndexes();
        euint256[2] memory marketDeck = $.marketDeck;
        euint16 total = TFHE.asEuint16(0);
        for (uint256 i; i < cardIndexes.length; i++) {
            uint256 marketDeckIndex = cardIndexes[i] % 32;
            total =
                total.add(marketDeck[marketDeckIndex].shr(cardIndexes[i] * 8).and(0xff).asEuint16());
        }
        TFHE.allowThis(total);
        return total;
    }

    function getCardToCommit(GameData storage $, PlayerData memory player, uint8 cardIndex)
        internal
        returns (euint8)
    {
        if (cardIndex > 53) revert();
        WhotDeckMap marketDeckMap = $.marketDeckMap;
        if (marketDeckMap.isNotEmpty(cardIndex)) {
            revert("MarketDeckMap: Index is not empty");
        }
        if (player.deckMap.isEmpty(cardIndex)) {
            revert("PlayerDeckMap: Index is empty");
        }
        euint256 marketDeck = $.marketDeck[cardIndex / 32];
        euint8 cardToCommit = marketDeck.shr(cardIndex * 8).and(0xff).asEuint8();
        TFHE.allowThis(cardToCommit);
        return cardToCommit;
    }

    function addPlayer(GameData storage $, address player) internal {
        PlayerData memory pData;
        pData.playerAddr = player;
        pData.isActive = true;

        pData.whotCardDeck[0] = TFHE.asEuint256(0);
        pData.whotCardDeck[1] = TFHE.asEuint256(0);

        TFHE.allow(pData.whotCardDeck[0], player);
        TFHE.allowThis(pData.whotCardDeck[0]);
        TFHE.allow(pData.whotCardDeck[1], player);
        TFHE.allowThis(pData.whotCardDeck[1]);

        uint256 playerIndex = $.players.length;
        $.players.push(pData);
        $.playerIndex[pData.playerAddr] = playerIndex;
    }

    function nextIndex(GameData storage $, uint256 currentIndex) internal view returns (uint256) {
        uint256 total = $.players.length;
        uint256 _nextIndex = (currentIndex + 1) % total;
        while (!$.players[_nextIndex].isActive) {
            _nextIndex = (_nextIndex + 1) % total;
        }
        return _nextIndex;
    }

    function nextNextIndex(GameData storage $, uint256 currentIndex)
        internal
        view
        returns (uint256)
    {
        PlayerData[] memory players = $.players;
        uint256 activeTotal;
        for (uint256 i; i < players.length; i++) {
            if (players[i].isActive) {
                activeTotal++;
            }
        }
        if (activeTotal == 2) {
            return currentIndex;
        }
        uint256 total = players.length;
        uint256 _nextIndex = (currentIndex + 2) % total;
        while (!players[_nextIndex].isActive) {
            _nextIndex = (_nextIndex + 1) % total;
        }
        return _nextIndex;
    }

    function initalizeMarketDeckMap(GameData storage $) internal {
        $.marketDeckMap = WhotDeckMap.wrap(INITIAL_MARKET_DECK_MAP);
    }

    function dealInitialHand(
        GameData storage $,
        PlayerData memory player,
        uint8 index,
        uint8 numPlayers
    ) internal {
        uint8[] memory indexes = new uint8[](INITIAL_HAND_SIZE);
        indexes[0] = index;
        indexes[1] = index + numPlayers;
        indexes[2] = index + (2 * numPlayers);
        indexes[3] = index + (3 * numPlayers);
        indexes[4] = index + (4 * numPlayers);
        indexes[5] = index + (5 * numPlayers);

        WhotDeckMap marketDeckMap = $.marketDeckMap;
        ($.marketDeckMap, $.players[index].deckMap) = marketDeckMap.deal(player.deckMap, indexes);

        euint256[2] memory marketDeck = $.marketDeck;

        uint256 i = indexes[0] / 32;
        uint256 mask = 0xff << ((indexes[0] % 32) * 8);
        player.whotCardDeck[i] = player.whotCardDeck[i].or(marketDeck[i].and(mask));
        i = indexes[1] / 32;
        mask = 0xff << ((indexes[1] % 32) * 8);
        player.whotCardDeck[i] = player.whotCardDeck[i].or(marketDeck[i].and(mask));
        i = indexes[2] / 32;
        mask = 0xff << ((indexes[2] % 32) * 8);
        player.whotCardDeck[i] = player.whotCardDeck[i].or(marketDeck[i].and(mask));
        i = indexes[3] / 32;
        mask = 0xff << ((indexes[3] % 32) * 8);
        player.whotCardDeck[i] = player.whotCardDeck[i].or(marketDeck[i].and(mask));
        i = indexes[4] / 32;
        mask = 0xff << ((indexes[4] % 32) * 8);
        player.whotCardDeck[i] = player.whotCardDeck[i].or(marketDeck[i].and(mask));
        i = indexes[5] / 32;
        mask = 0xff << ((indexes[5] % 32) * 8);
        player.whotCardDeck[i] = player.whotCardDeck[i].or(marketDeck[i].and(mask));

        $.players[index].whotCardDeck[0] = player.whotCardDeck[0];
        TFHE.allow(player.whotCardDeck[0], player.playerAddr);
        TFHE.allowThis(player.whotCardDeck[0]);

        if (i > 32) {
            $.players[index].whotCardDeck[1] = player.whotCardDeck[1];
            TFHE.allow(player.whotCardDeck[1], player.playerAddr);
            TFHE.allowThis(player.whotCardDeck[1]);
        }
    }

    function deal(GameData storage $, PlayerData memory player, uint256 currentIndex) internal {
        WhotDeckMap marketDeckMap = $.marketDeckMap;

        if (marketDeckMap.isMapNotEmpty()) {
            uint8 cardIndex;
            ($.marketDeckMap, $.players[currentIndex].deckMap, cardIndex) =
                marketDeckMap.deal(player.deckMap);
            uint256 i = cardIndex / 32;
            euint256 marketDeck = $.marketDeck[i];
            uint256 mask = 0xff << ((cardIndex % 32) * 8);
            euint256 updatedWhotCardDeck = player.whotCardDeck[i].or(marketDeck.and(mask));
            $.players[currentIndex].whotCardDeck[i] = updatedWhotCardDeck;
            TFHE.allow(updatedWhotCardDeck, player.playerAddr);
            TFHE.allowThis(updatedWhotCardDeck);
        }
    }

    function dealPickTwo(GameData storage $, PlayerData memory player, uint256 currentIndex)
        internal
    {
        dealPickN($, player, currentIndex, 2);
    }

    function dealPickThree(GameData storage $, PlayerData memory player, uint256 currentIndex)
        internal
    {
        dealPickN($, player, currentIndex, 3);
    }

    function dealPickFour(GameData storage $, PlayerData memory player, uint256 currentIndex)
        internal
    {
        dealPickN($, player, currentIndex, 4);
    }

    function dealPickN(
        GameData storage $,
        PlayerData memory player,
        uint256 currentIndex,
        uint256 n
    ) private {
        WhotDeckMap marketDeckMap = $.marketDeckMap;
        euint256[2] memory marketDeck = $.marketDeck;

        uint256 mask;
        uint8 cardIndex;
        uint8 k;
        uint8 allowBothIndex;

        (marketDeckMap, player.deckMap, cardIndex) = marketDeckMap.deal(player.deckMap);
        k = cardIndex / 32;
        mask = 0xff << ((cardIndex % 32) * 8);
        player.whotCardDeck[k] = player.whotCardDeck[k].or(marketDeck[k].and(mask));

        for (uint256 i; i < n - 1; i++) {
            uint8 j;
            if (marketDeckMap.isMapNotEmpty()) {
                (marketDeckMap, player.deckMap, cardIndex) = marketDeckMap.deal(player.deckMap);
                j = cardIndex / 32;
                mask = 0xff << ((cardIndex % 32) * 8);
                player.whotCardDeck[j] = player.whotCardDeck[j].or(marketDeck[j].and(mask));
            }
            allowBothIndex = k ^ j;
            k = j;
        }

        if (k > 32 && allowBothIndex == 0) {
            $.players[currentIndex].whotCardDeck[1] = player.whotCardDeck[1];
            TFHE.allow(player.whotCardDeck[1], player.playerAddr);
            TFHE.allowThis(player.whotCardDeck[1]);
        } else if (allowBothIndex != 0) {
            $.players[currentIndex].whotCardDeck[0] = player.whotCardDeck[0];
            TFHE.allow(player.whotCardDeck[0], player.playerAddr);
            TFHE.allowThis(player.whotCardDeck[0]);

            $.players[currentIndex].whotCardDeck[1] = player.whotCardDeck[1];
            TFHE.allow(player.whotCardDeck[1], player.playerAddr);
            TFHE.allowThis(player.whotCardDeck[1]);
        } else {
            $.players[currentIndex].whotCardDeck[0] = player.whotCardDeck[0];
            TFHE.allow(player.whotCardDeck[0], player.playerAddr);
            TFHE.allowThis(player.whotCardDeck[0]);
        }

        $.players[currentIndex].deckMap = player.deckMap;
        $.marketDeckMap = marketDeckMap;
    }

    function dealGeneralMarket(GameData storage $, uint256 currentIndex) internal {
        PlayerData[] memory players = $.players;
        WhotDeckMap marketDeckMap = $.marketDeckMap;
        euint256[2] memory marketDeck = $.marketDeck;

        for (uint256 i; i < players.length; i++) {
            if (marketDeckMap.isMapNotEmpty() && i != currentIndex && players[i].isActive) {
                uint8 cardIndex;
                (marketDeckMap, $.players[i].deckMap, cardIndex) =
                    marketDeckMap.deal(players[i].deckMap);

                uint8 deckIndex = cardIndex / 32;
                uint256 mask = 0xff << ((cardIndex % 32) * 8);

                euint256 updatedWhotCardDeck =
                    players[i].whotCardDeck[deckIndex].or(marketDeck[deckIndex].and(mask));

                TFHE.allow(updatedWhotCardDeck, players[i].playerAddr);
                TFHE.allowThis(updatedWhotCardDeck);
                $.players[i].whotCardDeck[deckIndex] = updatedWhotCardDeck;
            }
        }

        $.marketDeckMap = marketDeckMap;
    }
}
