// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "fhevm/lib/TFHE.sol";
import {AsyncHandler} from "./base/AsyncHandler.sol";
import {IWhotManager} from "./interfaces/IWhotManager.sol";
import {
    GameData,
    PlayerData,
    Action,
    PendingAction,
    GameStatus,
    WhotLib
} from "./libraries/WhotLib.sol";
import {ConditionalsLib} from "./libraries/ConditionalsLib.sol";
import {GameCache, GameCacheManager} from "./types/GameCache.sol";
import {CardShape, WhotCard, WhotCardLib} from "./types/WhotCard.sol";
import {WhotDeckMap, WhotDeckMapLib} from "./types/WhotDeckMap.sol";
import {TrustedShuffleService as TSS} from "./TrustedShuffleService.sol";

contract Whot is AsyncHandler {
    using TFHE for *;
    using ConditionalsLib for *;

    uint256 constant DEFAULT_MAX_DELAY = 7 minutes;
    // uint256 constant MAX_UINT32 = type(uint32).max;
    // Max number of players in a whot game.
    uint256 constant MAX_PLAYERS = 6;
    // Starting hand size for all players

    TSS internal tss;

    // game ID
    uint256 internal whotGameID = 1;

    // Whot Game Data.
    mapping(uint256 gameID => GameData) internal whotGame;

    // ERRORS
    // Player is  trying to join a game that they already joined.
    error PlayerAlreadyInGame();
    // Caller is  trying to join a game that has already started.
    error GameAlreadyStarted();
    // Caller is trying to join a game that has not started yet.
    error GameNotStarted();
    // Can only play or execute move when its player's turn.
    error NotPlayerTurn();
    // Player cannot make any move that doesn't resolve a pending action.
    // i.e If player's pending action is to pick 2, then player can only defend or pick.
    error ResolvePendingAction();
    // Card played does not match call card or is not special WHOT card.
    error WrongWhotCard();
    // Some moves can only be made to resolve a pending action thus if no pending action they cant be made.
    // i.e If a player's pending action is none then the player cant defend or pick.
    error NoPendingAction();
    // Defense is not enabled.
    error DefenseNotEnabled();
    // // If call card is WHOT card, any card played must match its wish card.
    // error WrongWishCard();
    // // Player is not active.
    // error PlayerNotActive();
    // Player not proposed by game creator.
    error NotProposedPlayer();
    // Game cant be started.
    error CannotStartGame();
    // Max player limit exceeded
    error PlayersLimitExceeded();
    error PlayersLimitNotMet();
    // // Caller is not part of game
    // error PlayerNotInGame(address player);
    // // Card not committed or decrypted.
    // error WhotCardNotReady();
    error CannotBootOutPlayer(address player);
    error InvalidGameAction(Action action);
    error PlayerAlreadyCommittedAction();

    //EVENTS
    // A player forfeited or was booted out by the whot manager.
    event PlayerForfeited(uint256 indexed gameID, uint256 playerIndex);
    // A player joined a game.
    event PlayerJoined(uint256 indexed gameID, address player);
    event PlayerPickTwo(uint256 indexed gameID, uint256 playerIndex, PendingAction action);
    event PlayerPickThree(uint256 indexed gameID, uint256 playerIndex);
    // A player executed a move - Action{..}
    event MoveExecuted(uint256 indexed gameID, uint256 pTurnIndex, Action action);
    // A player will miss their turn.
    event PlayerSuspended(uint256 indexed gameID, uint256 pTurnIndexSuspended);
    event PendingActionFulfilled(uint256 indexed gameID, uint256 playerIndex, PendingAction action);
    // // All players will  miss their next turn.
    event GameSuspended(uint256 indexed gameID, uint256 currentPlayerIndex);
    // All players deck will be dealt with an extra card.
    event GeneralMarket(uint256 indexed gameID, uint256 playerIndex);
    // New Whot game created.
    event GameCreated(uint256 indexed gameID, address gameCreator);
    // Whot game started.
    event GameStarted(uint256 indexed gameID);
    // Whot game ended.
    event GameEnded(uint256 indexed gameID);
    // // Card decrypted.
    // event CardDecrypted(uint256 indexed requestID, WhotCard card);

    event GameActionFailedWithError(uint256 indexed gameID, uint256 pTurnIndex, bytes4 errMsg);

    constructor(address _tss, uint256 _maxCallbackDelay) AsyncHandler(_maxCallbackDelay) {
        tss = TSS(_tss);
    }

    // Create whot game with max number of players.
    // To enable whot manager, caller has to be a smart cntract that implements `IWhotManager`
    // If array length greater than zero, then only addresses in the array can join the game.
    // If array is empty, then any participants as much as `maxPlayers` can join the game.
    function createGame(
        bytes32[] calldata proof,
        einput[2] calldata leaf,
        bytes calldata inputProof,
        uint256 shuffledCardDeckRootIndex,
        address[] calldata proposedPlayers,
        uint256 maxPlayers
    ) public returns (uint256 gameID) {
        gameID = whotGameID;
        GameData storage game = whotGame[gameID];
        // Create new market deck and shuffle.
        tss.verifyAndUseShuffledCardDeck(proof, leaf, shuffledCardDeckRootIndex);

        euint256 marketDeck_0 = TFHE.asEuint256(leaf[0], inputProof);
        game.marketDeck[0] = marketDeck_0;

        euint256 marketDeck_1 = TFHE.asEuint256(leaf[1], inputProof);
        game.marketDeck[1] = marketDeck_1;

        TFHE.allowThis(marketDeck_0);
        TFHE.allowThis(marketDeck_1);

        game.initalizeMarketDeckMap();
        game.proposedPlayers = proposedPlayers;
        game.gameCreator = msg.sender;

        maxPlayers = proposedPlayers.length != 0 ? proposedPlayers.length : maxPlayers;

        if (maxPlayers > MAX_PLAYERS) revert PlayersLimitExceeded();
        if (maxPlayers < 2) revert PlayersLimitNotMet();

        game.maxPlayers = uint8(maxPlayers);
        game.playersLeftToJoin = uint8(maxPlayers);

        unchecked {
            whotGameID++;
        }

        emit GameCreated(gameID, game.gameCreator);
    }

    // // Allows game creator to create and participate in a game.
    // function createAndJoinGame(
    //     bytes32[] calldata proof,
    //     einput[2] calldata leaf,
    //     bytes[2] calldata inputProof,
    //     uint256 shuffledCardDeckRootIndex,
    //     address[] calldata proposedPlayers,
    //     uint256 maxPlayers,
    //     bytes calldata extraData
    // ) external returns (uint256 gameID) {
    //     gameID = createGame(
    //         proof, leaf, inputProof, shuffledCardDeckRootIndex, proposedPlayers, maxPlayers
    //     );
    //     joinGame(gameID, extraData);
    // }

    // Joins whot game if game hasn't already started.
    // Can only join game if player is a proposed player (proposed players has to be set)
    // or max players limit has not being reached.
    function joinGame(uint256 gameID, bytes calldata extraData) public {
        GameData storage game = whotGame[gameID];

        (GameCache memory g, uint256 slot) = GameCacheManager.toMem(game);

        if (!g.status.eqs(GameStatus.None)) revert GameAlreadyStarted();

        address playerToAdd = msg.sender;

        if (game.isActive()) revert PlayerAlreadyInGame();

        bool isProposedPlayer =
            game.proposedPlayers.length != 0 ? game.isProposedPlayer() : g.playersLeftToJoin != 0;

        if (isProposedPlayer) {
            g.playersLeftToJoin--;
            game.addPlayer(playerToAdd);
        } else {
            revert NotProposedPlayer();
        }

        g.toStorage(slot);

        // _onJoinGame(gameID, g.gameCreator, playerToAdd, extraData);

        emit PlayerJoined(gameID, playerToAdd);
    }

    /// Start a whot game.
    function startGame(uint256 gameID) external {
        GameData storage game = whotGame[gameID];
        PlayerData[] memory players = game.players;

        (GameCache memory g, uint256 slot) = GameCacheManager.toMem(game);

        uint256 playersLeftToJoin = g.playersLeftToJoin;
        uint256 joined = g.maxPlayers - playersLeftToJoin;
        address gameCreator = g.gameCreator;
        bool canStartGame;

        assembly ("memory-safe") {
            let isGameCreator := eq(caller(), gameCreator)
            canStartGame := or(iszero(playersLeftToJoin), and(isGameCreator, gt(joined, 1)))
        }

        if (canStartGame) {
            for (uint256 i = 0; i < players.length; i++) {
                PlayerData memory player = players[i];
                game.setPlayerScoreToMin(i);
                game.dealInitialHand(player, uint8(i), uint8(joined));
            }
        } else {
            revert CannotStartGame();
        }

        g.status = GameStatus.Started;
        g.toStorage(slot);

        // shuffle players array.
        // First player's move is not constrained so might give them slight advantages.
        // game.shufflePlayers();
        emit GameStarted(gameID);
    }

    function commitMove(uint256 gameID, Action action, uint8 cardIndex, CardShape wish) external {
        if (hasCommittedAction(gameID)) revert PlayerAlreadyCommittedAction();
        GameData storage game = whotGame[gameID];
        (GameCache memory g,) = GameCacheManager.toMem(game);
        if (!g.status.eqs(GameStatus.Started)) revert GameNotStarted();
        // if action not play or defend revert!!!

        uint256 currentTurnIndex = g.playerTurnIndex;
        PlayerData memory player = game.players[currentTurnIndex];

        if (!player.turn()) revert NotPlayerTurn();
        if (!action.eqs_or(Action.Play, Action.Defend)) {
            revert InvalidGameAction(action);
        }

        euint8 cardToCommit = game.getCardToCommit(player, cardIndex);

        _commitMove(gameID, cardToCommit, action, wish, currentTurnIndex);
    }

    // Execute player's move.
    function executeMove(uint256 gameID, Action action) external {
        GameData storage game = whotGame[gameID];
        (GameCache memory g,) = GameCacheManager.toMem(game);
        // check if committed card is ready and ensure it is the player's turn.
        if (!g.status.eqs(GameStatus.Started)) revert GameNotStarted();

        PlayerData memory player = game.players[g.playerTurnIndex];
        if (!player.turn()) revert NotPlayerTurn();

        if (hasCommittedAction(gameID)) revert PlayerAlreadyCommittedAction();

        if (action.eqs(Action.GoToMarket)) {
            goToMarket(gameID, game, g.playerTurnIndex);
        } else if (action.eqs(Action.Pick)) {
            pick(gameID, game, g.playerTurnIndex);
        } else {
            revert InvalidGameAction(action);
        }

        // _onExecuteMove(gameID, g.gameCreator, g.playerTurnIndex, action);

        finish(gameID, game, false);
    }

    function handleCommitMove(uint256 requestID, uint8 card)
        external
        virtual
        override
        onlyGateway
    {
        // revert("Not implemented");
        CommittedCard memory cc = getCommittedMove(requestID);
        GameData storage game = whotGame[cc.gameID];

        WhotCard whotCard = WhotCardLib.toWhotCard(card);
        if (whotCard.iWish()) whotCard = WhotCardLib.makeWhotWish(cc.wishShape);

        (bool err, bytes4 errMsg) = cc.action.eqs(Action.Play)
            ? play(cc.gameID, game, WhotCardLib.toWhotCard(card), cc.extraData)
            : defend(cc.gameID, game, WhotCardLib.toWhotCard(card), cc.extraData);

        if (err) {
            emit GameActionFailedWithError(cc.gameID, cc.playerIndex, errMsg);
        }

        // if (err) _forfeit(cc.gameID, game, cc.playerIndex);
        finish(cc.gameID, game, false);
        clearMoveCommitment(cc.gameID);
    }

    function handleCommitScore(uint256 requestID, uint128 total)
        external
        virtual
        override
        onlyGateway
    {
        ScoreDecryptData memory sdd = getCommittedScoreData(requestID);
        GameData storage game = whotGame[sdd.gameID];

        for (uint256 i; i < sdd.playerIndexes.length; i++) {
            game.setPlayerScore(
                sdd.playerIndexes[i], uint16((total >> (sdd.playerIndexes[i] * 16)))
            );
        }

        _onEndGame(sdd.gameID, game.gameCreator);
    }

    /// Fails silently. Might be an anti patern? Todo(nonso): fix?
    function finish(uint256 gameID, GameData storage game, bool force) internal {
        PlayerData[] memory players = game.players;
        uint256 activePlayers;
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i].isActive) activePlayers++;
        }
        uint256 currentTurnIndex = game.playerTurnIndex;
        PlayerData memory player = players[currentTurnIndex];
        bool canFinish = game.marketDeckMap.isMapEmpty() || player.deckMap.isMapEmpty()
            || activePlayers == 1 || force;
        if (canFinish) {
            _calculatePlayersScore(gameID, game, players, activePlayers);
            game.status = GameStatus.Ended;
            emit GameEnded(gameID);
        }
    }

    // Forfeit whot game.
    function forfeit(uint256 gameID) external {
        GameData storage game = whotGame[gameID];
        if (!game.status.eqs(GameStatus.Started)) revert GameNotStarted();
        uint256 index = game.getPlayerIndex(msg.sender);
        _forfeit(gameID, game, index);
        finish(gameID, game, false);
    }

    // Allows whot manager to remove player from game.
    function bootOut(uint256 gameID) external {
        GameData storage game = whotGame[gameID];
        (GameCache memory g,) = GameCacheManager.toMem(game);

        if (!g.status.eqs(GameStatus.Started)) revert GameNotStarted();

        uint256 index = g.playerTurnIndex;
        address player = game.players[index].playerAddr;

        if ((g.lastMoveTimestamp + DEFAULT_MAX_DELAY) > block.timestamp) {
            revert CannotBootOutPlayer(player);
        }

        _forfeit(gameID, game, index);
        finish(gameID, game, false);
    }

    function _forfeit(uint256 gameID, GameData storage game, uint256 index) internal {
        game.deactivatePlayer(index);
        if (game.playerTurnIndex == index) {
            game.playerTurnIndex = uint8(game.nextIndex(index));
        }

        emit PlayerForfeited(gameID, index);
    }

    // Play whot card.
    // cc.gameID, game, cc.card.toWhotCard(), cc.cardIndex
    function play(uint256 gameID, GameData storage game, WhotCard card, bytes memory extraData)
        internal
        returns (bool err, bytes4 errMsg)
    {
        (GameCache memory g, uint256 slot) = GameCacheManager.toMem(game);
        uint256 currentIndex = g.playerTurnIndex;
        WhotCard callCard = g.callCard;

        PlayerData memory player = game.players[currentIndex];
        if (player.pAction.not_eqs(PendingAction.None)) {
            (err, errMsg) = (true, ResolvePendingAction.selector); //revert ResolvePendingAction();
            return (err, errMsg);
        }

        // iWishCard has desired card shape in the body.
        // while the number is in the upper part.
        if (!callCard.matchWhot(card)) {
            (err, errMsg) = (true, WrongWhotCard.selector); //revert WrongWhotCard();
            return (err, errMsg);
        }

        if (card.generalMarket()) {
            game.dealGeneralMarket(currentIndex);

            emit GeneralMarket(gameID, currentIndex);
        }
        uint256 _nextIndex = game.nextIndex(currentIndex);
        if (card.pickTwo()) {
            bool hsm = _hasSpecialMoves(gameID, game, currentIndex, extraData);
            PendingAction pAction =
                card.pickFour() && hsm ? PendingAction.PickFour : PendingAction.PickTwo;

            game.players[_nextIndex].pAction = pAction;

            emit PlayerPickTwo(gameID, _nextIndex, pAction);
        }

        if (card.pickThree()) {
            game.players[_nextIndex].pAction = PendingAction.PickThree;

            emit PlayerPickThree(gameID, _nextIndex);
        }

        bool hold;
        bool suspension;
        if (card.holdOn()) hold = true;
        if (card.suspension()) suspension = true;
        g.lastMoveTimestamp = uint40(block.timestamp);
        g.callCard = card;

        if (hold) {
            g.playerTurnIndex = uint8(game.nextNextIndex(currentIndex));
            g.toStorage(slot);
            emit PlayerSuspended(gameID, _nextIndex);
        } else if (suspension) {
            g.toStorage(slot);
            emit GameSuspended(gameID, currentIndex);
        } else {
            g.playerTurnIndex = uint8(_nextIndex);
            g.toStorage(slot);
        }

        emit MoveExecuted(gameID, currentIndex, Action.Play);
    }

    // pick 2, pick 4
    function pick(uint256 gameID, GameData storage game, uint256 currentIndex) internal {
        (GameCache memory g, uint256 slot) = GameCacheManager.toMem(game);

        PlayerData memory player = game.players[currentIndex];

        if (player.pAction.eqs(PendingAction.None)) revert NoPendingAction();

        if (player.pAction.eqs(PendingAction.PickTwo)) {
            game.dealPickTwo(player, currentIndex);
        } else if (player.pAction.eqs(PendingAction.PickThree)) {
            game.dealPickThree(player, currentIndex);
        } else {
            game.dealPickFour(player, currentIndex);
        }

        emit PendingActionFulfilled(gameID, currentIndex, player.pAction);

        game.players[currentIndex].pAction = PendingAction.None;
        g.playerTurnIndex = uint8(game.nextIndex(currentIndex));
        g.lastMoveTimestamp = uint40(block.timestamp);
        g.toStorage(slot);

        emit MoveExecuted(gameID, currentIndex, Action.Pick);
    }

    // defend against pick 2 or pick 4.
    function defend(uint256 gameID, GameData storage game, WhotCard card, bytes memory extraData)
        internal
        returns (bool err, bytes4 errMsg)
    {
        (GameCache memory g, uint256 slot) = GameCacheManager.toMem(game);
        uint256 currentIndex = g.playerTurnIndex;

        PlayerData memory player = game.players[currentIndex];

        if (!_hasSpecialMoves(gameID, game, currentIndex, extraData)) {
            (err, errMsg) = (true, DefenseNotEnabled.selector); //revert DefenseNotEnabled();
            return (err, errMsg);
        }
        // Nothing to defend against.
        if (player.pAction.eqs(PendingAction.None)) {
            (err, errMsg) = (true, NoPendingAction.selector); //revert NoPendingAction();
            return (err, errMsg);
        }
        // In order to defend, card number must be 2.
        if (!g.callCard.matchNumber(card)) {
            (err, errMsg) = (true, WrongWhotCard.selector); //revert WrongWhotCard();
            return (err, errMsg);
        }

        // pick 2 if pending action is a pick 4
        if (player.pAction.eqs(PendingAction.PickFour)) {
            game.dealPickTwo(player, currentIndex);
        }

        game.players[currentIndex].pAction = PendingAction.None;
        g.playerTurnIndex = uint8(game.nextIndex(currentIndex));
        g.lastMoveTimestamp = uint40(block.timestamp);
        g.callCard = card;
        g.toStorage(slot);

        emit MoveExecuted(gameID, currentIndex, Action.Defend);
    }

    // Go to Market. Take a card from the market deck.
    function goToMarket(uint256 gameID, GameData storage game, uint256 currentIndex) internal {
        (GameCache memory g, uint256 slot) = GameCacheManager.toMem(game);

        PlayerData memory player = game.players[currentIndex];

        if (!player.pAction.eqs(PendingAction.None)) {
            revert ResolvePendingAction();
        }

        game.deal(player, currentIndex);
        g.playerTurnIndex = uint8(game.nextIndex(currentIndex));
        g.lastMoveTimestamp = uint40(block.timestamp);
        g.toStorage(slot);

        emit MoveExecuted(gameID, currentIndex, Action.GoToMarket);
    }

    function _calculatePlayersScore(
        uint256 gameID,
        GameData storage game,
        PlayerData[] memory players,
        uint256 activePlayers
    ) internal {
        uint256[] memory playerIndexes = new uint256[](activePlayers);
        euint128 totals;
        uint256 indexPtr;
        for (uint256 i; i < players.length; i++) {
            if (players[i].isActive) {
                totals = totals.add(game.calculatePlayerScore(i).shl(uint8(i * 16)));
                playerIndexes[indexPtr++] = i;
            }
        }
        _commitScore(gameID, totals, playerIndexes);
    }

    function _hasSpecialMoves(
        uint256 gameID,
        GameData storage game,
        uint256 currentIndex,
        bytes memory extraData
    ) internal view returns (bool) {
        IWhotManager gameCreator = IWhotManager(game.gameCreator);
        return gameCreator.isWhotManager()
            ? gameCreator.hasSpecialMoves(gameID, currentIndex, extraData)
            : false;
    }

    function getPlayerWhotCardDeck(uint256 gameID, uint256 playerIndex)
        public
        view
        returns (WhotDeckMap, euint256[2] memory)
    {
        PlayerData memory player = whotGame[gameID].players[playerIndex];
        return (player.deckMap, player.whotCardDeck);
    }

    // function getPlayerWhotCardDeck(uint256 gameID)
    //     external
    //     view
    //     returns (WhotDeckMap, euint256[2] memory)
    // {
    //     uint256 playerIndex = whotGame[gameID].playerIndex[msg.sender];
    //     return getPlayerWhotCardDeck(gameID, playerIndex);
    // }

    function getPlayerData(uint256 gameID, uint256 playerIndex)
        external
        view
        returns (PlayerData memory)
    {
        return whotGame[gameID].players[playerIndex];
    }

    function _onJoinGame(
        uint256 gameID,
        address gameCreator,
        address player,
        bytes memory extraData
    ) internal {
        if (IWhotManager(gameCreator).isWhotManager()) {
            IWhotManager(gameCreator).onJoinGame(gameID, player, extraData);
        }
    }

    function _onExecuteMove(uint256 gameID, address gameCreator, uint256 playerIndex, Action action)
        internal
    {
        if (IWhotManager(gameCreator).isWhotManager()) {
            IWhotManager(gameCreator).onExecuteMove(gameID, playerIndex, action);
        }
    }

    function _onEndGame(uint256 gameID, address gameCreator) internal {
        if (IWhotManager(gameCreator).isWhotManager()) {
            IWhotManager(gameCreator).onEndGame(gameID);
        }
    }
}
