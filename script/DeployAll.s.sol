// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Import all deployment contracts
import { DeployTokens } from "./DeployTokens.s.sol";
import { DeployDiamond } from "./DeployDiamond.s.sol";
import { DeployUniV3 } from "./DeployUniV3.s.sol";
import { DeployUniV3Decomposer } from "./DeployUniV3Decomposer.s.sol";
import { DeployNFTManager } from "./DeployNFTManager.s.sol";
import { DeploySimpleSwapRouter } from "./DeploySimpleSwapRouter.s.sol";
import { IAdmin } from "../src/interfaces/IAdmin.sol";
import { VaultType } from "../src/vaults/VaultPointer.sol";
import { BaseAdminFacet } from "Commons/Util/Admin.sol";

// Import contracts for address extraction
import { SimplexDiamond } from "../src/Diamond.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { MockERC4626 } from "../test/mocks/MockERC4626.sol";
import { UniswapV3Factory } from "v3-core/UniswapV3Factory.sol";
import { NonfungiblePositionManager } from "../test/mocks/nfpm/NonfungiblePositionManager.sol";
import { UniV3Decomposer } from "../src/integrations/UniV3Decomposer.sol";
import { NFTManager } from "../src/integrations/NFTManager.sol";

/**
 * @title DeployAll
 * @dev Master deployment script that deploys the complete Ammplify ecosystem
 *
 * This script orchestrates the deployment of all contracts in the correct order:
 * 1. MockERC20 tokens (USDC, WETH) and MockERC4626 vaults
 * 2. SimplexDiamond (core Ammplify contract with all facets)
 * 3. Uniswap V3 infrastructure (Factory, NFPM, Pool)
 * 4. UniV3Decomposer (converts UniV3 positions to Ammplify)
 * 5. NFTManager (ERC721 wrapper for Ammplify positions)
 */
