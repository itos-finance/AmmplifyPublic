// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.27;

import { IERC20 } from "Commons/ERC/interfaces/IERC20.sol";
import { ForkableTest } from "Commons/Test/ForkableTest.sol";
import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";
import { UniswapV3Pool } from "v3-core/UniswapV3Pool.sol";
import { IUniswapV3Factory } from "v3-core/interfaces/IUniswapV3Factory.sol";
import { TickMath } from "v3-core/libraries/TickMath.sol";
import { ISwapRouter } from "../mocks/nfpm/interfaces/ISwapRouter.sol";

import { SimplexDiamond } from "../../src/Diamond.sol";
import { AdminFacet } from "../../src/facets/Admin.sol";
import { MakerFacet } from "../../src/facets/Maker.sol";
import { TakerFacet } from "../../src/facets/Taker.sol";
import { PoolFacet } from "../../src/facets/Pool.sol";
import { ViewFacet } from "../../src/facets/View.sol";
import { UniV3Decomposer } from "../../src/integrations/UniV3Decomposer.sol";
import {
    INonfungiblePositionManager
} from "../../src/integrations/univ3-periphery/interfaces/INonfungiblePositionManager.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

/**
 * @title AmmplifyForkBase
 * @notice Base contract for fork testing Uniswap V3 with Ammplify
 * @dev Extends ForkableTest to provide Uniswap V3 specific helper functions
 */
