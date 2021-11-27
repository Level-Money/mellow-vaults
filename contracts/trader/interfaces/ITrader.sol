// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// When trading from a smart contract, the most important thing to keep in mind is that
// access to an external price source is required. Without this, trades can be frontrun for considerable loss.

interface ITrader {
    /// @notice Trade path element
    /// @param token0 The token to be sold
    /// @param token1 The token to be bought
    /// @param options Protocol-specific options
    struct PathItem {
        address token0;
        address token1;
        bytes options;
    }

    /// @notice Swap exact amount of input tokens for output tokens
    /// @param traderId Trader ID (used only by Chief trader)
    /// @param input Address of the input token
    /// @param output Address of the output token
    /// @param amount Amount of the input tokens to spend
    /// @param recipient Address of the recipient (not used by Chief trader)
    /// @param path Trade path
    /// @param options Protocol-speceific options
    /// @return amountOut Amount of the output tokens received
    function swapExactInput(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        address recipient,
        PathItem[] calldata path,
        bytes calldata options
    ) external returns (uint256 amountOut);

    /// @notice Swap exact amount of input tokens for output tokens
    /// @param traderId Trader ID (used only by Chief trader)
    /// @param input Address of the input token
    /// @param output Address of the output token
    /// @param amount Amount of the output tokens to receive
    /// @param recipient Address of the recipient (not used by Chief trader)
    /// @param path Trade path
    /// @param options Protocol-speceific options
    /// @return amountIn of the input tokens spent
    function swapExactOutput(
        uint256 traderId,
        address input,
        address output,
        uint256 amount,
        address recipient,
        PathItem[] calldata path,
        bytes calldata options
    ) external returns (uint256 amountIn);
}
