// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "forge-std/StdCheats.sol";
import "forge-std/console2.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IMaker } from "../src/interfaces/IMaker.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { Test } from "forge-std/Test.sol";

contract NewMaker is Script, Test {
    address public constant CAPRICORN_MAKER_ADDRESS = 0xEca6d8973238B71180327C0376c6495A2a29fDE9;
    address public constant UNISWAP_MAKER_ADDRESS = 0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892;
    address public constant TOKEN1 = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;
    address public constant TOKEN2 = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // vm.startBroadcast(deployerPrivateKey);

        // Deal tokens
        deal(TOKEN1, deployer, 1000000e18);
        deal(TOKEN2, deployer, 1000000e18);

        // Query allowances before newMaker call
        address owner = 0xc137942872586E5847d66025c9aE04b89053Cb58;
        address spender = UNISWAP_MAKER_ADDRESS;

        IERC20 token1 = IERC20(TOKEN1);
        IERC20 token2 = IERC20(TOKEN2);

        uint256 token1Allowance = token1.allowance(owner, spender);
        uint256 token2Allowance = token2.allowance(owner, spender);

        console2.log("Token1 allowance:", token1Allowance);
        console2.log("Token2 allowance:", token2Allowance);

        // approve amounts
        token1.approve(spender, 1e18);
        token2.approve(spender, 1e18);

        // Call newMaker
        IMaker maker = IMaker(UNISWAP_MAKER_ADDRESS);
        vm.prank(0xc137942872586E5847d66025c9aE04b89053Cb58);
        maker.newMaker(
            0xc137942872586E5847d66025c9aE04b89053Cb58,
            0x659bD0BC4167BA25c62E05656F78043E7eD4a9da,
            -313200,
            -311520,
            721224196866580,
            true,
            4295128739,
            158456325028528675187087900672,
            ""
        );

        // vm.stopBroadcast();
    }
}
