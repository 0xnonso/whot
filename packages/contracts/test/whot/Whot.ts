import { expect } from "chai";
import { ethers } from "hardhat";

import { createInstances } from "../instance";
import { getSigners } from "../signers";
import { createTransaction } from "../utils";
import { deployWhotFixture } from "./Whot.fixture";
import { AddressLike } from "ethers";

describe("WhotGame", function () {
  before(async function () {
    this.signers = await getSigners(ethers);
  });

  beforeEach(async function () {
    const contract = await deployWhotFixture();
    this.contractAddress = await contract.getAddress();
    this.whotGame = contract;
    this.instances = await createInstances(this.contractAddress, ethers, this.signers);
  });

  it("should join game", async function () {
    const transaction = await createTransaction(
      this.whotGame.createGame, 
      [this.signers.bob.address, this.signers.alice.address],
       4
    );
    // const transaction = await createTransaction(this.whot.startGame, 1);
    await transaction.wait();
    // const gameID  = 1;
    // const bobGame = this.whotGame.connect(this.signers.bob);
    // await bobGame.joinGame(gameID);
    // const aliceGame = this.whotGame.connect(this.signers.alice);
    // await aliceGame.joinGame(gameID);
    // const carolGame = this.whotGame.connect(this.signers.carol);
    // await carolGame.joinGame(gameID);

    // const tx = await createTransaction(this.whotGame.startGame, gameID);
    // await tx.wait();

  });

  // it("should transfer tokens between two users", async function () {
  //   const encryptedAmount = this.instances.alice.encrypt32(10000);
  //   const transaction = await createTransaction(this.erc20.mint, encryptedAmount);
  //   await transaction.wait();

  //   const encryptedTransferAmount = this.instances.alice.encrypt32(1337);
  //   const tx = await createTransaction(
  //     this.erc20["transfer(address,bytes)"],
  //     this.signers.bob.address,
  //     encryptedTransferAmount,
  //   );
  //   await tx.wait();

  //   const tokenAlice = this.instances.alice.getTokenSignature(this.contractAddress)!;

  //   const encryptedBalanceAlice = await this.erc20.balanceOf(tokenAlice.publicKey, tokenAlice.signature);

  //   // Decrypt the balance
  //   const balanceAlice = this.instances.alice.decrypt(this.contractAddress, encryptedBalanceAlice);

  //   expect(balanceAlice).to.equal(10000 - 1337);

  //   const bobErc20 = this.erc20.connect(this.signers.bob);

  //   const tokenBob = this.instances.bob.getTokenSignature(this.contractAddress)!;

  //   const encryptedBalanceBob = await bobErc20.balanceOf(tokenBob.publicKey, tokenBob.signature);

  //   // Decrypt the balance
  //   const balanceBob = this.instances.bob.decrypt(this.contractAddress, encryptedBalanceBob);

  //   expect(balanceBob).to.equal(1337);
  // });
});
