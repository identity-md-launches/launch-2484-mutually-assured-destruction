// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeployMADToken} from "../script/Deploy.s.sol";
import {MADToken} from "../src/MADToken.sol";

contract DeployTest is Test {
    function test_deployMintsSupplyToTheScriptCaller() public {
        DeployMADToken deployer = new DeployMADToken();
        MADToken token = deployer.deploy();
        // `new` inside the script makes the script contract the deployer, so it holds the supply.
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        assertEq(token.balanceOf(address(deployer)), 1_000_000_000 ether);
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
    }
}
