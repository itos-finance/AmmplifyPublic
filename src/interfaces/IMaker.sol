// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

interface IMaker {
    // Events
    event MakerCreated(
        address indexed recipient,
        address indexed poolAddr,
        uint256 indexed assetId,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool isCompounding,
        int256 balance0,
        int256 balance1
    );

    event MakerAdjusted(
        address indexed owner,
        uint256 indexed assetId,
        address indexed poolAddr,
        uint128 targetLiq,
        int256 delta0,
        int256 delta1
    );

    event MakerRemoved(
        address indexed recipient,
        uint256 indexed assetId,
        address indexed poolAddr,
        uint256 removedX,
        uint256 removedY
    );

    event FeesCollected(
        address indexed recipient,
        uint256 indexed assetId,
        address indexed poolAddr,
        uint256 fees0,
        uint256 fees1
    );

    // Errors
    error NotMakerOwner(address owner, address sender);
    error NotMaker(uint256 assetId);
    error DeMinimusMaker(uint128 liq);

    /// @notice Creates a new maker position.
    /// @param recipient The recipient of the maker position.
    /// @param poolAddr The address of the pool.
    /// @param lowTick The lower tick of the liquidity range.
    /// @param highTick The upper tick of the liquidity range.
    /// @param liq The amount of liquidity to provide.
    /// @param isCompounding Whether the position is compounding.
    /// @param minSqrtPriceX96 For any price dependent operations, the actual price of the pool must be above this.
    /// @param maxSqrtPriceX96 For any price dependent operations, the actual price of the pool must be below this.
    /// @param rftData Data passed during RFT to the payer.
    function newMaker(
        address recipient,
        address poolAddr,
        int24 lowTick,
        int24 highTick,
        uint128 liq,
        bool isCompounding,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (uint256 _assetId);

    /// @notice Removes a maker position.
    /// @param recipient The recipient of the removed assets.
    /// @param assetId The ID of the asset to remove.
    /// @param minSqrtPriceX96 The minimum sqrt price for the operation.
    /// @param maxSqrtPriceX96 The maximum sqrt price for the operation.
    /// @param rftData Data passed during RFT to the recipient.
    function removeMaker(
        address recipient,
        uint256 assetId,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (address token0, address token1, uint256 removedX, uint256 removedY);

    /// @notice Collects fees from a maker position.
    /// @param recipient The recipient of the collected fees.
    /// @param assetId The ID of the asset to collect fees from.
    /// @param minSqrtPriceX96 The minimum sqrt price for the operation.
    /// @param maxSqrtPriceX96 The maximum sqrt price for the operation.
    /// @param rftData Data passed during RFT to the recipient.
    function collectFees(
        address recipient,
        uint256 assetId,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (uint256 fees0, uint256 fees1);

    /// Either add or remove liq to reach a target liquidity value.
    /// @dev Note that this also collects fees.
    /// @param recipient Who receives tokens when removing liq. Does not get used when adding liq.
    /// @return token0 The lower address token of the pool.
    /// @return token1 The upper address token of the pool.
    /// @return delta0 The change in token0's balance from the perspective of the pool. Positive means the sender paid.
    /// @return delta1 The change in token1's balance from the perspective of the pool. Positive means the sender paid.
    function adjustMaker(
        address recipient,
        uint256 assetId,
        uint128 targetLiq,
        uint160 minSqrtPriceX96,
        uint160 maxSqrtPriceX96,
        bytes calldata rftData
    ) external returns (address token0, address token1, int256 delta0, int256 delta1);

    /// @notice Allow this address to open positions and give you ownership.
    /// @param opener The address that will be allowed to open positions on behalf of the caller.
    function addPermission(address opener) external;

    /// @notice Remove this address from opening positions and giving you ownership.
    /// @param opener The address that will no longer be allowed to open positions on behalf of the caller.
    function removePermission(address opener) external;
}
