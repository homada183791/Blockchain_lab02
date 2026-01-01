import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  await deploy("YourToken", {
    from: deployer,
    args: [],
    log: true,
    // waitConfirmations: 1, // bật nếu deploy testnet
  });
};

export default func;
func.tags = ["YourToken"];
