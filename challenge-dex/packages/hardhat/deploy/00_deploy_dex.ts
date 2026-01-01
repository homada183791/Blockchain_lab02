import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { DEX } from "../typechain-types/contracts/DEX";
import { Balloons } from "../typechain-types/contracts/Balloons";

const deployYourContract: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy } = hre.deployments;

  const networkName = hre.network.name; // hardhat | localhost | sepolia
  const isLocal = networkName === "localhost" || networkName === "hardhat";

  console.log("Deploying to network:", networkName);

  /* ------------------------------------------------------------ */
  /* 1) Deploy / reuse Balloons                                   */
  /* ------------------------------------------------------------ */
  await deploy("Balloons", {
    from: deployer,
    log: true,
    autoMine: true,
  });

  const balloons: Balloons = await hre.ethers.getContract(
    "Balloons",
    deployer
  );
  const balloonsAddress = await balloons.getAddress();

  /* ------------------------------------------------------------ */
  /* 2) Deploy / reuse DEX                                        */
  /* ------------------------------------------------------------ */
  await deploy("DEX", {
    from: deployer,
    args: [balloonsAddress],
    log: true,
    autoMine: true,
  });

  const dex = (await hre.ethers.getContract("DEX", deployer)) as DEX;
  const dexAddress = await dex.getAddress();

  /* ------------------------------------------------------------ */
  /* 3) Optional: transfer 10 BAL to frontend address             */
  /* ------------------------------------------------------------ */
  const frontendAddress = "0x30228d57FF1933cee0C0F88ED7AA5f306774B162";

  try {
    await balloons.transfer(frontendAddress, "" + 10 * 10 ** 18);
    console.log("Transferred 10 BAL to frontend address:", frontendAddress);
  } catch (err) {
    console.log("Skipping BAL transfer (likely already transferred).");
  }

  /* ------------------------------------------------------------ */
  /* 4) ONLY init DEX on LOCAL network                             */
  /* ------------------------------------------------------------ */
  if (isLocal) {
    console.log(
      "Approving DEX (" + dexAddress + ") to take Balloons (local)..."
    );

    await balloons.approve(dexAddress, hre.ethers.parseEther("100"));

    console.log("INIT exchange (local)...");
    await dex.init(hre.ethers.parseEther("1"), {
      value: hre.ethers.parseEther("1"),
      gasLimit: 200000,
    });

    console.log("DEX initialized on local network ✅");
  } else {
    console.log("Skipping approve + init on live network ✅");
    console.log("Balloons deployed at:", balloonsAddress);
    console.log("DEX deployed at:", dexAddress);
    console.log("👉 Init DEX manually from the UI");
  }
};

export default deployYourContract;

deployYourContract.tags = ["Balloons", "DEX"];
