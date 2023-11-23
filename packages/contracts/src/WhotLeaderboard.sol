// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {IWhotManager} from "./interfaces/IWhotManager.sol";
import {Whot} from "./Whot.sol";

contract WhotLeaderboard is IWhotManager {
    Whot whotGame;

    event WhotGameSet(Whot prev, Whot current);

    function canBootOut() external override {}

    function setWhotGame(Whot _whot) external {
        whotGame = _whot;
        emit WhotGameSet(whotGame, _whot);
    }
}