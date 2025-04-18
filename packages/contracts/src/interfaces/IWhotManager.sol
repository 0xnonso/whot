// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Action} from "../libraries/WhotLib.sol";

interface IWhotManager {
    function isWhotManager() external view returns (bool);

    // callabck
    function onJoinGame(uint256 gameID, address player, bytes memory extraData) external;
    function onExecuteMove(uint256 gameID, uint256 playerIndex, Action action) external;
    function onEndGame(uint256 gameID) external;

    function hasSpecialMoves(uint256 gameID, uint256 currentIndex, bytes memory extraData)
        external
        view
        returns (bool);
}
