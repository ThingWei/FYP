const hre = require('hardhat');
async function main() {
  const [, renter, owner] = await hre.ethers.getSigners();
  const Contract = await hre.ethers.getContractFactory('RentalAgreement');
  const contract = await Contract.deploy(renter.address, owner.address, hre.ethers.parseEther('1'), hre.ethers.parseEther('.5'), { value: hre.ethers.parseEther('1.5') });
  await contract.waitForDeployment(); console.log(await contract.getAddress());
}
main().catch((error) => { console.error(error); process.exitCode = 1; });

