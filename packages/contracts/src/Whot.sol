// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import {IWhotManager} from "./interfaces/IWhotManager.sol";
import {EIP712WithModifier} from "./abstracts/EIP712WithModifier.sol";
import "./WhotLib.sol";

contract Whot is EIP712WithModifier {
    using TFHE for *;
    using WhotLib for *;

    // Max number of players in a whot game.
    uint256 constant MAX_PLAYERS = 6;
    // Starting hand size for all players
    uint256 constant INITIAL_HAND_SIZE = 6;

    // Whot Game Data.
    mapping(uint256 => WhotLib.GameData) internal whotGame;

    mapping(address => bool) internal specialMovesUnlockedFor;

    // game ID
    uint256 gID = 1;

    // ERRORS
    // Player is  trying to join a game that they already joined.
    error PlayerAlreadyInGame();
    // Caller is  trying to join a game that has already started.
    error GameAlreadyStarted();
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
    // If call card is WHOT card, any card played must match its wish card.
    error WrongWishCard();
    // Player is not active. 
    error PlayerNotActive();
    // Player not proposed by game creator.
    error NotProposedPlayer();
    // Game cant be started.
    error CantStartGame();
    // Max player limit exceeded
    error PlayersLimitExceeded();
    // Caller is not part of game
    error PlayerNotInGame();


    //EVENTS
    // A player forfeited or was booted out by the whot manager.
    event PlayerForfeited(uint256 indexed gameID, address player);
    // A player joined a game.
    event PlayerJoined(uint256 indexed gameID, address player);
    // A player executed a move - WhotLib.Action{..}
    event MoveExecuted(uint256 indexed gameID, uint8 pTurnIndex, uint8 card, WhotLib.Action action);
    // A player will miss their turn.
    event Suspended(uint256 indexed gameID, uint8 pTurnIndexSuspended);
    // All players will  miss their next turn.
    event GameHeld(uint256 indexed gameID);
    // All players deck will be dealt with an extra card.
    event GeneralMarket(uint256 indexed gameID);
    // New Whot game created.
    event GameCreated(uint256 indexed gameID, address gameCreator);
    // Whot game started.
    event GameStarted(uint256 indexed gameID);
    // Whot game ended.
    event GameEnded(uint256 indexed gameID);


    // Create whot game with max number of players.
    // To enable whot manager, caller has to be a smart cntract that implements `IWhotManager`
    // If array length greater than zero, then only addresses in the array can join the game.
    // If array is empty, then any participants as much as `maxPlayers` can join the game.
    function createGame(address[] memory proposedPlayers, uint8 maxPlayers) public returns(uint256 gameID){
        gameID = gID;
        WhotLib.GameData storage game = whotGame[gameID];
        // Create new market deck and shuffle.
        game.marketDeck = WhotLib.getDefaultMarketDeck().shuffleDeck();
        game.proposedPlayers = proposedPlayers;
        game.maxPlayers = proposedPlayers.length > 0 ? uint8(proposedPlayers.length) : maxPlayers;
        if(game.maxPlayers > MAX_PLAYERS){
            revert PlayersLimitExceeded();
        }
        // player's index is initially set to its proposed player index.
        // when shuffling player's index it is then set to its normal player index.
        for(uint256 i = 0; i < proposedPlayers.length; i++){
            game.playerIndex[proposedPlayers[i]] = i;
        }
        gID++;

        emit GameCreated(gameID, game.gameCreator);
    }

    // Allows game creator to create and participate in a game.
    function createAndJoinGame(address[] memory proposedPlayers, uint8 maxPlayers) external returns(uint256 gameID){
        gameID = createGame(proposedPlayers, maxPlayers);
        joinGame(gameID);
    }

    // Joins whot game if game hasn't already started.
    // Can only join game if player is a proposed player (proposed players has to be set) 
    // or max players limit has not being reached.
    function joinGame(uint256 gameID) public {
        WhotLib.GameData storage game = whotGame[gameID];
        WhotLib.PlayerData memory player;
        bool isProposedPlayer;
        if(game.callCard != 0) revert GameAlreadyStarted();
        if(game.isActive[msg.sender]) revert PlayerAlreadyInGame();
        if(game.proposedPlayers.length != 0){
            isProposedPlayer = game.proposedPlayers[game.playerIndex[msg.sender]] == msg.sender;
        } else {
            isProposedPlayer = game.playersLeftToJoin != 0;
        }
        if(isProposedPlayer){
            player.playerAddr = msg.sender;
            game.isActive[msg.sender] = true;
            game.players.push(player);
            game.playersLeftToJoin--;
        } else { revert NotProposedPlayer(); }

        emit PlayerJoined(gameID, msg.sender);
    }

    /// Start a whot game.
    function startGame(uint256 gameID) external {
        WhotLib.GameData storage game = whotGame[gameID];
        WhotLib.PlayerData[] memory players = game.players;
        if(
            (msg.sender == game.gameCreator && (game.maxPlayers - game.playersLeftToJoin) >= 2) 
            || game.playersLeftToJoin == 0
        ){
            // initial deck size for each player is six.
            for(uint256 i = 0; i < INITIAL_HAND_SIZE; i++){
                for(uint256 j = 0; j < players.length; j++){
                    game.marketDeck.deal(game.players[j].deck);
                }
            }
            // set initial player score to min.
            // where zero is maximum score and type(uint32).max in minimum score.
            for(uint256 k = 0; k < players.length; k++){
                game.score[game.players[k].playerAddr] = type(uint32).max;
            }
        } else { revert CantStartGame(); }

        // shuffle players array.
        // First player's move is not constrained so might give them slight advantages.
        shufflePlayers(game);
        game.started = true;
        emit GameStarted(gameID);
    }

    // Execute player's move.
    function executeMove(
        uint256 gameID,
        WhotLib.Action action,
        uint256 cardIndex,
        WhotLib.Shape iWishCardShape
    ) external {
        WhotLib.GameData storage game = whotGame[gameID];
        gameStarted(game);
        isPlayerTurn(game);
        if(action == WhotLib.Action.Play) play(gameID, game, cardIndex, iWishCardShape);
        if(action == WhotLib.Action.Defend) defend(gameID, game, cardIndex);
        if(action == WhotLib.Action.GoToMarket) goToMarket(gameID, game);
        if(action == WhotLib.Action.Pick) pick(gameID, game);
        finish(gameID, game);
    }

    /// Fails silently. Might be an anti patern? Todo(nonso): fix?
    function finish(uint256 gameID, WhotLib.GameData storage game) internal {
        WhotLib.PlayerData[] memory players = game.players;
        uint256 activePlayers;
        for(uint256 i = 0; i < players.length; i++){
            if(game.isActive[players[i].playerAddr]){
                activePlayers++;
            }
        }
        if(game.marketDeck.isEmpty() || game.players[game.playerTurnIndex].deck.isEmpty() || activePlayers == 1){
            // calculate active players total score.
            for(uint256 i = 0; i < players.length; i++){
                if(game.isActive[players[i].playerAddr]){
                    game.score[players[i].playerAddr] = game.players[i].deck.total();
                }
            }
            game.ended = true;

            emit GameEnded(gameID);
        }
    }

    // Forfeit whot game.
    function forfeit(uint256 gameID) external {
        WhotLib.GameData storage game = whotGame[gameID];
        gameStarted(game);
        _forfeit(gameID, game, msg.sender);
        finish(gameID, game);
    }

    // Allows whot manager to remove player from game.
    function bootOut(uint256 gameID, address player) external {
        WhotLib.GameData storage game = whotGame[gameID];
        gameStarted(game);
        // callback to whot manager.
        IWhotManager(game.gameCreator).canBootOut();
        _forfeit(gameID, game, player);
        finish(gameID, game);
    }

    function _forfeit(uint256 gameID, WhotLib.GameData storage game, address _player) internal {
        WhotLib.PlayerData memory player = game.players[game.playerIndex[_player]];
        // checks edge cases where default mapping is zero which is a valid index.
        if(player.playerAddr != _player){
            revert PlayerNotInGame();
        }
        if(!game.isActive[_player]){
            revert PlayerNotActive();
        }
        game.isActive[_player] = false;
        if(player.playerAddr == _player){
            game.playerTurnIndex = nextIndex(game);
        }
        
        emit PlayerForfeited(gameID, _player);
    }

    // Play whot card.
    function play(
        uint256 gameID, 
        WhotLib.GameData storage game, 
        uint256 cardIndex, 
        WhotLib.Shape iWishCardShape
    ) internal {
        WhotLib.PlayerData[] memory players = game.players;
        uint8 currentIndex = game.playerTurnIndex;
        uint8 card = players[currentIndex].deck[cardIndex].decrypt();
        uint8 callCard = game.callCard;
        bool suspension;
        if(players[currentIndex].pAction != WhotLib.PendingAction.None){
            revert ResolvePendingAction();
        }
        if(card.shape() != whotCardShape()){
            if(callCard.shape() != whotCardShape()){
                if(
                    callCard.shape() != card.shape() 
                    || callCard.number() != card.number() 
                    || card.shape() != whotCardShape() 
                    || callCard != 0
                ){
                    revert WrongWhotCard();
                }
            } else {
                if(card.shape() != WhotLib.Shape(callCard & 7)){ revert WrongWishCard(); }
            }
            // general market
            if(card.number() == 14){
                for(uint256 i = 0; i < players.length; i++){
                    if(
                        players[i].playerAddr != players[currentIndex].playerAddr 
                        && game.isActive[players[i].playerAddr] 
                        && !game.marketDeck.isEmpty()
                    ){
                        game.marketDeck.deal(game.players[i].deck);
                    }
                }
                suspension = true;
                emit GeneralMarket(gameID);
            }
            
            // pick 2. if card's shape is star and multiplier enabled pick 4
            if(card.number() == 2){
                game.players[nextIndex(game)].pAction = (specialMovesUnlocked() && card.shape() == WhotLib.Shape.Star) ?
                    WhotLib.PendingAction.PickFour : WhotLib.PendingAction.PickTwo;
            }
            if(card.number() == 8){
                suspension = true;
                emit GameHeld(gameID);
            }
            // next player is suspended thus will miss their turn.
            if(card.number() == 1){
                suspension = true;
                suspend(gameID, game);
            }
        } else {
            game.callCard = (card & 0xE0) | uint8(iWishCardShape);
        }
        uint256 pDeckLength = players[currentIndex].deck.length;
        pDeckLength--;
        if(pDeckLength == cardIndex){
            game.players[currentIndex].deck.pop();
        } else {
            game.players[currentIndex].deck[cardIndex] = players[currentIndex].deck[pDeckLength];
            game.players[currentIndex].deck.pop();
        }
        game.callCard = card;
        // if there is a suspension no need to update next index.
        if(!suspension) game.playerTurnIndex = nextIndex(game);

        emit MoveExecuted(gameID, currentIndex, card, WhotLib.Action.Play);
    }

    // pick 2, pick 4
    function pick(uint256 gameID, WhotLib.GameData storage game) internal {
        WhotLib.PlayerData[] memory players = game.players;
        uint8 currentIndex = game.playerTurnIndex;
        
        if(players[currentIndex].pAction == WhotLib.PendingAction.None){ revert NoPendingAction(); }
        for(uint8 i = 0; i < uint8(players[currentIndex].pAction) * 2; i++){
            // can only pick if market deck is not empty.
            if(!game.marketDeck.isEmpty()){
                game.marketDeck.deal(game.players[currentIndex].deck);
            }
        }
        game.playerTurnIndex = nextIndex(game);

        emit MoveExecuted(gameID, currentIndex, 0, WhotLib.Action.Pick);
    }

    // defend against pick 2 or pick 4.
    function defend(uint256 gameID, WhotLib.GameData storage game, uint256 cardIndex) internal {
        WhotLib.PlayerData[] memory players = game.players;
        uint8 currentIndex = game.playerTurnIndex;
        uint8 card = players[currentIndex].deck[cardIndex].decrypt();
        uint8 callCard = game.callCard;
        // Defense not enabled.
        if(!specialMovesUnlocked()) revert DefenseNotEnabled();
        // Nothing to defend against.
        if(players[currentIndex].pAction == WhotLib.PendingAction.None){ revert NoPendingAction(); }
        // In order to defend, card number must be 2.
        if(card.number() != 2 && callCard.number() != 2){
            revert WrongWhotCard();
        }
        // pick 2 if pending action is a pick 4
        if(players[currentIndex].pAction == WhotLib.PendingAction.PickFour){
            for(uint8 i = 0; i < 2; i++){
                game.marketDeck.deal(game.players[currentIndex].deck);
            }
        }
        uint256 pDeckLength = players[currentIndex].deck.length;
        pDeckLength--;
        if(pDeckLength == cardIndex){
            game.players[currentIndex].deck.pop();
        } else {
            game.players[currentIndex].deck[cardIndex] = players[currentIndex].deck[pDeckLength];
            game.players[currentIndex].deck.pop();
        }
        game.playerTurnIndex = nextIndex(game);
        game.callCard = card;

        emit MoveExecuted(gameID, currentIndex, card, WhotLib.Action.Defend);
    }

    // Go to Market. Take a card from the market deck.
    function goToMarket(uint256 gameID, WhotLib.GameData storage game) internal {
        WhotLib.PlayerData[] memory players = game.players;
        uint8 currentIndex = game.playerTurnIndex;
        
        if(players[currentIndex].pAction != WhotLib.PendingAction.None){
            revert ResolvePendingAction();
        }
        game.marketDeck.deal(game.players[currentIndex].deck);
        game.playerTurnIndex = nextIndex(game);

        emit MoveExecuted(gameID, currentIndex, 0, WhotLib.Action.GoToMarket);
    }

    function whotCardShape() internal pure returns(WhotLib.Shape shape){
        return WhotLib.Shape(5);
    }

    // Get next player turn index. if next player is not active skip to next player.
    function nextIndex(WhotLib.GameData storage game) internal view returns(uint8){
        uint8 currentIndex = game.playerTurnIndex;
        uint8 total = uint8(game.players.length);
        uint8 _nextIndex = (currentIndex % total) + 1;
        while(!game.isActive[game.players[_nextIndex].playerAddr]){
            _nextIndex = (_nextIndex % total) + 1;
        }
        return _nextIndex;
    }
    
    // Suspends next player. Next player will miss their turn.
    function suspend(uint256 gameID, WhotLib.GameData storage game) internal {
        uint8 currentIndex = game.playerTurnIndex;
        uint8 total = uint8(game.players.length);
        uint8 _nextIndex = (currentIndex % total) + 1;
        uint8 nextNextIndex = (_nextIndex % total) + 1;
        while(!game.isActive[game.players[nextNextIndex].playerAddr]){
            nextNextIndex = (nextNextIndex % total) + 1;
        }
        game.playerTurnIndex = nextNextIndex;
        
        emit Suspended(gameID, nextNextIndex);
    }

    function unlockSpecialMoves() external {
        specialMovesUnlockedFor[msg.sender] = true;
    }

    // Shuffle player index before game starts.
    function shufflePlayers(WhotLib.GameData storage game) internal {
        // get random number.
        uint256 rand = uint256(
            keccak256(
                abi.encode(
                    game.gameCreator, 
                    block.timestamp, 
                    blockhash(block.number - 1)
                )
            )
        );
        uint256 lastIndex = game.players.length;
        uint256 randIndex;
        while(lastIndex > 0){
            randIndex = rand % lastIndex;
            WhotLib.PlayerData memory temp = game.players[lastIndex];
            game.players[lastIndex] = game.players[randIndex];
            game.playerIndex[game.players[randIndex].playerAddr] = lastIndex;
            game.players[randIndex] = temp;
            game.playerIndex[temp.playerAddr] = randIndex;
            lastIndex--;
        }
    }

    // Get decrypted player card.
    function getPlayerCard(
        uint256 gameID,
        uint256 cardIndex,
        bytes32 publicKey, 
        bytes calldata signature
    ) public view onlySignedPublicKey(publicKey, signature) returns (bytes memory) {
        WhotLib.GameData storage game = whotGame[gameID];
        WhotLib.PlayerData memory player = game.players[game.playerIndex[msg.sender]];
        if(msg.sender != player.playerAddr){
            revert PlayerNotInGame();
        }
        euint8 card = player.deck[cardIndex];
        return card.reencrypt(publicKey);
    }

    function gameStarted(WhotLib.GameData storage game) internal view returns(bool){
        return game.started && !game.ended;
    }

    function specialMovesUnlocked() internal view returns(bool){
        return specialMovesUnlockedFor[msg.sender];
    }

    function isPlayerTurn(WhotLib.GameData storage game) internal view {
        WhotLib.PlayerData memory player = game.players[game.playerTurnIndex];
        if(msg.sender != player.playerAddr){
            revert NotPlayerTurn();
        }
    }

    constructor() EIP712WithModifier("Whot Authorization Token", "0.1"){}
}