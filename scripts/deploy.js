const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await ethers.getSigners();
  const bal = await ethers.provider.getBalance(deployer.address);
  console.log(`Network:  ${network.name} (chainId ${(await ethers.provider.getNetwork()).chainId})`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance:  ${ethers.formatEther(bal)} POT`);

  const mp = await ethers.deployContract("MilestonePay");
  await mp.waitForDeployment();
  const address = await mp.getAddress();
  const tx = mp.deploymentTransaction();
  console.log(`\nMilestonePay deployed at: ${address}`);
  console.log(`Deploy tx: ${tx.hash}`);

  const out = {
    network: network.name,
    chainId: Number((await ethers.provider.getNetwork()).chainId),
    address,
    deployTx: tx.hash,
    deployedAt: new Date().toISOString(),
  };
  fs.writeFileSync(path.join(__dirname, "..", "deployment.json"), JSON.stringify(out, null, 2));
  console.log("Saved deployment.json — paste the address into frontend/config.js");
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
