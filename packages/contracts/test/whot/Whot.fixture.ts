import { ethers } from "hardhat";

import type { Whot } from "../../types";
import { getSigners } from "../signers";

export async function deployWhotFixture(): Promise<Whot> {
  const signers = await getSigners(ethers);

  const contractFactory = await ethers.getContractFactory("Whot");
  const contract = await contractFactory.connect(signers.alice).deploy();
  await contract.waitForDeployment();

  return contract;
}
