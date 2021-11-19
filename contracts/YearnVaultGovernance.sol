// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./interfaces/IProtocolGovernance.sol";
import "./interfaces/IYearnVaultGovernance.sol";
import "./VaultGovernance.sol";

/// @notice Governance that manages all Aave Vaults params and can deploy a new Aave Vault.
contract YearnVaultGovernance is IYearnVaultGovernance, VaultGovernance {
    /// @notice Creates a new contract.
    /// @param internalParams_ Initial Internal Params
    /// @param delayedProtocolParams_ Initial Protocol Params
    constructor(InternalParams memory internalParams_, DelayedProtocolParams memory delayedProtocolParams_)
        VaultGovernance(internalParams_)
    {
        _delayedProtocolParams = abi.encode(delayedProtocolParams_);
    }

    function strategyTreasury(uint256 nft) external view override(IVaultGovernance, VaultGovernance) returns (address) {
        return delayedStrategyParams(nft).strategyTreasury;
    }

    /// @inheritdoc IYearnVaultGovernance
    function delayedStrategyParams(uint256 nft) public view returns (DelayedStrategyParams memory) {
        if (_delayedStrategyParams[nft].length == 0) {
            return DelayedStrategyParams({strategyTreasury: address(0)});
        }
        return abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IYearnVaultGovernance
    function stagedDelayedStrategyParams(uint256 nft) external view returns (DelayedStrategyParams memory) {
        if (_stagedDelayedStrategyParams[nft].length == 0) {
            return DelayedStrategyParams({strategyTreasury: address(0)});
        }
        return abi.decode(_stagedDelayedStrategyParams[nft], (DelayedStrategyParams));
    }

    /// @inheritdoc IYearnVaultGovernance
    function stageDelayedStrategyParams(uint256 nft, DelayedStrategyParams calldata params) external {
        _stageDelayedStrategyParams(nft, abi.encode(params));
        emit StageDelayedStrategyParams(tx.origin, msg.sender, nft, params, _delayedStrategyParamsTimestamp[nft]);
    }

    /// @inheritdoc IYearnVaultGovernance
    function commitDelayedStrategyParams(uint256 nft) external {
        _commitDelayedStrategyParams(nft);
        emit CommitDelayedStrategyParams(
            tx.origin,
            msg.sender,
            nft,
            abi.decode(_delayedStrategyParams[nft], (DelayedStrategyParams))
        );
    }

    /// @inheritdoc IYearnVaultGovernance
    function delayedProtocolParams() public view returns (DelayedProtocolParams memory) {
        if (_delayedProtocolParams.length == 0) {
            return DelayedProtocolParams({yearnVaultRegistry: IYearnVaultRegistry(address(0))});
        }
        return abi.decode(_delayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IYearnVaultGovernance
    function stagedDelayedProtocolParams() external view returns (DelayedProtocolParams memory) {
        if (_stagedDelayedProtocolParams.length == 0) {
            return DelayedProtocolParams({yearnVaultRegistry: IYearnVaultRegistry(address(0))});
        }
        return abi.decode(_stagedDelayedProtocolParams, (DelayedProtocolParams));
    }

    /// @inheritdoc IYearnVaultGovernance
    function stageDelayedProtocolParams(DelayedProtocolParams calldata params) external {
        _stageDelayedProtocolParams(abi.encode(params));
        emit StageDelayedProtocolParams(tx.origin, msg.sender, params, _delayedProtocolParamsTimestamp);
    }

    /// @inheritdoc IYearnVaultGovernance
    function commitDelayedProtocolParams() external {
        _commitDelayedProtocolParams();
        emit CommitDelayedProtocolParams(
            tx.origin,
            msg.sender,
            abi.decode(_delayedProtocolParams, (DelayedProtocolParams))
        );
    }

    /// @notice Emitted when new DelayedStrategyParams are staged for commit
    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that were staged for commit
    /// @param when When the params could be committed
    event StageDelayedStrategyParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedStrategyParams params,
        uint256 when
    );

    /// @notice Emitted when new DelayedStrategyParams are committed
    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param nft VaultRegistry NFT of the vault
    /// @param params New params that are committed
    event CommitDelayedStrategyParams(
        address indexed origin,
        address indexed sender,
        uint256 indexed nft,
        DelayedStrategyParams params
    );

    /// @notice Emitted when new DelayedProtocolParams are staged for commit
    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param params New params that were staged for commit
    /// @param when When the params could be committed
    event StageDelayedProtocolParams(
        address indexed origin,
        address indexed sender,
        DelayedProtocolParams params,
        uint256 when
    );

    /// @notice Emitted when new DelayedProtocolParams are committed
    /// @param origin Origin of the transaction
    /// @param sender Sender of the transaction
    /// @param params New params that are committed
    event CommitDelayedProtocolParams(address indexed origin, address indexed sender, DelayedProtocolParams params);
}