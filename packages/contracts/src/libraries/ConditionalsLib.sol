// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Action, PendingAction, GameStatus} from "./WhotLib.sol";

library ConditionalsLib {
    function eqs(Action a, Action b) internal pure returns (bool) {
        return a == b;
    }

    function eqs(PendingAction a, PendingAction b) internal pure returns (bool) {
        return a == b;
    }

    function eqs(GameStatus a, GameStatus b) internal pure returns (bool) {
        return a == b;
    }

    function eqs_or(Action a, Action b, Action c) internal pure returns (bool) {
        return a == b || a == c;
    }

    function eqs_or(PendingAction a, PendingAction b, PendingAction c)
        internal
        pure
        returns (bool)
    {
        return a == b || a == c;
    }

    function eqs_or(GameStatus a, GameStatus b, GameStatus c) internal pure returns (bool) {
        return a == b || a == c;
    }

    function not_eqs(Action a, Action b) internal pure returns (bool) {
        return a != b;
    }

    function not_eqs(PendingAction a, PendingAction b) internal pure returns (bool) {
        return a != b;
    }

    function not_eqs(GameStatus a, GameStatus b) internal pure returns (bool) {
        return a != b;
    }
}
