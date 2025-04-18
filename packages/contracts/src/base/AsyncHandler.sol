// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "fhevm/config/ZamaFHEVMConfig.sol";
import "fhevm/config/ZamaGatewayConfig.sol";
import "fhevm/gateway/GatewayCaller.sol";
import "fhevm/lib/TFHE.sol";

import {CardShape} from "../types/WhotCard.sol";
import {Action} from "../libraries/WhotLib.sol";

abstract contract AsyncHandler is
    SepoliaZamaFHEVMConfig,
    SepoliaZamaGatewayConfig,
    GatewayCaller
{
    using TFHE for *;

    uint256 immutable MAX_CALLBACK_DELAY;

    mapping(uint256 requestID => CommittedCard) private gatewayRequestToCommittedMove;
    mapping(uint256 gameID => uint256 requestID) private committedMoveToGatewayRequest;
    mapping(uint256 requestID => ScoreDecryptData) private gatewayRequestToCommittedScore;

    struct CommittedCard {
        Action action;
        uint40 timestamp;
        uint8 playerIndex;
        CardShape wishShape;
        euint8 card;
        uint256 gameID;
        bytes extraData;
    }

    struct ScoreDecryptData {
        uint256 gameID;
        uint256[] playerIndexes;
    }

    constructor(uint256 _maxCallbackDelay) {
        MAX_CALLBACK_DELAY = _maxCallbackDelay;
    }

    function _commitMove(
        uint256 gameID,
        euint8 cardToCommit,
        Action action,
        CardShape wishShape,
        uint256 index
    ) internal {
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(cardToCommit);

        uint256 reqID = Gateway.requestDecryption(
            cts, this.handleCommitMove.selector, 0, block.timestamp + MAX_CALLBACK_DELAY, false
        );

        CommittedCard memory cc;
        cc.gameID = gameID;
        cc.card = cardToCommit;
        cc.timestamp = uint40(block.timestamp);
        cc.playerIndex = uint8(index);
        cc.action = action;
        cc.wishShape = wishShape;

        gatewayRequestToCommittedMove[reqID] = cc;
        committedMoveToGatewayRequest[gameID] = reqID;
    }

    function _commitScore(uint256 gameID, euint128 totals, uint256[] memory playerIndexes)
        internal
    {
        uint256[] memory cts = new uint256[](1);
        cts[0] = Gateway.toUint256(totals);

        uint256 reqID = Gateway.requestDecryption(
            cts, this.handleCommitScore.selector, 0, block.timestamp + MAX_CALLBACK_DELAY, false
        );

        ScoreDecryptData memory scoreDecryptData;
        scoreDecryptData.gameID = gameID;
        scoreDecryptData.playerIndexes = playerIndexes;

        gatewayRequestToCommittedScore[reqID] = scoreDecryptData;
    }

    function getCommittedMove(uint256 reqID) internal view returns (CommittedCard memory) {
        return gatewayRequestToCommittedMove[reqID];
    }

    function getCommittedScoreData(uint256 reqID) internal view returns (ScoreDecryptData memory) {
        return gatewayRequestToCommittedScore[reqID];
    }

    function hasCommittedAction(uint256 gameID) internal view returns (bool) {
        return committedMoveToGatewayRequest[gameID] != 0;
    }

    function clearMoveCommitment(uint256 gameID) internal {
        committedMoveToGatewayRequest[gameID] = 0;
    }

    function handleCommitMove(uint256 requestID, uint8 card) external virtual;
    function handleCommitScore(uint256 requestID, uint128 total) external virtual;
}
