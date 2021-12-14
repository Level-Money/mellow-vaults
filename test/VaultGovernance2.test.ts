import { BigNumber, Contract, ethers } from "ethers";
import { Arbitrary, Random } from "fast-check";
import { type } from "os";
import { sleep, toObject, zeroify } from "./library/Helpers";
import { address, pit, RUNS } from "./library/property";
import { TestContext } from "./library/setup";
import { mersenne } from "pure-rand";
import { equals } from "ramda";
import { expect } from "chai";

const random = new Random(mersenne(Math.floor(Math.random() * 100000)));

function generateParams<T extends Object>(
    params: Arbitrary<T>
): { someParams: T; noneParams: T } {
    const someParams: T = params
        .filter((x: T) => !equals(x, zeroify(x)))
        .generate(random).value;
    const noneParams: T = zeroify(someParams);
    return { someParams, noneParams };
}

export function vaultGovernanceBehavior<
    DSP,
    SP,
    DPP,
    PP,
    DPPV,
    S extends Contract
>(
    this: TestContext<S>,
    {
        delayedStrategyParams,
        strategyParams,
        delayedProtocolParams,
        protocolParams,
    }: {
        delayedStrategyParams?: Arbitrary<DSP>;
        strategyParams?: Arbitrary<SP>;
        delayedProtocolParams?: Arbitrary<DPP>;
        protocolParams?: Arbitrary<PP>;
        delayedProtocolPerVaultParams?: Arbitrary<DPPV>;
    }
) {
    if (delayedProtocolParams) {
        abstractParamsBehavior.call(this, delayedProtocolParams, {
            delayed: true,
            protocol: true,
            perVault: false,
        });
    }
}

export function abstractParamsBehavior<P, S extends Contract>(
    this: TestContext<S>,
    paramsArb: Arbitrary<P>,
    {
        delayed,
        protocol,
        perVault,
    }: { delayed: boolean; protocol: boolean; perVault: boolean }
) {
    if (delayed) {
        const paramsName = protocol
            ? "DelayedProtocolParams"
            : "DelayedStrategyParams";
        const camelParamsName = protocol
            ? "delayedProtocolParams"
            : "delayedStrategyParams";

        const { someParams, noneParams } = generateParams(paramsArb);
        describe(`#staged${paramsName}`, () => {
            pit(
                "always equals to params that were just staged",
                { numRuns: RUNS.low },
                paramsArb,
                async (params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(params);
                    const actualParams =
                        await this.subject.stagedDelayedProtocolParams();

                    return equals(toObject(actualParams), params);
                }
            );

            it(`returns ${paramsName} staged for commit`, async () => {
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(someParams);
                const actualParams =
                    await this.subject.stagedDelayedProtocolParams();
                expect(actualParams).to.be.equivalent(someParams);
            });

            describe("when no params are staged for commit", () => {
                it("returns zero struct", async () => {
                    const actualParams =
                        await this.subject.stagedDelayedProtocolParams();
                    expect(actualParams).to.equivalent(noneParams);
                });
            });

            describe("when params were just committed", () => {
                it("returns zero struct", async () => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(someParams);
                    await sleep(this.governanceDelay);
                    await this.subject
                        .connect(this.admin)
                        .commitDelayedProtocolParams();
                    const actualParams =
                        await this.subject.stagedDelayedProtocolParams();
                    expect(actualParams).to.equivalent(noneParams);
                });
            });
        });

        describe(`#${camelParamsName}`, () => {
            pit(
                `just staging params doesn't affect ${paramsName}`,
                { numRuns: RUNS.low },
                paramsArb,
                async (params: P) => {
                    await this.subject
                        .connect(this.admin)
                        .stageDelayedProtocolParams(params);
                    const actualParams =
                        await this.subject.delayedProtocolParams();

                    return !equals(toObject(actualParams), params);
                }
            );

            it(`returns current ${paramsName}`, async () => {
                await this.subject
                    .connect(this.admin)
                    .stageDelayedProtocolParams(someParams);
                await sleep(this.governanceDelay);
                await this.subject
                    .connect(this.admin)
                    .commitDelayedProtocolParams();
                const actualParams = await this.subject.delayedProtocolParams();
                expect(actualParams).to.equivalent(someParams);
            });

            describe("when no params were committed", () => {
                it("returns non-zero params initialized in constructor", async () => {
                    const actualParams =
                        await this.subject.delayedProtocolParams();
                    expect(actualParams).to.not.be.equivalent(noneParams);
                });
            });
        });
    }
}
