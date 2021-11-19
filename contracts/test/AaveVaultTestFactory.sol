// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "../interfaces/IVaultFactory.sol";
import "../interfaces/IVaultFactory.sol";
import "./AaveVaultTest.sol";

contract AaveVaultTestFactory is IVaultFactory {
    IVaultGovernance public vaultGovernance;

    constructor(IVaultGovernance vaultGovernance_) {
        vaultGovernance = vaultGovernance_;
    }

    function setVaultGovernance(address newVaultGovernance) public {
        vaultGovernance = IVaultGovernance(newVaultGovernance);
    }

    function deployVault(address[] memory vaultTokens, bytes memory) external returns (IVault) {
        require(msg.sender == address(vaultGovernance), "VG");
        AaveVaultTest vault = new AaveVaultTest(vaultGovernance, vaultTokens);
        return IVault(vault);
    }
}