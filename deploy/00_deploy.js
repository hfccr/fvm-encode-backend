require("hardhat-deploy")
require("hardhat-deploy-ethers")

const { networkConfig } = require("../helper-hardhat-config")


const private_key = network.config.accounts[0]
const wallet = new ethers.Wallet(private_key, ethers.provider)

module.exports = async ({ deployments, ethers }) => {
    const { deploy } = deployments;
    const feeData = await ethers.provider.getFeeData();
    const overrides = {
        maxPriorityFeePerGas: feeData.maxPriorityFeePerGas,
        maxFeePerGas: feeData.maxFeePerGas,
    };
    console.log('Overrides are');
    console.log(overrides);
    console.log("Wallet Ethereum Address:", wallet.address)
    // const chainId = network.config.chainId
    // const tokensToBeMinted = networkConfig[chainId]["tokensToBeMinted"]

    //deploy settings
    const settings = await deploy("Settings", {
        from: wallet.address,
        args: [wallet.address],
        log: true,
    });


    //deploy vault
    const vault = await deploy("Vault", {
        from: wallet.address,
        args: [settings.address],
        log: true,
    });

    // deploy appeals
    const appeals = await deploy("Appeals", {
        from: wallet.address,
        args: [settings.address, vault.address],
        log: true,
    });

    // deploy providers
    const providers = await deploy("Providers", {
        from: wallet.address,
        args: [settings.address, vault.address, appeals.address],
        log: true,
    });

    // deploy deals
    const deals = await deploy("Deals", {
        from: wallet.address,
        args: [settings.address, vault.address, appeals.address, providers.address],
        log: true,
    });

    console.log('Setting roles on vault contract');
    const vaultContract = await ethers.getContractAt("Vault", vault.address);
    const balance = await vaultContract.getProtocolBalance();
    console.log(balance);
    await (await vaultContract.setAppealsRole(appeals.address, overrides)).wait();
    await (await vaultContract.setProvidersRole(providers.address, overrides)).wait();
    await (await vaultContract.setDealsRole(deals.address, overrides)).wait();


    console.log('Setting deal address on appeals contract');
    const appealsContract = await ethers.getContractAt("Appeals", appeals.address);
    await (await appealsContract.setDealsAddress(deals.address, overrides)).wait();

    console.log('Setting deal address on providers contract');
    const providersContract = await ethers.getContractAt("Providers", providers.address);
    await (await providersContract.setDealsAddress(deals.address, overrides)).wait();

}