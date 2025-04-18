// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IWhotManager} from "../interfaces/IWhotManager.sol";
import {Lobby} from "../types/LobbyManager.sol";
import {Action} from "../libraries/WhotLib.sol";
import {Whot} from "../Whot.sol";

contract WhotLeaderboardV1 is IWhotManager {
    address public immutable gameMaster;
    Whot public whot;

    Lobby lobby;

    event WhotGameSet(Whot _whot);

    // function canBootOut(uint256 gameID, address player) external override {}

    modifier onlyGameMaster() {
        require(msg.sender == gameMaster, "Only Game Master");
        _;
    }

    function setWhotGame(Whot _whot) public onlyGameMaster {
        whot = _whot;
        emit WhotGameSet(_whot);
    }

    function register() external {}

    function createWhotTournament() external onlyGameMaster {}

    function hasSpecialMoves(uint256 gameID, uint256 currentIndex, bytes memory extraData)
        external
        view
        virtual
        override
        returns (bool)
    {}

    function onExecuteMove(uint256 gameID, uint256 playerIndex, Action action)
        external
        virtual
        override
    {}

    function onJoinGame(uint256 gameID, address player, bytes memory extraData)
        external
        virtual
        override
    {}

    function onEndGame(uint256 gameID) external virtual override {}

    function isWhotManager() external view virtual override returns (bool) {
        return true;
    }
}
