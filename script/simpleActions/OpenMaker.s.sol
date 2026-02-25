// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "forge-std/console2.sol";
import { IMaker } from "../../src/interfaces/IMaker.sol";
import { Script } from "forge-std/Script.sol";
import { TickMath } from "v4-core/libraries/TickMath.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

// Used for fork testing opening positions.
contract OpenMakerScript is Script {
    address public ammplify = 0x5B5e9d616fAFCCC4865a6C29b6F89Ff3aAE7c892;
    address public pool = 0x659bD0BC4167BA25c62E05656F78043E7eD4a9da;
    address public user = 0xd5B79A8b472b941b131a3Eb2f9C4c9E4b0C6DcE9;
    address public usdc = 0x754704Bc059F8C67012fEd69BC8A327a5aafb603;
    address public wmon = 0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A;

    function run() public {
        vm.startPrank(user);
        IMaker maker = IMaker(ammplify);
        IERC20(wmon).approve(ammplify, type(uint256).max);
        maker.newMaker(
            user,
            pool,
            (int24(-307336) / 60) * 60,
            (int24(-305282) / 60) * 60,
            100_000_000_000,
            TickMath.MIN_SQRT_PRICE,
            TickMath.MAX_SQRT_PRICE,
            ""
        );
        vm.stopPrank();
    }
}