contract AmmplifyForkBase is ForkableTest {
    // Uniswap V3 contracts
    IUniswapV3Factory public factory;
    INonfungiblePositionManager public nftManager;
    IUniswapV3Pool public pool;
    ISwapRouter public router;

    // Ammplify contracts
    SimplexDiamond public diamond;

    // Helper contracts
    UniV3Decomposer public decomposer;

    // Test tokens
    IERC20 public token0;
    IERC20 public token1;

    // Token creation tracking
    bool public tokensCreated;

    // Position tracking
    uint256 public nextTokenId = 1;
    mapping(uint256 => PositionInfo) public positions;

    struct PositionInfo {
        address owner;
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0;
        uint256 amount1;
    }

    // Constants for common fee tiers
    uint24 public constant FEE_TIER_500 = 500; // 0.05%
    uint24 public constant FEE_TIER_3000 = 3000; // 0.3%
    uint24 public constant FEE_TIER_10000 = 10000; // 1%

    // Common tick ranges
    int24 public constant TICK_SPACING_500 = 10;
    int24 public constant TICK_SPACING_3000 = 60;
    int24 public constant TICK_SPACING_10000 = 200;

    function forkSetup() internal virtual override {
        // Load addresses from fork JSON
        factory = IUniswapV3Factory(getAddr("factory"));

        // Try to load nfpm, fallback to NFT_MANAGER for backwards compatibility
        address nfpmAddr = _tryGetAddr("nfpm");
        if (nfpmAddr != address(0)) {
            nftManager = INonfungiblePositionManager(nfpmAddr);
        } else {
            nfpmAddr = _tryGetAddr("NFT_MANAGER");
            if (nfpmAddr != address(0)) {
                nftManager = INonfungiblePositionManager(nfpmAddr);
            } else {
                revert("NFT Manager address not found in JSON");
            }
        }

        // Load router from JSON
        address routerAddr = _tryGetAddr("router");
        if (routerAddr != address(0)) {
            router = ISwapRouter(routerAddr);
        }

        // Try to load tokens first, create if they don't exist
        // This must happen before pool creation
        _loadOrCreateTokens();

        // Try to load pool from pools object, or fallback to POOL key
        address poolAddr = _tryGetPoolAddress();
        if (poolAddr != address(0)) {
            pool = IUniswapV3Pool(poolAddr);
            // Update token0 and token1 to match the pool's ordering
            token0 = IERC20(pool.token0());
            token1 = IERC20(pool.token1());
        } else {
            // Pool doesn't exist, we'll need to create it
            pool = _createPoolIfNeeded();
        }

        // Deploy facets first
        AdminFacet adminFacetInstance = new AdminFacet();
        MakerFacet makerFacetInstance = new MakerFacet();
        TakerFacet takerFacetInstance = new TakerFacet();
        PoolFacet poolFacetInstance = new PoolFacet();
        ViewFacet viewFacetInstance = new ViewFacet();

        // Create facet addresses struct
        SimplexDiamond.FacetAddresses memory facetAddresses = SimplexDiamond.FacetAddresses({
            adminFacet: address(adminFacetInstance),
            makerFacet: address(makerFacetInstance),
            takerFacet: address(takerFacetInstance),
            poolFacet: address(poolFacetInstance),
            viewFacet: address(viewFacetInstance)
        });

        // Deploy diamond with factory address and facet addresses from JSON
        diamond = new SimplexDiamond(address(factory), facetAddresses);
        decomposer = new UniV3Decomposer(address(nftManager), address(diamond));

        // Increase pool observation cardinality to minimum required (32)
        _increasePoolCardinality();
    }

    /**
     * @notice Increase pool observation cardinality to minimum required
     * @dev Pools need at least 32 observations for TWAP calculations
     */
    function _increasePoolCardinality() internal {
        uint16 minObservations = 32;
        UniswapV3Pool(address(pool)).increaseObservationCardinalityNext(minObservations);

        // Perform a small swap to populate observations
        // This is necessary because increaseObservationCardinalityNext only sets the target,
        // but observations are populated as swaps occur
        _performObservationSwap();
    }

    /**
     * @notice Perform a small swap to populate pool observations
     * @dev This swap helps populate the observation array after increasing cardinality
     */
    function _performObservationSwap() internal {
        // Check if router is available
        if (address(router) == address(0)) {
            revert("Router address not found in JSON. Cannot perform observation swap.");
        }

        // Check if pool has liquidity first
        uint128 poolLiquidity = pool.liquidity();
        if (poolLiquidity == 0) {
            // No liquidity in pool, cannot perform swap
            // This means initial liquidity addition failed - revert with clear error
            revert(
                "Cannot perform observation swap: pool has no liquidity. Initial liquidity addition may have failed."
            );
        }

        // Get pool fee
        uint24 poolFee = pool.fee();

        // Perform a very small swap (1 wei) to trigger observation recording
        // We'll swap token0 for token1
        uint256 amountIn = 1; // 1 wei

        // Fund this contract with a small amount of token0 if needed
        if (token0.balanceOf(address(this)) < 1000) {
            deal(address(token0), address(this), 1000);
        }

        // Approve router to take tokens
        require(token0.approve(address(router), 1000), "Token0 approval failed");

        // Perform the swap using router
        try
            router.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: address(token0),
                    tokenOut: address(token1),
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp + 300, // 5 minutes
                    amountIn: amountIn,
                    amountOutMinimum: 0, // Accept any amount out
                    sqrtPriceLimitX96: 0 // No price limit
                })
            )
        returns (uint256 /* amountOut */) {
            // Swap succeeded
            // amountOut is the amount of token1 received
        } catch (bytes memory reason) {
            // If swap fails, try the other direction
            if (token1.balanceOf(address(this)) < 1000) {
                deal(address(token1), address(this), 1000);
            }
            require(token1.approve(address(router), 1000), "Token1 approval failed");
            try
                router.exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: address(token1),
                        tokenOut: address(token0),
                        fee: poolFee,
                        recipient: address(this),
                        deadline: block.timestamp + 300,
                        amountIn: amountIn,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                )
            returns (uint256 /* amountOut */) {
                // Swap succeeded in reverse direction
            } catch (bytes memory reason2) {
                // If both directions fail, revert with error message
                revert(
                    string(
                        abi.encodePacked(
                            "Observation swap failed in both directions. Reason1: ",
                            reason,
                            " Reason2: ",
                            reason2
                        )
                    )
                );
            }
        }
    }

    /**
     * @notice Try to get an address from JSON, returning address(0) if not found
     * @param key The JSON key to look up
     * @return addr The address, or address(0) if not found
     */
    function _tryGetAddr(string memory key) internal view returns (address addr) {
        try this._getAddrInternal(key) returns (address a) {
            return a;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Internal helper to get address (needed for try/catch)
     */
    function _getAddrInternal(string memory key) external view returns (address) {
        return getAddr(key);
    }

    /**
     * @notice Try to get pool address from JSON, checking pools object first
     * @return poolAddr The pool address, or address(0) if not found
     */
    function _tryGetPoolAddress() internal view returns (address poolAddr) {
        // First try the old POOL key for backwards compatibility
        poolAddr = _tryGetAddr("POOL");
        if (poolAddr != address(0)) {
            return poolAddr;
        }

        // Try reading from pools object (e.g., pools.USDC_WETH_3000)
        // Read the JSON file directly to access nested values
        string memory jsonPath = _getJsonPath();
        if (bytes(jsonPath).length > 0) {
            string memory json = vm.readFile(jsonPath);
            // Try common pool names
            poolAddr = _tryParseJsonAddress(json, ".pools.USDC_WETH_3000");
            if (poolAddr != address(0) && poolAddr != address(0x0000000000000000000000000000000000000000)) {
                return poolAddr;
            }
            // Try other common patterns
            poolAddr = _tryParseJsonAddress(json, ".pools.WETH_USDC_3000");
            if (poolAddr != address(0) && poolAddr != address(0x0000000000000000000000000000000000000000)) {
                return poolAddr;
            }
        }

        return address(0);
    }

    /**
     * @notice Get the JSON file path from environment
     * @return jsonPath The path to the JSON file
     */
    function _getJsonPath() internal view returns (string memory jsonPath) {
        try vm.envString("DEPLOYED_ADDRS_PATH") returns (string memory pathToAddrs) {
            string memory projectRoot = string.concat(vm.projectRoot(), "/");
            return string.concat(projectRoot, pathToAddrs);
        } catch {
            return "";
        }
    }

    /**
     * @notice Try to parse an address from JSON
     * @param json The JSON string
     * @param key The JSON key path
     * @return addr The address, or address(0) if not found or invalid
     */
    function _tryParseJsonAddress(string memory json, string memory key) internal pure returns (address addr) {
        try vm.parseJsonAddress(json, key) returns (address a) {
            return a;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Load or create tokens from JSON
     */
    function _loadOrCreateTokens() internal {
        // Try to load existing tokens
        address token0Addr = _tryGetAddr("token0");
        if (token0Addr != address(0)) {
            token0 = IERC20(token0Addr);
        }

        address token1Addr = _tryGetAddr("token1");
        if (token1Addr != address(0)) {
            token1 = IERC20(token1Addr);
        }

        // If tokens weren't loaded, create them
        if (address(token0) == address(0) || address(token1) == address(0)) {
            _createTokens();
        }
    }

    /**
     * @notice Create MockERC20 tokens for testing
     * @dev Creates two tokens with standard names and 18 decimals
     */
    function _createTokens() internal {
        if (address(token0) == address(0)) {
            token0 = IERC20(address(new MockERC20("Token0", "TKN0", 18)));
        }
        if (address(token1) == address(0)) {
            token1 = IERC20(address(new MockERC20("Token1", "TKN1", 18)));
        }
        tokensCreated = true;
    }

    /**
     * @notice Create and initialize a Uniswap V3 pool if it doesn't exist
     * @return pool The created or existing pool
     */
    function _createPoolIfNeeded() internal returns (IUniswapV3Pool) {
        // Tokens should already be loaded/created by _loadOrCreateTokens()
        require(
            address(token0) != address(0) && address(token1) != address(0),
            "Tokens must be loaded or created first"
        );

        // Get fee tier (default to 3000 = 0.3%)
        uint24 fee = 3000;

        // Check if pool already exists
        address poolAddr = factory.getPool(address(token0), address(token1), fee);
        if (poolAddr != address(0)) {
            IUniswapV3Pool existingPool = IUniswapV3Pool(poolAddr);
            // Update token0 and token1 to match the pool's ordering
            token0 = IERC20(existingPool.token0());
            token1 = IERC20(existingPool.token1());
            // Set the pool variable
            pool = existingPool;
            return existingPool;
        }

        // Create the pool
        // Ensure token0 < token1 for Uniswap V3
        address tokenA = address(token0) < address(token1) ? address(token0) : address(token1);
        address tokenB = address(token0) < address(token1) ? address(token1) : address(token0);

        poolAddr = factory.createPool(tokenA, tokenB, fee);
        IUniswapV3Pool newPool = IUniswapV3Pool(poolAddr);

        // Initialize the pool with a default price (1:1 ratio)
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(0);
        newPool.initialize(sqrtPriceX96);

        // Update token0 and token1 to match the pool's ordering
        token0 = IERC20(newPool.token0());
        token1 = IERC20(newPool.token1());

        // Set the pool variable before adding liquidity
        pool = newPool;

        // Add initial liquidity to the pool
        _addInitialLiquidity(newPool);

        return newPool;
    }

    /**
     * @notice Add initial liquidity to a newly created pool
     * @param poolToAddLiquidity The pool to add liquidity to
     */
    function _addInitialLiquidity(IUniswapV3Pool poolToAddLiquidity) internal {
        // Get tick spacing for the pool
        int24 tickSpacing = poolToAddLiquidity.tickSpacing();

        // Calculate min and max ticks (aligned to tick spacing)
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        // Fund this contract with tokens for initial liquidity
        // We'll use amounts that should work at 1:1 price (tick 0)
        uint256 amount0Desired = 1e18; // 1 token0 (assuming 18 decimals)
        uint256 amount1Desired = 1e18; // 1 token1 (assuming 18 decimals)

        // Ensure we have enough tokens
        if (token0.balanceOf(address(this)) < amount0Desired) {
            deal(address(token0), address(this), amount0Desired * 2);
        }
        if (token1.balanceOf(address(this)) < amount1Desired) {
            deal(address(token1), address(this), amount1Desired * 2);
        }

        // Roll forward time by 300 seconds before minting
        // This is needed for pool observations and time-based checks
        vm.warp(block.timestamp + 300);

        // Use createPosition to add liquidity via NFT manager
        // This handles all the complexity including callbacks
        createPosition(
            minTick,
            maxTick,
            amount0Desired,
            amount1Desired,
            address(this) // recipient - this contract
        );
    }

    /**
     * @notice Create a pool with custom parameters (public function for manual pool creation)
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param fee Fee tier (500, 3000, or 10000)
     * @param sqrtPriceX96 Initial sqrt price (use TickMath.getSqrtRatioAtTick() to convert from tick)
     * @return newPool The created pool
     */
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee,
        uint160 sqrtPriceX96
    ) public returns (IUniswapV3Pool newPool) {
        require(tokenA != tokenB, "Tokens must be different");
        require(tokenA != address(0) && tokenB != address(0), "Tokens cannot be zero address");

        // Ensure token0 < token1 for Uniswap V3
        address token0Addr = tokenA < tokenB ? tokenA : tokenB;
        address token1Addr = tokenA < tokenB ? tokenB : tokenA;

        // Check if pool already exists
        address poolAddr = factory.getPool(token0Addr, token1Addr, fee);
        require(poolAddr == address(0), "Pool already exists");

        // Create the pool
        poolAddr = factory.createPool(token0Addr, token1Addr, fee);
        newPool = IUniswapV3Pool(poolAddr);

        // Initialize the pool
        newPool.initialize(sqrtPriceX96);

        // Update instance variables if this is the main pool
        if (address(pool) == address(0)) {
            pool = newPool;
            token0 = IERC20(newPool.token0());
            token1 = IERC20(newPool.token1());
        }
    }

    /**
     * @notice Get pool fee from JSON or use default
     * @return fee The fee tier (defaults to 3000 = 0.3%)
     */
    function _getPoolFee() internal view returns (uint24 fee) {
        // Try to read fee from JSON, default to 3000
        string memory jsonPath = _getJsonPath();
        if (bytes(jsonPath).length > 0) {
            string memory json = vm.readFile(jsonPath);
            try vm.parseJsonUint(json, ".poolFee") returns (uint256 feeValue) {
                return uint24(feeValue);
            } catch {
                // Try reading from pools object
                try vm.parseJsonUint(json, ".pools.USDC_WETH_3000.fee") returns (uint256 feeValue) {
                    return uint24(feeValue);
                } catch {
                    // Default to 3000
                }
            }
        }
        return FEE_TIER_3000;
    }

    function deploySetup() internal virtual override {
        // For local testing without forking
        // This would deploy mock contracts
        // revert("Local setup not implemented - use forking");
    }

    /**
     * @notice Create a new Uniswap V3 position
     * @param tickLower Lower tick boundary
     * @param tickUpper Upper tick boundary
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @param recipient Recipient of the position NFT
     * @return tokenId The NFT token ID
     * @return liquidity The liquidity amount
     * @return amount0 Actual amount of token0 used
     * @return amount1 Actual amount of token1 used
     */
    function createPosition(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        address recipient
    ) internal returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        // Approve tokens
        token0.approve(address(nftManager), amount0Desired);
        token1.approve(address(nftManager), amount1Desired);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: pool.fee(),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient,
            deadline: block.timestamp + 3600
        });

        (tokenId, liquidity, amount0, amount1) = nftManager.mint(params);

        // Store position info
        positions[tokenId] = PositionInfo({
            owner: recipient,
            liquidity: liquidity,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0: amount0,
            amount1: amount1
        });

        nextTokenId = tokenId + 1;
    }

    /**
     * @notice Increase liquidity of an existing position
     * @param tokenId The position NFT ID
     * @param amount0Desired Desired amount of token0
     * @param amount1Desired Desired amount of token1
     * @return liquidity New liquidity amount
     * @return amount0 Actual amount of token0 used
     * @return amount1 Actual amount of token1 used
     */
    function increasePositionLiquidity(
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        // Approve tokens
        token0.approve(address(nftManager), amount0Desired);
        token1.approve(address(nftManager), amount1Desired);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 3600
            });

        (liquidity, amount0, amount1) = nftManager.increaseLiquidity(params);

        // Update stored position info
        PositionInfo storage pos = positions[tokenId];
        pos.liquidity += liquidity;
        pos.amount0 += amount0;
        pos.amount1 += amount1;
    }

    /**
     * @notice Decrease liquidity of an existing position
     * @param tokenId The position NFT ID
     * @param liquidityAmount Amount of liquidity to remove
     * @return amount0 Amount of token0 returned
     * @return amount1 Amount of token1 returned
     */
    function decreasePositionLiquidity(
        uint256 tokenId,
        uint128 liquidityAmount
    ) internal returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidityAmount,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 3600
            });

        (amount0, amount1) = nftManager.decreaseLiquidity(params);

        // Update stored position info
        PositionInfo storage pos = positions[tokenId];
        pos.liquidity -= liquidityAmount;
        pos.amount0 -= amount0;
        pos.amount1 -= amount1;
    }

    /**
     * @notice Collect fees from a position
     * @param tokenId The position NFT ID
     * @param recipient Recipient of collected fees
     * @return amount0 Amount of token0 collected
     * @return amount1 Amount of token1 collected
     */
    function collectPositionFees(
        uint256 tokenId,
        address recipient
    ) internal returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: recipient,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nftManager.collect(params);
    }

    /**
     * @notice Burn a position NFT (removes all liquidity)
     * @param tokenId The position NFT ID
     */
    function burnPosition(uint256 tokenId) internal {
        // First decrease all liquidity
        PositionInfo storage pos = positions[tokenId];
        if (pos.liquidity > 0) {
            decreasePositionLiquidity(tokenId, pos.liquidity);
        }

        // Collect any remaining fees
        collectPositionFees(tokenId, address(this));

        // Burn the NFT
        nftManager.burn(tokenId);

        // Remove from tracking
        delete positions[tokenId];
    }

    /**
     * @notice Get tick spacing for a given fee tier
     * @param fee The fee tier
     * @return tickSpacing The tick spacing
     */
    function getTickSpacing(uint24 fee) internal pure returns (int24 tickSpacing) {
        if (fee == FEE_TIER_500) return TICK_SPACING_500;
        if (fee == FEE_TIER_3000) return TICK_SPACING_3000;
        if (fee == FEE_TIER_10000) return TICK_SPACING_10000;
        revert("Unsupported fee tier");
    }

    /**
     * @notice Get a valid tick within the tick spacing
     * @param tick The desired tick
     * @param fee The fee tier
     * @return validTick The nearest valid tick
     */
    function getValidTick(int24 tick, uint24 fee) internal pure returns (int24 validTick) {
        int24 spacing = getTickSpacing(fee);
        return (tick / spacing) * spacing;
    }

    /**
     * @notice Get pool information
     * @return fee The pool fee
     * @return tickSpacing The tick spacing
     * @return sqrtPriceX96 Current sqrt price
     * @return tick Current tick
     * @return liquidity Current liquidity
     */
    function getPoolInfo()
        internal
        view
        returns (uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, int24 tick, uint128 liquidity)
    {
        fee = pool.fee();
        tickSpacing = getTickSpacing(fee);
        (sqrtPriceX96, tick, , , , , ) = pool.slot0();
        liquidity = pool.liquidity();
    }

    /**
     * @notice Get token balances for an address
     * @param user The user address
     * @return balance0 Token0 balance
     * @return balance1 Token1 balance
     */
    function getTokenBalances(address user) internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = token0.balanceOf(user);
        balance1 = token1.balanceOf(user);
    }

    /**
     * @notice Get position information
     * @param tokenId The position NFT ID
     * @return info The position information
     */
    function getPositionInfo(uint256 tokenId) internal view returns (PositionInfo memory info) {
        return positions[tokenId];
    }
}
