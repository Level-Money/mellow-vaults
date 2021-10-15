import { network } from "hardhat";

export const sleepTo = async (timestamp: number) => {
    await network.provider.send("evm_setNextBlockTimestamp", [timestamp]);
    await network.provider.send('evm_mine');
}

export const sleep = async (seconds: number) => {
    await network.provider.send("evm_increaseTime", [seconds]);
    await network.provider.send("evm_mine");
}
