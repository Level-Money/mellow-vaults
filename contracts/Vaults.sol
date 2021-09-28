// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./access/GovernanceAccessControl.sol";
import "./interfaces/IVaults.sol";
import "./libraries/Array.sol";
import "./VaultsGovernance.sol";

abstract contract Vaults is IVaults, GovernanceAccessControl, ERC721, VaultsGovernance {
    using SafeERC20 for IERC20;

    mapping(uint256 => address[]) private _managedTokens;
    mapping(uint256 => mapping(address => bool)) private _managedTokensIndex;
    uint256 public topVaultNft = 1;

    constructor(
        string memory name,
        string memory symbol,
        address _protocolGovernance
    ) ERC721(name, symbol) VaultsGovernance(_protocolGovernance) {}

    /// -------------------  PUBLIC, VIEW  -------------------

    function managedTokens(uint256 nft) public view override returns (address[] memory) {
        return _managedTokens[nft];
    }

    function isManagedToken(uint256 nft, address token) public view override returns (bool) {
        return _managedTokensIndex[nft][token];
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, IERC165, AccessControlEnumerable)
        returns (bool)
    {
        return interfaceId == type(IVaults).interfaceId || super.supportsInterface(interfaceId);
    }

    function vaultTVL(uint256 nft)
        external
        view
        virtual
        returns (address[] memory tokens, uint256[] memory tokenAmounts);

    /// -------------------  PUBLIC, MUTATING, GOVERNANCE OR PERMISSIONLESS  -------------------
    function createVault(address[] memory cellTokens, bytes memory params) external override returns (uint256) {
        require(permissionless || _isGovernanceOrDelegate(), "PGD");
        require(cellTokens.length <= protocolGovernance.maxTokensPerVault(), "MT");
        require(Array.isSortedAndUnique(cellTokens), "SAU");
        uint256 nft = _mintVaultNft(cellTokens, params);
        _managedTokens[nft] = cellTokens;
        for (uint256 i = 0; i < cellTokens.length; i++) {
            _managedTokensIndex[nft][cellTokens[i]] = true;
        }
        emit IVaults.CreateVault(_msgSender(), nft, params);
        return nft;
    }

    /// -------------------  PUBLIC, MUTATING, NFT OWNER OR APPROVED  -------------------
    /// tokens are used from contract balance
    function push(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) public returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        (address[] memory pTokens, uint256[] memory pTokenAmounts) = _validateAndProjectTokens(
            nft,
            tokens,
            tokenAmounts
        );
        uint256[] memory pActualTokenAmounts = _push(nft, pTokens, pTokenAmounts);
        actualTokenAmounts = Array.projectTokenAmounts(tokens, pTokens, pActualTokenAmounts);
    }

    function transferAndPush(
        uint256 nft,
        address from,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokenAmounts[i] > 0) {
                IERC20(tokens[i]).safeTransferFrom(from, address(this), tokenAmounts[i]);
            }
        }
        actualTokenAmounts = push(nft, tokens, tokenAmounts);
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 leftover = actualTokenAmounts[i] < tokenAmounts[i] ? tokenAmounts[i] - actualTokenAmounts[i] : 0;
            if (leftover > 0) {
                IERC20(tokens[i]).safeTransfer(from, leftover);
            }
        }
    }

    function pull(
        uint256 nft,
        address to,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) external returns (uint256[] memory actualTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        (address[] memory pTokens, uint256[] memory pTokenAmounts) = _validateAndProjectTokens(
            nft,
            tokens,
            tokenAmounts
        );
        uint256[] memory pActualTokenAmounts = _pull(nft, to, pTokens, pTokenAmounts);
        actualTokenAmounts = Array.projectTokenAmounts(tokens, pTokens, pActualTokenAmounts);
        emit Pull(nft, to, tokens, actualTokenAmounts);
    }

    function reclaimTokens(address to, address[] calldata tokens) external {
        require(_isGovernanceOrDelegate(), "GD");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.safeTransfer(to, token.balanceOf(address(this)));
        }
    }

    /// -------------------  PRIVATE, VIEW  -------------------

    function _validateAndProjectTokens(
        uint256 nft,
        address[] calldata tokens,
        uint256[] calldata tokenAmounts
    ) internal view returns (address[] memory pTokens, uint256[] memory pTokenAmounts) {
        require(_isApprovedOrOwner(_msgSender(), nft), "IO"); // Also checks that the token exists
        require(Array.isSortedAndUnique(tokens), "SAU");
        require(tokens.length == tokenAmounts.length, "L");
        pTokens = managedTokens(nft);
        pTokenAmounts = Array.projectTokenAmounts(pTokens, tokens, tokenAmounts);
    }

    /// -------------------  PRIVATE, MUTATING  -------------------

    function _mintVaultNft(address[] memory, bytes memory) internal virtual returns (uint256) {
        uint256 nft = topVaultNft;
        topVaultNft += 1;
        _safeMint(_msgSender(), nft);
        return nft;
    }

    /// Guaranteed to have exact signature matching managed tokens
    function _push(
        uint256 nft,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) internal virtual returns (uint256[] memory actualTokenAmounts);

    /// Guaranteed to have exact signature matching managed tokens
    function _pull(
        uint256 nft,
        address to,
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) internal virtual returns (uint256[] memory actualTokenAmounts);
}