import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre;
  const { deploy, get } = deployments;

  const { deployer } = await getNamedAccounts();

  const yourTokenDeployment = await get("YourToken");
  const yourToken = await ethers.getContractAt("YourToken", yourTokenDeployment.address);

  const vendorDeployment = await deploy("Vendor", {
    from: deployer,
    args: [yourTokenDeployment.address],
    log: true,
    // waitConfirmations: 1, // bật nếu deploy testnet
  });

  const vendorAddress = vendorDeployment.address;

  // Chuyển 1000 token sang Vendor để bán
  const tx1 = await yourToken.transfer(vendorAddress, ethers.parseEther("1000"));
  await tx1.wait();

  // (Khuyến nghị) chuyển ownership cho địa chỉ bạn đang dùng trên UI
  // Cách dùng:
  // FRONTEND_ADDRESS=0xYourFrontendAddress yarn deploy --reset
  const frontendAddress = process.env.FRONTEND_ADDRESS;
  if (frontendAddress && ethers.isAddress(frontendAddress)) {
    const vendor = await ethers.getContractAt("Vendor", vendorAddress);
    const tx2 = await vendor.transferOwnership(frontendAddress);
    await tx2.wait();
  }
};

export default func;
func.tags = ["Vendor"];
func.dependencies = ["YourToken"];
