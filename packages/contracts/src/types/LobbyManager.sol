// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

struct Tournament {
    uint40 startTime;
    uint8 rounds;
    uint16 maxParticipants;
}

struct Lobby {
    uint256[4] players;
    mapping(address => bool) joined;
}

using LobbyManager for Lobby global;

library LobbyManager {
    function setUpLobby(Lobby storage lobby, Tournament memory tournamentData) internal {}

    function addParticipant(Lobby storage lobby, address player) internal {
        uint8 nextFreeIndex = uint8((lobby.players[0] >> 248));

        assembly {
            sstore(add(lobby.slot, mul(0x10, nextFreeIndex)), player)
        }
    }

    function getLobbyPlayers(Lobby storage lobby) internal returns (address[] memory) {
        uint256 player1_Slot = lobby.players[0];
        uint256 numPlayers = player1_Slot >> 248;
        address[] memory players = new address[](numPlayers);

        if (numPlayers == 0) {
            return players;
        }

        players[0] = address(uint160(player1_Slot));

        for (uint256 i = 1; i < numPlayers; i++) {
            players[i] = address(uint160(lobby.players[i]));
        }
    }

    function reset(Lobby storage lobby) internal {}
}
