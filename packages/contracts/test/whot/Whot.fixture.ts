import type { Whot } from "../../types";
import { getSigners } from "../signers";
import { ZeroAddress } from "ethers";
import { ethers } from "hardhat";

export async function deployWhotFixture(): Promise<Whot> {
  const signers = await getSigners();

  const mockTSSFactory = await ethers.getContractFactory(
    "MockTrustedShuffleService"
  );
  const mockTSS = await mockTSSFactory
    .connect(signers.alice)
    .deploy(ZeroAddress);

  const contractFactory = await ethers.getContractFactory("Whot");
  const contract = await contractFactory
    .connect(signers.alice)
    .deploy(mockTSS.getAddress(), 100);
  await contract.waitForDeployment();

  return contract;
}
