// import { expect } from "chai";
// import { network } from "hardhat";
import { awaitAllDecryptionResults } from "../asyncDecrypt";
import { createInstance } from "../instance";
import { reencryptEuint256 } from "../reencrypt";
import { getSigners, initSigners } from "../signers";
// import { debug } from "../utils";
import { deployWhotFixture } from "./whot.fixture";

describe("Whot", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const contract = await deployWhotFixture();
    this.contractAddress = await contract.getAddress();
    this.whot = contract;
    this.fhevm = await createInstance();
  });

  it("whot happy test", async function () {
    const input = this.fhevm.createEncryptedInput(
      this.contractAddress,
      this.signers.alice.address
    );
    input.add256(
      0x6261484746454443424128272625242322210e0d0c0b0a090807060504030201n
    );
    input.add256(0xb4b4b4b4b4b4b4b48887868584838281686766656463n);

    const encryptedDeck = await input.encrypt();

    const transaction = await this.whot.createGame(
      [],
      [encryptedDeck.handles[0], encryptedDeck.handles[1]],
      encryptedDeck.inputProof,
      0,
      [],
      3
    );
    await transaction.wait();

    await this.whot.connect(this.signers.alice).joinGame(1, "0x");
    await this.whot.connect(this.signers.carol).joinGame(1, "0x");
    await this.whot.connect(this.signers.dave).joinGame(1, "0x");

    await this.whot.connect(this.signers.carol).startGame(1);

    // const tx = await this.whot.connect(this.signers.alice).commitMove(1, 0, 13, 0);
    // await tx.wait();
    const tx1 = await this.whot.connect(this.signers.alice).executeMove(1, 2);
    await tx1.wait();

    const tx2 = await this.whot.connect(this.signers.carol).executeMove(1, 2);
    await tx2.wait();

    const tx3 = await this.whot.connect(this.signers.dave).executeMove(1, 2);
    await tx3.wait();

    // const tx4 = await this.whot.connect(this.signers.carol).commitMove(1, 0, 1, 0);
    // await tx4.wait();

    // await awaitAllDecryptionResults();

    // const tx5 = await this.whot.connect(this.signers.alice).executeMove(1, 3);
    // await tx5.wait();

    // await awaitAllDecryptionResults();

    const deck2 = await this.whot.getPlayerWhotCardDeck(1, 0);

    let aliceDeck2 = await reencryptEuint256(
      this.signers.alice,
      this.fhevm,
      deck2[1][0],
      this.contractAddress
    );
    let aliceDeck2Deckmap = deck2[0];

    console.log("deckmap: ", aliceDeck2Deckmap);
    console.log("len", aliceDeck2Deckmap & 0x3ffn);
    while (aliceDeck2 != 0n) {
      const card = aliceDeck2 & 0xffn;
      console.log("cardShape: ", card >> 5n, "cardNumber: ", card & 0x1fn);
      aliceDeck2 = aliceDeck2 >> 8n;
    }

    aliceDeck2Deckmap = aliceDeck2Deckmap >> 10n;
    while (aliceDeck2Deckmap != 0n) {
      console.log("alice_deckmap: ", aliceDeck2Deckmap & 1n);
      aliceDeck2Deckmap = aliceDeck2Deckmap >> 1n;
    }

    const deck3 = await this.whot.getPlayerWhotCardDeck(1, 1);

    let carolDeck = await reencryptEuint256(
      this.signers.carol,
      this.fhevm,
      deck3[1][0],
      this.contractAddress
    );
    console.log(carolDeck);
    while (carolDeck != 0n) {
      const card = carolDeck & 0xffn;
      console.log("cardShape2: ", card >> 5n, "cardNumber2: ", card & 0x1fn);
      carolDeck = carolDeck >> 8n;
    }

    let caroleDeckDeckmap = deck3[0];

    console.log("deckmap: ", caroleDeckDeckmap);
    console.log("len", caroleDeckDeckmap & 0x3ffn);
    caroleDeckDeckmap = caroleDeckDeckmap >> 10n;
    while (caroleDeckDeckmap != 0n) {
      console.log("carol_deckmap: ", caroleDeckDeckmap & 1n);
      caroleDeckDeckmap = caroleDeckDeckmap >> 1n;
    }

    const deck4 = await this.whot.getPlayerWhotCardDeck(1, 2);

    let daveDeck = await reencryptEuint256(
      this.signers.dave,
      this.fhevm,
      deck4[1][0],
      this.contractAddress
    );
    console.log(daveDeck);
    while (daveDeck != 0n) {
      const card = daveDeck & 0xffn;
      console.log("cardShape3: ", card >> 5n, "cardNumber3: ", card & 0x1fn);
      daveDeck = daveDeck >> 8n;
    }

    let daveDeckmap = deck4[0];

    console.log("deckmap: ", daveDeckmap);
    console.log("len", daveDeckmap & 0x3ffn);
    daveDeckmap = daveDeckmap >> 10n;
    while (daveDeckmap != 0n) {
      console.log("dave_deckmap: ", daveDeckmap & 1n);
      daveDeckmap = daveDeckmap >> 1n;
    }

    await awaitAllDecryptionResults();
  });
});
