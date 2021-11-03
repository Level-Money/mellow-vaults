import { ethers, getNamedAccounts } from "hardhat";
import { Contract, ContractFactory } from "@ethersproject/contracts";
import { Signer } from "@ethersproject/abstract-signer";

import { sleep, sortContractsByAddresses } from "./Helpers";
import {
    Address,
    ERC20,
    ERC20Vault,
    ProtocolGovernance,
    VaultGovernance,
    LpIssuerGovernance,
    VaultRegistry,
    ProtocolGovernance_constructorArgs,
    VaultGovernance_constructorArgs,
    LpIssuerGovernance_constructorArgs,
    ProtocolGovernance_Params,
    ERC20Test_constructorArgs,
    VaultFactory,
    VaultType,
    VaultGovernance_InternalParams,
    IVaultGovernance,
} from "./Types";
import { BigNumber } from "@ethersproject/bignumber";

export async function deployERC20Tokens(length: number): Promise<ERC20[]> {
    let tokens: ERC20[] = [];
    let token_constructorArgs: ERC20Test_constructorArgs[] = [];
    const Contract: ContractFactory = await ethers.getContractFactory(
        "ERC20Test"
    );

    for (let i = 0; i < length; ++i) {
        token_constructorArgs.push({
            name: "Test Token",
            symbol: `TEST_${i}`,
        });
    }

    for (let i: number = 0; i < length; ++i) {
        const contract: ERC20 = await Contract.deploy(
            token_constructorArgs[i].name + `_${i.toString()}`,
            token_constructorArgs[i].symbol
        );
        await contract.deployed();
        tokens.push(contract);
    }
    return tokens;
}

export const deployProtocolGovernance = async (options: {
    constructorArgs?: ProtocolGovernance_constructorArgs;
    initializerArgs?: {
        params: ProtocolGovernance_Params;
    };
    adminSigner: Signer;
}) => {
    // defaults<
    const constructorArgs: ProtocolGovernance_constructorArgs =
        options.constructorArgs ?? {
            admin: await options.adminSigner.getAddress(),
        };
    // />
    const contractFactory: ContractFactory = await ethers.getContractFactory(
        "ProtocolGovernance"
    );
    const contract: ProtocolGovernance = await contractFactory.deploy(
        constructorArgs.admin
    );

    if (options?.initializerArgs) {
        await contract
            .connect(options!.adminSigner)
            .setPendingParams(options.initializerArgs.params);
        await sleep(Number(options.initializerArgs.params.governanceDelay));
        await contract.connect(options!.adminSigner).commitParams();
    }
    return contract;
};

export const deployVaultRegistryAndProtocolGovernance = async (options: {
    name?: string;
    symbol?: string;
    adminSigner: Signer;
    treasury: Address;
}) => {
    const protocolGovernance = await deployProtocolGovernance({
        adminSigner: options.adminSigner,
    });
    const VaultRegistryFactory: ContractFactory =
        await ethers.getContractFactory("VaultRegistry");
    let contract: VaultRegistry = await VaultRegistryFactory.deploy(
        options.name ?? "Test Vault Registry",
        options.symbol ?? "TVR",
        protocolGovernance.address
    );
    await contract.deployed();
    await protocolGovernance.connect(options.adminSigner).setPendingParams({
        maxTokensPerVault: BigNumber.from(10),
        governanceDelay: BigNumber.from(1),

        strategyPerformanceFee: BigNumber.from(10 * 10 ** 9),
        protocolPerformanceFee: BigNumber.from(2 * 10 ** 9),
        protocolExitFee: BigNumber.from(10 ** 9),
        protocolTreasury: options.treasury,
        vaultRegistry: contract.address,
    });
    await sleep(1);
    return {
        vaultRegistry: contract,
        protocolGovernance: protocolGovernance,
    };
};

export async function deployVaultFactory(options: {
    vaultGovernance: IVaultGovernance;
    vaultType: VaultType;
}): Promise<VaultFactory> {
    const Contract = await ethers.getContractFactory(
        `${options.vaultType}VaultFactory`
    );
    const contract = await Contract.deploy(options.vaultGovernance);
    return contract;
}

export const deployVaultGovernance = async (options: {
    constructorArgs: VaultGovernance_constructorArgs;
    adminSigner: Signer;
    treasury: Address;
    vaultType: VaultType;
}) => {
    let contract: Contract;
    const Contract = await ethers.getContractFactory(
        `${options.vaultType}VaultGovernance`
    );
    contract = await Contract.deploy(options.constructorArgs.params);
    await contract.deployed();
    return contract;
};

export async function deployVaultGovernanceSystem(options: {
    adminSigner: Signer;
    treasury: Address;
    vaultType: VaultType;
}): Promise<{
    vaultFactory: VaultFactory;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    vaultGovernance: VaultGovernance;
}> {
    const { vaultRegistry, protocolGovernance } =
        await deployVaultRegistryAndProtocolGovernance({
            name: "VaultRegistry",
            symbol: "MVR",
            adminSigner: options.adminSigner,
            treasury: options.treasury,
        });
    let params: VaultGovernance_InternalParams = {
        protocolGovernance: protocolGovernance.address,
        registry: vaultRegistry.address,
        factory: ethers.constants.AddressZero,
    };
    const contractFactory: ContractFactory = await ethers.getContractFactory(
        `${options.vaultType}VaultGovernance`
    );
    let vaultGovernance: VaultGovernance;
    switch (options.vaultType) {
        case "Aave" as VaultType: {
            const { aaveLendingPool } = await getNamedAccounts();
            vaultGovernance = await contractFactory.deploy(params, {
                lendingPool: aaveLendingPool,
            });
            break;
        }
        case "UniV3" as VaultType: {
            const { uniswapV3PositionManager } = await getNamedAccounts();
            vaultGovernance = await contractFactory.deploy(params, {
                positionManager: uniswapV3PositionManager,
            });
            break;
        }
        default: {
            /// TODO: UniV3, Gateway
            vaultGovernance = await contractFactory.deploy(params);
            break;
        }
    }
    await vaultGovernance.deployed();
    const vaultFactory = await deployVaultFactory({
        vaultType: options.vaultType,
        vaultGovernance: vaultGovernance.address,
    });
    params.factory = vaultFactory.address;
    await vaultGovernance
        .connect(options.adminSigner)
        .stageInternalParams(params);
    await sleep(1);
    await vaultGovernance.connect(options.adminSigner).commitInternalParams();
    return {
        vaultFactory: vaultFactory,
        vaultRegistry: vaultRegistry,
        protocolGovernance: protocolGovernance,
        vaultGovernance: vaultGovernance,
    };
}

