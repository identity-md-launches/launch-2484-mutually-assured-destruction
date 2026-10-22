// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Local or test-network deployment helper. The IdentityMD launch does not use this script:
///         the factory deploys the token from its creation code and the whole supply lands with the
///         factory. This exists so the requester can deploy the same bytecode on a fork or testnet.
/// @dev    The token takes no constructor arguments, so there is nothing to configure. `deploy()` is
///         the unit the tests call; `run()` only wraps it in a broadcast.
contract DeployMADToken is Script {
    function deploy() public returns (MADToken token) {
        token = new MADToken();
    }

    function run() external returns (MADToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
