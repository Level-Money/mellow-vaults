// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "../interfaces/IVault.sol";
import "../interfaces/IERC20Vault.sol";
import "../interfaces/external/univ3/IUniswapV3Pool.sol";
import "../interfaces/external/univ3/ISwapRouter.sol";
import "../libraries/CommonLibrary.sol";
import "../libraries/StrategyLibrary.sol";
import "../libraries/external/FullMath.sol";
import "../DefaultAccessControl.sol";

contract MStrategy is DefaultAccessControl {
    struct Params {
        uint256 oraclePriceTimespan;
        uint256 oracleLiquidityTimespan;
        uint256 liquidToFixedRatioX96;
        uint256 sqrtPMinX96;
        uint256 sqrtPMaxX96;
        uint256 tokenRebalanceThresholdX96;
        uint256 poolRebalanceThresholdX96;
    }

    struct ImmutableParams {
        address token0;
        address token1;
        IUniswapV3Pool uniV3Pool;
        ISwapRouter uniV3Router;
        IERC20Vault erc20Vault;
        IVault moneyVault;
    }

    Params[] public vaultParams;
    ImmutableParams[] public vaultImmutableParams;
    mapping(address => mapping(address => uint256)) public vaultIndex;
    mapping(uint256 => bool) public disabled;
    uint256 public vaultCount;

    constructor(address owner) DefaultAccessControl(owner) {}

    mapping(address => mapping(address => uint256)) public paramsIndex;

    function shouldRebalance(uint256 id) external view returns (bool) {
        Params storage params = vaultParams[id];
        ImmutableParams storage immutableParams = vaultImmutableParams[id];
        IUniswapV3Pool pool = immutableParams.uniV3Pool;
        IERC20Vault erc20Vault = immutableParams.erc20Vault;
        uint256[] memory erc20Tvl = erc20Vault.tvl();
        uint256[] memory moneyTvl = immutableParams.moneyVault.tvl();
        uint256[2] memory tvl = [erc20Tvl[0] + moneyTvl[0], erc20Tvl[1] + moneyTvl[1]];

        for (uint256 i = 0; i < 2; i++) {
            uint256 currentRatioX96 = FullMath.mulDiv(erc20Tvl[i], CommonLibrary.Q96, moneyTvl[i]);
            uint256 deviation = CommonLibrary.deviationFactor(currentRatioX96, params.liquidToFixedRatioX96);
            if (deviation > params.poolRebalanceThresholdX96) {
                return true;
            }
        }
        {
            (uint256 sqrtPriceX96, , ) = StrategyLibrary.getUniV3Averages(pool, params.oraclePriceTimespan);

            uint256 currentRatioX96 = FullMath.mulDiv(tvl[1], CommonLibrary.Q96, tvl[0]);
            uint256 targetTokenRatioX96 = targetRatioX96(sqrtPriceX96, params.sqrtPMinX96, params.sqrtPMaxX96);
            uint256 deviation = CommonLibrary.deviationFactor(currentRatioX96, targetTokenRatioX96);
            if (deviation > params.tokenRebalanceThresholdX96) {
                return true;
            }
        }
        return false;
    }

    function rebalance(uint256 id) external {
        require(id < vaultCount, "VE");
        require(!disabled[id], "DIS");
        Params storage params = vaultParams[id];
        ImmutableParams storage immutableParams = vaultImmutableParams[id];
        IUniswapV3Pool pool = immutableParams.uniV3Pool;
        IERC20Vault erc20Vault = immutableParams.erc20Vault;
        IVault moneyVault = immutableParams.moneyVault;
        address[] memory tokens = erc20Vault.vaultTokens();
        uint256[] memory erc20Tvl = erc20Vault.tvl();
        uint256[] memory moneyTvl = immutableParams.moneyVault.tvl();
        uint256[2] memory tvl = [erc20Tvl[0] + moneyTvl[0], erc20Tvl[1] + moneyTvl[1]];
        _rebalanceTokens(tvl, pool, erc20Vault, params);
        _rebalancePools(
            erc20Tvl,
            moneyTvl,
            tokens,
            params.liquidToFixedRatioX96,
            params.poolRebalanceThresholdX96,
            erc20Vault,
            moneyVault
        );
    }

    function _rebalancePools(
        uint256[] memory erc20Tvl,
        uint256[] memory moneyTvl,
        address[] memory tokens,
        uint256 liquidToFixedRatioX96,
        uint256 poolRebalanceThresholdX96,
        IVault erc20Vault,
        IVault moneyVault
    ) internal {
        uint256[] memory erc20Amounts = new uint256[](2);
        uint256[] memory moneyAmounts = new uint256[](2);
        bool[] memory zeroForOnes = new bool[](2);
        for (uint256 i = 0; i < 2; i++) {
            (uint256 amountIn, bool zeroForOne) = _calcRebalancePoolAmount(
                erc20Tvl[i],
                moneyTvl[i],
                liquidToFixedRatioX96,
                poolRebalanceThresholdX96
            );
            zeroForOnes[i] = zeroForOne;
            if (zeroForOne) {
                erc20Amounts[i] = amountIn;
            } else {
                moneyAmounts[i] = amountIn;
            }
        }
        if (zeroForOnes[0] || zeroForOnes[1]) {
            if ((erc20Amounts[0] > 0) || (erc20Amounts[1] > 0)) {
                erc20Vault.pull(address(moneyVault), tokens, erc20Amounts, "");
            }
        }
        if (!zeroForOnes[0] || !zeroForOnes[1]) {
            if ((moneyAmounts[0] > 0) || (moneyAmounts[1] > 0)) {
                moneyVault.pull(address(erc20Vault), tokens, moneyAmounts, "");
            }
        }
    }

    function _calcRebalancePoolAmount(
        uint256 tvl0,
        uint256 tvl1,
        uint256 liquidToFixedRatioX96,
        uint256 poolRebalanceThresholdX96
    ) internal pure returns (uint256 amountIn, bool zeroForOne) {
        uint256 currentRatioX96 = FullMath.mulDiv(tvl1, CommonLibrary.Q96, tvl0);
        uint256 deviation = CommonLibrary.deviationFactor(currentRatioX96, liquidToFixedRatioX96);
        if (deviation > poolRebalanceThresholdX96) {
            (amountIn, zeroForOne) = StrategyLibrary.swapToTargetWithoutSlippage(
                liquidToFixedRatioX96,
                CommonLibrary.Q96,
                tvl0,
                tvl1,
                0
            );
        }
    }

    function _rebalanceTokens(
        uint256[2] memory tvl,
        IUniswapV3Pool pool,
        IERC20Vault erc20Vault,
        Params storage params
    ) internal {
        (uint256 sqrtPriceX96, uint256 liquidity, ) = StrategyLibrary.getUniV3Averages(
            pool,
            params.oraclePriceTimespan
        );
        uint256 deviation;
        uint256 targetTokenRatioX96 = targetRatioX96(sqrtPriceX96, params.sqrtPMinX96, params.sqrtPMaxX96);
        {
            uint256 currentRatioX96 = FullMath.mulDiv(tvl[1], CommonLibrary.Q96, tvl[0]);
            deviation = CommonLibrary.deviationFactor(currentRatioX96, targetTokenRatioX96);
        }

        if (deviation > params.tokenRebalanceThresholdX96) {
            ITrader.PathItem[] memory path = new ITrader.PathItem[](1);
            uint256 amountIn;
            {
                bool zeroForOne;
                uint256 poolFee = pool.fee();
                (amountIn, zeroForOne) = StrategyLibrary.swapToTargetWithSlippage(
                    targetTokenRatioX96,
                    sqrtPriceX96,
                    tvl[0],
                    tvl[1],
                    poolFee,
                    liquidity
                );
                (address tokenIn, address tokenOut) = (pool.token0(), pool.token1());
                if (!zeroForOne) {
                    (tokenIn, tokenOut) = (tokenOut, tokenIn);
                }

                bytes memory poolOptions = new bytes(32);
                assembly {
                    mstore(add(poolOptions, 32), poolFee)
                }
                path[0] = ITrader.PathItem({token0: tokenIn, token1: tokenOut, options: poolOptions});
            }
            erc20Vault.swapExactInput(0, amountIn, address(erc20Vault), path, "");
        }
    }

    function targetRatioX96(
        uint256 sqrtPriceX96,
        uint256 sqrtPMinX96,
        uint256 sqrtPMaxX96
    ) public pure returns (uint256) {
        if (sqrtPriceX96 <= sqrtPMinX96) {
            return 0;
        }
        if (sqrtPriceX96 >= sqrtPMaxX96) {
            return CommonLibrary.Q96;
        }
        return FullMath.mulDiv(sqrtPriceX96 - sqrtPMinX96, CommonLibrary.Q96, sqrtPMaxX96 - sqrtPMinX96);
    }

    function addVault(ImmutableParams memory immutableParams_, Params memory params_) external {
        require(isAdmin(msg.sender), "ADM");
        address token0 = immutableParams_.token0;
        address token1 = immutableParams_.token1;
        require(immutableParams_.uniV3Pool.token0() == token0, "T0");
        require(immutableParams_.uniV3Pool.token1() == token1, "T1");
        require(paramsIndex[token0][token1] == 0, "EXST");
        IVault[2] memory vaults = [immutableParams_.erc20Vault, immutableParams_.moneyVault];
        for (uint256 i = 0; i < vaults.length; i++) {
            IVault vault = vaults[i];
            address[] memory tokens = vault.vaultTokens();
            require(tokens[0] == token0, "VT0");
            require(tokens[1] == token1, "VT1");
        }
        vaultParams.push(params_);
        uint256 num = vaultParams.length;
        vaultImmutableParams.push(immutableParams_);
        paramsIndex[token0][token1] = num;
        paramsIndex[token1][token0] = num;
        vaultCount += 1;
        emit VaultAdded(tx.origin, msg.sender, num, immutableParams_, params_);
    }

    function disableVault(uint256 id, bool disabled_) external {
        require(isAdmin(msg.sender), "ADM");
        require(id < vaultCount, "VE");
        disabled[id] = disabled_;
        emit VaultDisabled(tx.origin, msg.sender, id, disabled_);
    }

    function updateVaultParams(uint256 id, Params memory params) external {
        require(isAdmin(msg.sender), "ADM");
        require(id < vaultCount, "VE");
        require(!disabled[id], "DIS");
        vaultParams[id] = params;
        emit VaultParamsUpdated(tx.origin, msg.sender, id, params);
    }

    event VaultAdded(
        address indexed origin,
        address indexed sender,
        uint256 id,
        ImmutableParams immutableParams,
        Params params
    );

    event VaultDisabled(address indexed origin, address indexed sender, uint256 num, bool disabled);
    event VaultParamsUpdated(address indexed origin, address indexed sender, uint256 id, Params params);
}