export async function deployTestVaultGovernance(options: {
    adminSigner: Signer;
    treasury: Address;
    vaultType: VaultType;
}): Promise<{
    vaultFactory: VaultFactory;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    vaultGovernance: VaultGovernance;
}> {
    const { vaultRegistry, protocolGovernance } =
        await deployVaultRegistryAndProtocolGovernance({
            name: "VaultRegistry",
            symbol: "MVR",
            adminSigner: options.adminSigner,
            treasury: options.treasury,
        });
    let contractFactory: ContractFactory = await ethers.getContractFactory(
        "TestVaultGovernance"
    );
    let contract = await contractFactory.deploy({
        protocolGovernance: protocolGovernance.address,
        registry: vaultRegistry.address,
        factory: ethers.constants.AddressZero,
    });

    let vaultFactory = await deployVaultFactory({
        vaultGovernance: contract.address,
        vaultType: "ERC20",
    });

    await contract.stageInternalParams({
        protocolGovernance: protocolGovernance.address,
        registry: vaultRegistry.address,
        factory: vaultFactory.address,
    });

    await contract.commitInternalParams();

    return {
        vaultFactory: vaultFactory,
        vaultRegistry: vaultRegistry,
        protocolGovernance: protocolGovernance,
        vaultGovernance: contract,
    };
}

export async function deployVaultRegistry(options: {
    name: string;
    symbol: string;
    protocolGovernance: ProtocolGovernance;
}): Promise<Contract> {
    let Contract = await ethers.getContractFactory("VaultRegistry");
    let contract = await Contract.deploy(
        options.name,
        options.symbol,
        options.protocolGovernance.address
    );
    await contract.deployed();
    return contract;
}

export async function deployCommonLibrary(): Promise<Contract> {
    const Library: ContractFactory = await ethers.getContractFactory("Common");
    const library: Contract = await Library.deploy();
    await library.deployed();
    return library;
}

export async function deployCommonLibraryTest(): Promise<Contract> {
    const CommonTest: ContractFactory = await ethers.getContractFactory(
        "CommonTest"
    );
    const commonTest: Contract = await CommonTest.deploy();
    await commonTest.deployed();
    return commonTest;
}

export const deployLpIssuerGovernance = async (options: {
    constructorArgs?: LpIssuerGovernance_constructorArgs;
    adminSigner?: Signer;
}) => {
    // defaults<
    const constructorArgs: LpIssuerGovernance_constructorArgs =
        options.constructorArgs ?? {
            gatewayVault: ethers.constants.AddressZero,
            protocolGovernance: ethers.constants.AddressZero,
        };
    // />
    const Contract: ContractFactory = await ethers.getContractFactory(
        "LpIssuerGovernance"
    );

    let contract: LpIssuerGovernance = await Contract.deploy(constructorArgs);
    await contract.deployed();
    return contract;
};

export async function deployERC20VaultSystem(options: {
    tokensCount: number;
    adminSigner: Signer;
    treasury: Address;
    vaultOwner: Address;
}): Promise<{
    vaultFactory: VaultFactory;
    vaultRegistry: VaultRegistry;
    protocolGovernance: ProtocolGovernance;
    vaultGovernance: VaultGovernance;
    tokens: ERC20[];
    vault: ERC20Vault;
    nft: number;
}> {
    const { vaultRegistry, protocolGovernance, vaultFactory, vaultGovernance } =
        await deployVaultGovernanceSystem({
            adminSigner: options.adminSigner,
            treasury: options.treasury,
            vaultType: "ERC20" as VaultType,
        });
    const vaultTokens: ERC20[] = sortContractsByAddresses(
        await deployERC20Tokens(options.tokensCount)
    );
    await protocolGovernance
        .connect(options.adminSigner)
        .setPendingVaultGovernancesAdd([vaultGovernance.address]);
    await sleep(Number(await protocolGovernance.governanceDelay()));
    await protocolGovernance
        .connect(options.adminSigner)
        .commitVaultGovernancesAdd();
    const { vault, nft } = await vaultGovernance.callStatic.deployVault(
        vaultTokens.map((token) => token.address),
        [],
        options.vaultOwner
    );
    await vaultGovernance.deployVault(
        vaultTokens.map((token) => token.address),
        [],
        options.vaultOwner
    );
    const vaultContract: ERC20Vault = await ethers.getContractAt(
        "ERC20Vault",
        vault
    );
    return {
        vaultFactory: vaultFactory,
        vaultRegistry: vaultRegistry,
        protocolGovernance: protocolGovernance,
        vaultGovernance: vaultGovernance,
        tokens: vaultTokens,
        vault: vaultContract,
        nft: nft,
    };
}