contract DeployAll is Script {
    // Deployed contract addresses
    address public simplexDiamond;
    address public usdcToken;
    address public wethToken;
    address public usdcVault;
    address public wethVault;
    address public uniV3Factory;
    address public nfpm;
    address public usdcWethPool;
    address public decomposer;
    address public nftManager;
    address public swapRouter;

    function run() external {
        // Get the deployer's address and private key from environment
        address deployer = vm.envAddress("DEPLOYER_PUBLIC_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("============================================================");
        console.log("DEPLOYING COMPLETE AMMPLIFY ECOSYSTEM");
        console.log("============================================================");
        console.log("Deployer:", deployer);
        console.log("Deployer balance:", deployer.balance);
        console.log("");

        // Step 1: Deploy tokens and vaults
        console.log("Step 1/8: Deploying Tokens and Vaults...");
        _deployTokens();

        // Step 2: Deploy SimplexDiamond
        console.log("Step 2/8: Deploying SimplexDiamond...");
        _deployDiamond();

        // Step 3: Deploy Uniswap V3 infrastructure
        console.log("Step 3/8: Deploying Uniswap V3...");
        _deployUniV3();

        // Step 4: Deploy UniV3Decomposer
        console.log("Step 4/8: Deploying UniV3Decomposer...");
        _deployDecomposer();

        // Step 5: Deploy NFTManager
        console.log("Step 5/8: Deploying NFTManager...");
        _deployNFTManager();

        // Step 6: Deploy SwapRouter
        console.log("Step 6/8: Deploying SwapRouter...");
        _deploySwapRouter();

        // Step 7: Setup Vaults
        console.log("Step 7/8: Setting up Vaults...");
        _setupVaults(deployerPrivateKey);

        // Step 8: Setup Token Approvals
        console.log("Step 8/8: Setting up Token Approvals...");
        _setupApprovals(deployer, deployerPrivateKey);

        // Final summary
        _logFinalSummary();
    }

    /**
     * @notice Deploy tokens and vaults
     */
    function _deployTokens() internal {
        DeployTokens tokenDeployer = new DeployTokens();
        tokenDeployer.run();

        usdcToken = address(tokenDeployer.usdc());
        wethToken = address(tokenDeployer.weth());
        usdcVault = address(tokenDeployer.usdcVault());
        wethVault = address(tokenDeployer.wethVault());

        console.log(unicode"✅ Tokens deployed:");
        console.log("   USDC:", usdcToken);
        console.log("   WETH:", wethToken);
        console.log("   USDC Vault:", usdcVault);
        console.log("   WETH Vault:", wethVault);
        console.log("");

        // Update addresses JSON
        _updateDeployedAddressesJson();
    }

    /**
     * @notice Deploy SimplexDiamond
     */
    function _deployDiamond() internal {
        DeployDiamond diamondDeployer = new DeployDiamond();
        diamondDeployer.run();

        simplexDiamond = address(diamondDeployer.diamond());

        console.log(unicode"✅ SimplexDiamond deployed:");
        console.log("   Diamond:", simplexDiamond);
        console.log("");

        // Update addresses JSON
        _updateDeployedAddressesJson();
    }

    /**
     * @notice Deploy Uniswap V3 infrastructure
     */
    function _deployUniV3() internal {
        // Set environment variables for UniV3 deployment
        vm.setEnv("TOKEN_USDC", vm.toString(usdcToken));
        vm.setEnv("TOKEN_WETH", vm.toString(wethToken));

        DeployUniV3 uniV3Deployer = new DeployUniV3();
        uniV3Deployer.run();

        uniV3Factory = address(uniV3Deployer.factory());
        nfpm = address(uniV3Deployer.nfpm());
        usdcWethPool = address(uniV3Deployer.usdcWethPool());

        console.log(unicode"✅ Uniswap V3 deployed:");
        console.log("   Factory:", uniV3Factory);
        console.log("   NFPM:", nfpm);
        console.log("   USDC/WETH Pool:", usdcWethPool);
        console.log("");

        // Update addresses JSON
        _updateDeployedAddressesJson();
    }

    /**
     * @notice Deploy UniV3Decomposer
     */
    function _deployDecomposer() internal {
        // Set environment variables for Decomposer deployment
        vm.setEnv("MAKER_FACET", vm.toString(simplexDiamond));
        vm.setEnv("NFPM", vm.toString(nfpm));

        DeployUniV3Decomposer decomposerDeployer = new DeployUniV3Decomposer();
        decomposerDeployer.run();

        decomposer = address(decomposerDeployer.decomposer());

        console.log(unicode"✅ UniV3Decomposer deployed:");
        console.log("   Decomposer:", decomposer);
        console.log("");

        // Update addresses JSON
        _updateDeployedAddressesJson();
    }

    /**
     * @notice Deploy NFTManager
     */
    function _deployNFTManager() internal {
        // Set environment variables for NFTManager deployment
        vm.setEnv("MAKER_FACET", vm.toString(simplexDiamond));
        vm.setEnv("DECOMPOSER", vm.toString(decomposer));
        vm.setEnv("NFPM", vm.toString(nfpm));

        DeployNFTManager nftManagerDeployer = new DeployNFTManager();
        nftManagerDeployer.run();

        nftManager = address(nftManagerDeployer.nftManager());

        console.log(unicode"✅ NFTManager deployed:");
        console.log("   NFTManager:", nftManager);
        console.log("");

        // Update addresses JSON
        _updateDeployedAddressesJson();
    }

    /**
     * @notice Deploy SimpleSwapRouter
     */
    function _deploySwapRouter() internal {
        // Write necessary addresses to addresses JSON for DeploySimpleSwapRouter
        _updateDeployedAddressesJson();

        DeploySimpleSwapRouter swapRouterDeployer = new DeploySimpleSwapRouter();
        swapRouterDeployer.run();

        swapRouter = address(swapRouterDeployer.simpleSwapRouter());

        console.log(unicode"✅ SimpleSwapRouter deployed:");
        console.log("   SimpleSwapRouter:", swapRouter);
        console.log("");

        // Update addresses JSON
        _updateDeployedAddressesJson();
    }

    /**
     * @notice Update addresses JSON with current deployment addresses
     */
    function _updateDeployedAddressesJson() internal {
        string memory protocol = vm.envOr("AMMPLIFY_PROTOCOL", string("uniswapv3"));

        // Create JSON content with new flat schema
        string memory jsonContent = string(
            abi.encodePacked(
                "{\n",
                '  "network": "Monad Testnet",\n',
                '  "tokens": {\n',
                '    "USDC": { "address": "', vm.toString(usdcToken), '", "decimals": 6 },\n',
                '    "WETH": { "address": "', vm.toString(wethToken), '", "decimals": 18 }\n',
                "  },\n",
                '  "diamond": "', vm.toString(simplexDiamond), '",\n',
                '  "decomposer": "', vm.toString(decomposer), '",\n',
                '  "factory": "', vm.toString(uniV3Factory), '",\n',
                '  "nfpm": "', vm.toString(nfpm), '",\n',
                '  "router": "', vm.toString(swapRouter), '",\n',
                '  "pools": {\n',
                '    "USDC_WETH_3000": "', vm.toString(usdcWethPool), '"\n',
                "  }\n",
                "}"
            )
        );

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/addresses/", protocol, ".json");
        vm.writeFile(path, jsonContent);

        console.log(unicode"📝 Updated addresses JSON with current deployment addresses");
    }

    /**
     * @notice Setup vaults in the diamond
     */
    function _setupVaults(uint256 deployerPrivateKey) internal {
        console.log("Adding vaults to SimplexDiamond...");
        console.log("Using SimplexDiamond at:", simplexDiamond);

        vm.startBroadcast(deployerPrivateKey);

        IAdmin admin = IAdmin(simplexDiamond);
        BaseAdminFacet adminFacet = BaseAdminFacet(simplexDiamond);

        address owner = adminFacet.owner();
        console.log("Diamond owner:", owner);
        console.log("Current caller:", msg.sender);

        // Add USDC vault (index 0)
        console.log("Adding USDC Vault:", usdcVault);
        try admin.addVault(usdcToken, 0, usdcVault, VaultType.E4626) {
            console.log("USDC Vault added successfully at index 0");
        } catch Error(string memory reason) {
            console.log("Failed to add USDC Vault:", reason);
            revert(string.concat("USDC Vault setup failed: ", reason));
        } catch {
            console.log("Failed to add USDC Vault: Unknown error");
            revert("USDC Vault setup failed with unknown error");
        }
        // Add WETH vault (index 1)
        console.log("Adding WETH Vault:", wethVault);
        try admin.addVault(wethToken, 1, wethVault, VaultType.E4626) {
            console.log("WETH Vault added successfully at index 1");
        } catch Error(string memory reason) {
            console.log("Failed to add WETH Vault:", reason);
            revert(string.concat("WETH Vault setup failed: ", reason));
        } catch {
            console.log("Failed to add WETH Vault: Unknown error");
            revert("WETH Vault setup failed with unknown error");
        }
        // Verify vault setup
        console.log("=== Vault Verification ===");
        try admin.viewVaults(usdcToken, 0) returns (address vault, address backup) {
            console.log("USDC Vault (index 0):", vault);
            console.log("USDC Backup Vault:", backup);
        } catch {
            console.log("Warning: Could not verify USDC vault setup");
        }
        try admin.viewVaults(wethToken, 1) returns (address vault, address backup) {
            console.log("WETH Vault (index 1):", vault);
            console.log("WETH Backup Vault:", backup);
        } catch {
            console.log("Warning: Could not verify WETH vault setup");
        }
        console.log(unicode"✅ Vaults setup completed:");
        console.log("   USDC Vault (index 0):", usdcVault);
        console.log("   WETH Vault (index 1):", wethVault);
        console.log("");

        vm.stopBroadcast();
    }

    /**
     * @notice Setup token approvals for the deployer
     */
    function _setupApprovals(address deployer, uint256 deployerPrivateKey) internal {
        console.log("Setting up token approvals for deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Import the IERC20 interface
        IERC20 usdcContract = IERC20(usdcToken);
        IERC20 wethContract = IERC20(wethToken);

        // Approve diamond contract for unlimited spending
        console.log("Approving SimplexDiamond for token spending...");
        usdcContract.approve(simplexDiamond, type(uint256).max);
        wethContract.approve(simplexDiamond, type(uint256).max);

        // Approve NFT manager contract for unlimited spending
        console.log("Approving NFTManager for token spending...");
        usdcContract.approve(nftManager, type(uint256).max);
        wethContract.approve(nftManager, type(uint256).max);

        console.log(unicode"✅ Token approvals setup completed:");
        console.log("   USDC approved for SimplexDiamond and NFTManager");
        console.log("   WETH approved for SimplexDiamond and NFTManager");
        console.log("");

        vm.stopBroadcast();
    }

    /**
     * @notice Log final deployment summary
     */
    function _logFinalSummary() internal view {
        console.log("============================================================");
        console.log("DEPLOYMENT COMPLETE!");
        console.log("============================================================");

        console.log(unicode"🏗️  CORE CONTRACTS:");
        console.log("   SimplexDiamond (Ammplify Core):", simplexDiamond);
        console.log("   NFTManager (Position NFTs):", nftManager);
        console.log("");

        console.log(unicode"🪙  TOKENS & VAULTS:");
        console.log("   USDC Token:", usdcToken);
        console.log("   WETH Token:", wethToken);
        console.log("   USDC Vault:", usdcVault);
        console.log("   WETH Vault:", wethVault);
        console.log("");

        console.log(unicode"🦄  UNISWAP V3:");
        console.log("   Factory:", uniV3Factory);
        console.log("   NFPM:", nfpm);
        console.log("   SwapRouter:", swapRouter);
        console.log("   USDC/WETH Pool:", usdcWethPool);
        console.log("");

        console.log(unicode"🔄  INTEGRATIONS:");
        console.log("   UniV3Decomposer:", decomposer);
        console.log("");

        console.log(unicode"🚀  NEXT STEPS:");
        console.log("   1. Create maker positions (approvals already set up!):");
        console.log("      Direct: forge script script/actions/OpenMaker.s.sol --broadcast");
        console.log("      NFT:    forge script script/actions/OpenMakerNFT.s.sol --broadcast");
        console.log("");
        console.log("   2. Create a taker position (requires admin rights):");
        console.log("      forge script script/actions/OpenTaker.s.sol --broadcast");
        console.log("");
        console.log("   3. View your positions:");
        console.log("      forge script script/actions/ViewPositions.s.sol");
        console.log("");

        console.log("============================================================");
        console.log(unicode"All contracts deployed successfully! 🎉");
        console.log("============================================================");
    }

    /**
     * @notice Helper function to get all deployed addresses as a JSON-like string
     * @dev Useful for frontend integration or other scripts
     */
    function getDeploymentAddresses() external view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "{\n",
                    '  "simplexDiamond": "',
                    vm.toString(simplexDiamond),
                    '",\n',
                    '  "nftManager": "',
                    vm.toString(nftManager),
                    '",\n',
                    '  "decomposer": "',
                    vm.toString(decomposer),
                    '",\n',
                    '  "usdcToken": "',
                    vm.toString(usdcToken),
                    '",\n',
                    '  "wethToken": "',
                    vm.toString(wethToken),
                    '",\n',
                    '  "usdcVault": "',
                    vm.toString(usdcVault),
                    '",\n',
                    '  "wethVault": "',
                    vm.toString(wethVault),
                    '",\n',
                    '  "uniV3Factory": "',
                    vm.toString(uniV3Factory),
                    '",\n',
                    '  "nfpm": "',
                    vm.toString(nfpm),
                    '",\n',
                    '  "swapRouter": "',
                    vm.toString(swapRouter),
                    '",\n',
                    '  "usdcWethPool": "',
                    vm.toString(usdcWethPool),
                    '"\n',
                    "}"
                )
            );
    }
}
