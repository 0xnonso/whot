// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "fhevm/TFHE.sol";    

library WhotLib {
    using TFHE for *;

    enum Action{
        Play,
        Defend,
        GoToMarket,
        Pick
    }

    enum PendingAction{
        None,
        PickTwo,
        PickFour
    }

    enum Shape{
        Circle,
        Triangle,
        Cross,
        Square,
        Star,
        Whot
    }

    struct PlayerData {
        address playerAddr;
        euint8[] deck;
        PendingAction pAction;
    }
    struct GameData {
        address gameCreator;
        uint8 callCard;
        uint8 playerTurnIndex;
        bool started;
        bool ended;
        uint8 maxPlayers;
        uint8 playersLeftToJoin;
        uint64 lastMoveTimestamp;
        euint32[] marketDeck;
        PlayerData[] players;
        address[] proposedPlayers;
        mapping(address => bool) isActive;
        mapping(address => uint32) score;
        // Todo: might remove.
        // Allows for easier retrieval of player's data index;
        mapping(address => uint256) playerIndex;
    }
    
    function getDefaultMarketDeck() internal pure returns(euint32[] memory){
        euint32[] memory defaultDeck = new euint32[](14);
        defaultDeck[0]  = uint256(16909060).asEuint32(); 
        defaultDeck[1]  = uint256(84346890).asEuint32();                    
        defaultDeck[2]  = uint256(185339150).asEuint32();
        defaultDeck[3]  = uint256(555885348).asEuint32();  // 00100001 00100010 00100011 00100100
        defaultDeck[4]  = uint256(623323178).asEuint32();  // 00100101 00100111 00101000 00101010
        defaultDeck[5]  = uint256(724315438).asEuint32();  // 00101011 00101100 00101101 00101110
        defaultDeck[6]  = uint256(1094861637).asEuint32(); // 01000001 01000010 01000011 01000101
        defaultDeck[7]  = uint256(1196051277).asEuint32(); // 01000111 01001010 01001011 01001101
        defaultDeck[8]  = uint256(1315005027).asEuint32(); // 01001110 01100001 01100010 01100011
        defaultDeck[9]  = uint256(1701276267).asEuint32(); // 01100101 01100111 01101010 01101011
        defaultDeck[10] = uint256(1835958658).asEuint32(); // 01101101 01101110 10000001 10000010
        defaultDeck[11] = uint256(2206500231).asEuint32(); // 10000011 10000100 10000101 10000111
        defaultDeck[12] = uint256(2293544116).asEuint32(); // 10001000 10110100 10110100 10110100
        defaultDeck[13] = uint256(46260).asEuint32();      // 10110100 10110100
        return defaultDeck;
    }

    function shuffleDeck(euint32[] memory deck) internal returns(euint32[] memory){
        // fhe operations are very expensive 🥲
        // https://discord.com/channels/901152454077452399/1174473260801470514/1175347229914046506
        euint8 rand = TFHE.randEuint8();
        uint8 i = 54;
        while(i != 0){
            euint8 j = rand.rem(i);
            swap(deck, uint32(i), j.asEuint32());
            i--;
        }

        return deck;
    }

    function swap(euint32[] memory deck, uint32 i, euint32 j) internal view {
        uint256 arrIndex_i = i/4;
        uint256 arrIndex_j = j.div(4).decrypt();

        euint32 deck_i = deck[arrIndex_i];
        euint32 deck_i_i = deck[arrIndex_i];

        euint32 deck_j = deck[arrIndex_j];
        euint32 deck_j_j = deck[arrIndex_j];
        
        euint32 index_i = uint256((i % 4) * 8).asEuint32();
        euint32 index_j = j.rem(4).mul(8);

        euint32 clearMask_i = uint256(0xFF).asEuint32().shl(index_i).xor(uint256(0xFFFFFFFF).asEuint32());
        euint32 clearMask_j = uint256(0xFF).asEuint32().shl(index_j).xor(uint256(0xFFFFFFFF).asEuint32());

        deck_i = deck_i.and(clearMask_i);
        deck_i = deck_i.or(deck_j_j.shr(index_j).and(uint256(0xFF).asEuint32()).shl(index_i));

        deck_j = deck_j.and(clearMask_j);
        deck_j = deck_j.or(deck_i_i.shr(index_i).and(uint256(0xFF).asEuint32()).shl(index_j));

        deck[arrIndex_i] = deck_i;
        deck[arrIndex_i] = deck_j;
    }

    function deal(euint32[] storage marketDeck, euint8[] storage playerDeck) internal {
        uint8 dLen = uint8(marketDeck.length);
        euint32 _marketDeck = marketDeck[dLen/4];
        uint8  marketDeckIndex = (dLen % 4) * 8;
        _marketDeck = _marketDeck.shr(marketDeckIndex);
        _marketDeck = _marketDeck.and(uint256(0xFF).asEuint32());
        playerDeck[playerDeck.length] = _marketDeck.asEuint8();
        marketDeck[dLen/4] = marketDeck[dLen/4].and(uint256(0xFFFFFF00 << marketDeckIndex).asEuint32());
    }

    function isEmpty(euint32[] storage deck) internal view returns(bool){
        return deck[0].eq(0).decrypt();
    }

    function isEmpty(euint8[] storage deck) internal view returns(bool){
        return deck.length == 0;
    }

    function total(euint8[] memory deck) internal view returns(uint32){
        // Should be cheaper to just decrypt all the cards first?
        // since game has already ended no need to hide card info.
        euint32 _total;
        for(uint256 i =  0; i < deck.length; i++){
            euint8 cardNumber = deck[i].and(uint256(0x1F).asEuint8());
            euint8 cardShape = deck[i].shr(5);
            euint8 cardToAdd = cardShape.eq(uint8(Shape.Star)).cmux(cardNumber.mul(2), cardNumber);
            _total = _total.add(cardToAdd);
        }
        return _total.decrypt();
    }

    function shape(uint8 card) internal pure returns(Shape){
        return Shape(card >> 5);
    }

    function number(uint8 card) internal pure returns(uint8){
        return card & 0x1F;
    }

}
