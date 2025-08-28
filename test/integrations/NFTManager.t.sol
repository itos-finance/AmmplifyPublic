// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { IERC721 } from "a@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC20 } from "a@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { MultiSetupTest } from "../MultiSetup.u.sol";
import { NFTManager } from "../../src/integrations/NFTManager.sol";
import { UniV3Decomposer } from "../../src/integrations/UniV3Decomposer.sol";
import { LiqType } from "../../src/walkers/Liq.sol";
import { MockNFPM } from "../mocks/MockNFPM.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import {
    INonfungiblePositionManager
} from "../../src/integrations/univ3-periphery/interfaces/INonfungiblePositionManager.sol";

contract NFTManagerTest is MultiSetupTest {
    NFTManager public nftManager;
    UniV3Decomposer public decomposer;

    // Test parameters
    uint24 public constant POOL_FEE = 3000;
    int24 public constant LOW_TICK = -600;
    int24 public constant HIGH_TICK = 600;
    uint128 public constant LIQUIDITY = 1000e18;
    uint128 public constant MIN_SQRT_PRICE_X96 = 0;
    uint128 public constant MAX_SQRT_PRICE_X96 = type(uint128).max;

    // Constants for price bounds (from v3-core)
    uint160 public constant MIN_SQRT_RATIO = 4295128739;
    uint160 public constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    function setUp() public {
        // Setup the diamond and facets
        _newDiamond();

        // Setup a pool
        (uint256 poolIdx, address poolAddr, address token0Addr, address token1Addr) = setUpPool(POOL_FEE);

        token0 = MockERC20(token0Addr);
        token1 = MockERC20(token1Addr);

        // Deploy NFPM
        _deployNFPM();

        // Setup decomposer
        decomposer = new UniV3Decomposer(address(nfpm), address(makerFacet));

        // Setup NFT manager
        nftManager = new NFTManager(address(makerFacet), address(decomposer), address(nfpm));

        // Create vaults for token0 and token1 from the pool
        _createPoolVaults(poolAddr);
    }

    // Helper function to create a position using the mint function
    function createPosition(
        address owner,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256) {
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: uint256(liquidity),
            amount1Desired: uint256(liquidity),
            amount0Min: 0,
            amount1Min: 0,
            recipient: owner,
            deadline: block.timestamp + 3600,
            data: ""
        });

        (uint256 tokenId, , , ) = nfpm.mint(params);
        return tokenId;
    }

    function test_BasicNFTFunctionality() public {
        // Test basic NFT functionality without complex operations
        assertEq(nftManager.totalSupply(), 0);

        // Test that the NFT manager has the correct contracts
        assertTrue(address(nftManager.MAKER_FACET()) == address(makerFacet));
        assertTrue(address(nftManager.DECOMPOSER()) == address(decomposer));
        assertTrue(address(nftManager.NFPM()) == address(nfpm));
    }

    function test_PoolVaultsCreated() public {
        // Test that vaults were created for token0 and token1
        (address vault0, address backup0) = adminFacet.viewVaults(address(token0), 0);
        (address vault1, address backup1) = adminFacet.viewVaults(address(token1), 0);

        // Verify vaults exist and are not zero addresses
        assertTrue(vault0 != address(0), "Vault0 should exist");
        assertTrue(vault1 != address(0), "Vault1 should exist");

        // Verify no backup vaults initially
        assertEq(backup0, address(0), "Backup0 should not exist initially");
        assertEq(backup1, address(0), "Backup1 should not exist initially");

        // Verify vaults are in the vaults array
        assertEq(vaults.length, 2, "Should have 2 vaults");
        assertTrue(address(vaults[0]) == vault0 || address(vaults[0]) == vault1, "Vault0 should be in vaults array");
        assertTrue(address(vaults[1]) == vault0 || address(vaults[1]) == vault1, "Vault1 should be in vaults array");
    }

    // ============ mintNewMaker Tests ============
    function test_mintNewMaker() public {
        // Fund the test account for RFT operations
        _fundAccount(address(this));

        bytes memory rftData = "";

        // Mint a new maker position via NFT manager
        (uint256 tokenId, uint256 assetId) = nftManager.mintNewMaker(
            address(this), // recipient
            address(pools[0]), // poolAddr
            LOW_TICK, // lowTick
            HIGH_TICK, // highTick
            LIQUIDITY, // liq
            false, // isCompounding
            uint128(MIN_SQRT_RATIO), // minSqrtPriceX96
            uint128(MAX_SQRT_RATIO), // maxSqrtPriceX96
            rftData // rftData
        );

        // Verify the NFT was minted
        assertEq(nftManager.totalSupply(), 1);
        assertEq(nftManager.ownerOf(tokenId), address(this));

        // Verify the asset was created and linked
        assertEq(nftManager.tokenToAsset(tokenId), assetId);
        assertEq(nftManager.assetToToken(assetId), tokenId);

        // Verify the asset exists in the maker facet
        (address owner, address poolAddr, int24 lowTick, int24 highTick, , uint128 liq) = viewFacet.getAssetInfo(
            assetId
        );
        assertEq(owner, address(nftManager)); // NFT manager owns the asset
        assertEq(poolAddr, address(pools[0]));
        assertEq(lowTick, LOW_TICK);
        assertEq(highTick, HIGH_TICK);
        assertEq(liq, LIQUIDITY);
    }

    // ============ decomposeAndMint Tests ============

    function test_decomposeAndMint() public {
        // Fund the test account for RFT operations
        _fundAccount(address(this));

        // First, mint a Uniswap V3 position using the NFPM
        uint256 positionId = createPosition(
            address(this), // owner
            POOL_FEE, // fee
            LOW_TICK, // tickL
            HIGH_TICK, // tickU
            LIQUIDITY // liq
        );

        // Verify the position was minted
        assertEq(nfpm.ownerOf(positionId), address(this));

        bytes memory rftData = "";

        // Now decompose and mint the position
        (uint256 tokenId, uint256 assetId) = nftManager.decomposeAndMint(
            positionId, // positionId
            true, // isCompounding
            uint128(MIN_SQRT_RATIO), // minSqrtPriceX96
            uint128(MAX_SQRT_RATIO), // maxSqrtPriceX96
            rftData // rftData
        );

        // Verify the NFT was minted
        assertEq(nftManager.totalSupply(), 1);
        assertEq(nftManager.ownerOf(tokenId), address(this));

        // Verify the asset was created and linked
        assertEq(nftManager.tokenToAsset(tokenId), assetId);
        assertEq(nftManager.assetToToken(assetId), tokenId);

        // Verify the asset exists in the maker facet
        (address owner, address poolAddr, int24 lowTick, int24 highTick, , uint128 liq) = viewFacet.getAssetInfo(
            assetId
        );
        assertEq(owner, address(nftManager)); // NFT manager owns the asset
        assertEq(poolAddr, address(pools[0]));
        assertEq(lowTick, LOW_TICK);
        assertEq(highTick, HIGH_TICK);
        assertEq(liq, LIQUIDITY);

        // Verify the position was transferred to the NFT manager
        assertEq(nfpm.ownerOf(positionId), address(nftManager));

        // Verify the position was approved to the decomposer
        // Note: We can't directly check approval in the mock, but the transfer should succeed
    }

    // ============ burnAsset Tests ============
    function test_burnAsset() public {
        // Fund the test account for RFT operations
        _fundAccount(address(this));

        bytes memory rftData = "";

        // First mint a new maker position via NFT manager
        (uint256 tokenId, uint256 assetId) = nftManager.mintNewMaker(
            address(this), // recipient
            address(pools[0]), // poolAddr
            LOW_TICK, // lowTick
            HIGH_TICK, // highTick
            LIQUIDITY, // liq
            false, // isCompounding
            uint128(MIN_SQRT_RATIO), // minSqrtPriceX96
            uint128(MAX_SQRT_RATIO), // maxSqrtPriceX96
            rftData // rftData
        );

        // Verify the NFT was minted
        assertEq(nftManager.totalSupply(), 1);
        assertEq(nftManager.ownerOf(tokenId), address(this));

        // Now burn the asset
        (address token0, address token1, uint256 removedX, uint256 removedY, uint256 fees0, uint256 fees1) = nftManager
            .burnAsset(
                tokenId,
                uint128(MIN_SQRT_RATIO), // minSqrtPriceX96
                uint128(MAX_SQRT_RATIO), // maxSqrtPriceX96
                rftData // rftData
            );

        // Verify the NFT was burned
        assertEq(nftManager.totalSupply(), 0);

        // Verify the asset mappings were cleared
        assertEq(nftManager.tokenToAsset(tokenId), 0);
        assertEq(nftManager.assetToToken(assetId), 0);

        // Verify the returned values are valid addresses
        assertTrue(token0 != address(0));
        assertTrue(token1 != address(0));
    }

    // ============ collectFees Tests ============
    function test_collectFees() public {
        // Fund the test account for RFT operations
        _fundAccount(address(this));

        bytes memory rftData = "";

        // First mint a new maker position via NFT manager
        (uint256 tokenId, uint256 assetId) = nftManager.mintNewMaker(
            address(this), // recipient
            address(pools[0]), // poolAddr
            LOW_TICK, // lowTick
            HIGH_TICK, // highTick
            LIQUIDITY, // liq
            false, // isCompounding
            uint128(MIN_SQRT_RATIO), // minSqrtPriceX96
            uint128(MAX_SQRT_RATIO), // maxSqrtPriceX96
            rftData // rftData
        );

        // Verify the NFT was minted
        assertEq(nftManager.totalSupply(), 1);
        assertEq(nftManager.ownerOf(tokenId), address(this));

        // Collect fees from the position
        (uint256 fees0, uint256 fees1) = nftManager.collectFees(
            tokenId,
            uint128(MIN_SQRT_RATIO), // minSqrtPriceX96
            uint128(MAX_SQRT_RATIO), // maxSqrtPriceX96
            rftData // rftData
        );

        // Verify fees were collected (in mock, this returns 1e18 for each token)
        assertEq(fees0, 1e18);
        assertEq(fees1, 1e18);

        // Verify the NFT still exists and wasn't burned
        assertEq(nftManager.totalSupply(), 1);
        assertEq(nftManager.ownerOf(tokenId), address(this));
    }

    // ============ positions Tests ============
    function test_positions() public {
        // Fund the test account for RFT operations
        _fundAccount(address(this));

        bytes memory rftData = "";

        // First mint a new maker position via NFT manager
        (uint256 tokenId, uint256 assetId) = nftManager.mintNewMaker(
            address(this), // recipient
            address(pools[0]), // poolAddr
            LOW_TICK, // lowTick
            HIGH_TICK, // highTick
            LIQUIDITY, // liq
            false, // isCompounding
            uint128(MIN_SQRT_RATIO), // minSqrtPriceX96
            uint128(MAX_SQRT_RATIO), // maxSqrtPriceX96
            rftData // rftData
        );

        // Verify the NFT was minted
        assertEq(nftManager.totalSupply(), 1);
        assertEq(nftManager.ownerOf(tokenId), address(this));

        // Get position information
        (
            uint256 returnedAssetId,
            address owner,
            address poolAddr,
            address token0,
            address token1,
            int24 lowTick,
            int24 highTick,
            LiqType liqType,
            uint128 liquidity,
            uint128 timestamp
        ) = nftManager.positions(tokenId);

        // Verify all position data matches what we created
        assertEq(returnedAssetId, assetId);
        assertEq(owner, address(nftManager)); // NFT manager owns the asset
        assertEq(poolAddr, address(pools[0]));
        assertEq(token0, address(this.token0()));
        assertEq(token1, address(this.token1()));
        assertEq(lowTick, LOW_TICK);
        assertEq(highTick, HIGH_TICK);
        assertEq(uint8(liqType), uint8(LiqType.MAKER_NC)); // Non-compounding maker
        assertEq(liquidity, LIQUIDITY);
        assertTrue(timestamp > 0); // Should have a timestamp
    }
}
