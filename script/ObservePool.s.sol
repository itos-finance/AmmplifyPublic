// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "forge-std/StdJson.sol";

import { IUniswapV3Pool } from "v3-core/interfaces/IUniswapV3Pool.sol";

/**
 * @title ObservePool
 * @notice Script to call the observe function on a UniswapV3Pool
 * @dev The observe function returns cumulative tick and liquidity values for specified time periods
 */
contract ObservePool is Script {
    using stdJson for string;

    function run() public {
        // Get pool address from environment or deployed-uniswap.json
        address poolAddress = getPoolAddress();

        console2.log("=== Observe Pool ===");
        console2.log("Pool Address:", poolAddress);

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        // Get pool info
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();
        (uint160 sqrtPriceX96, int24 tick, , , , , ) = pool.slot0();

        console2.log("\n--- Pool Info ---");
        console2.log("Token0:", token0);
        console2.log("Token1:", token1);
        console2.log("Pool Fee:", fee);
        console2.log("Current Tick:", tick);
        console2.log("Current sqrtPriceX96:", sqrtPriceX96);

        // Get secondsAgos from environment or use defaults
        // Default: observe current state [0] and 1 hour ago [3600]
        uint32[] memory secondsAgos = getSecondsAgos();

        console2.log("\n--- Observation Parameters ---");
        console2.log("Number of observations:", secondsAgos.length);
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            console2.log("  secondsAgos[", i, "]:", secondsAgos[i]);
        }

        vm.warp(37_749_288);

        // Call observe function
        console2.log("\n--- Calling observe() ---");
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = pool.observe(
            secondsAgos
        );

        // Display results
        console2.log("\n=== Observation Results ===");
        console2.log("Number of results:", tickCumulatives.length);

        for (uint256 i = 0; i < tickCumulatives.length; i++) {
            console2.log("\n--- Observation", i);
            console2.log("Seconds ago:", secondsAgos[i]);
            console2.log("Tick Cumulative:", uint256(int256(tickCumulatives[i])));
            console2.log("Seconds Per Liquidity Cumulative X128:", secondsPerLiquidityCumulativeX128s[i]);
        }

        // If we have 2 observations, calculate time-weighted average tick
        if (tickCumulatives.length == 2 && secondsAgos[0] > secondsAgos[1]) {
            uint32 timeDelta = secondsAgos[0] - secondsAgos[1];
            int56 tickDelta = tickCumulatives[0] - tickCumulatives[1];
            int56 avgTick = tickDelta / int56(uint56(timeDelta));

            console2.log("\n--- Time-Weighted Average ---");
            console2.log("Time period:", timeDelta, "seconds");
            console2.log("Average Tick:", uint256(int256(avgTick)));
        }
    }

    /**
     * @notice Get pool address from environment or deployed-uniswap.json
     */
    function getPoolAddress() internal view returns (address poolAddress) {
        return address(0x659bD0BC4167BA25c62E05656F78043E7eD4a9da);
    }

    /**
     * @notice Get pool address from pool key in deployed-uniswap.json
     */
    function getPoolAddressFromKey(string memory poolKey) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployed-uniswap.json");
        string memory json = vm.readFile(path);
        string memory key = string.concat(".uniswap.pools.", poolKey);
        return json.readAddress(key);
    }

    /**
     * @notice Get secondsAgos array from environment or use defaults
     * @dev Environment variable should be comma-separated values like "3600,0"
     */
    function getSecondsAgos() internal view returns (uint32[] memory) {
        // Try to get from environment variable
        try vm.envString("SECONDS_AGOS") returns (string memory secondsAgosStr) {
            return parseSecondsAgos(secondsAgosStr);
        } catch {}
        // Default: observe current state [0] and 1 hour ago [3600]
        uint32[] memory defaultAgos = new uint32[](2);
        defaultAgos[0] = 0; // 1 hour ago
        defaultAgos[1] = 120; // current
        return defaultAgos;
    }

    /**
     * @notice Parse comma-separated string of seconds into uint32 array
     */
    function parseSecondsAgos(string memory secondsAgosStr) internal pure returns (uint32[] memory) {
        // Simple parsing: split by comma and convert to uint32
        // This is a basic implementation - for production, consider using a more robust parser
        bytes memory strBytes = bytes(secondsAgosStr);
        uint256 count = 1;

        // Count commas to determine array size
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == bytes1(",")) {
                count++;
            }
        }

        uint32[] memory result = new uint32[](count);
        uint256 currentIndex = 0;
        uint256 startIndex = 0;

        for (uint256 i = 0; i <= strBytes.length; i++) {
            if (i == strBytes.length || strBytes[i] == bytes1(",")) {
                bytes memory numBytes = new bytes(i - startIndex);
                for (uint256 j = 0; j < numBytes.length; j++) {
                    numBytes[j] = strBytes[startIndex + j];
                }
                result[currentIndex] = uint32(stringToUint(string(numBytes)));
                currentIndex++;
                startIndex = i + 1;
            }
        }

        return result;
    }

    /**
     * @notice Convert string to uint256 (simple implementation)
     */
    function stringToUint(string memory s) internal pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            if (uint8(b[i]) >= 48 && uint8(b[i]) <= 57) {
                result = result * 10 + (uint8(b[i]) - 48);
            }
        }
        return result;
    }
}
