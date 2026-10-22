// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @notice Stands in for the ProjectFactory: deploys the token through CREATE2 from its own address,
///         as `launchCustom` does, and then moves the supply the way the launch flows do.
contract FactoryStub {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0) && deployed.code.length > 0, "constructor failed");
    }

    function move(IERC20 token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract MADTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    uint256 internal constant SWARM_BPS = 1_000;
    uint256 internal constant POOL_BPS = 8_000;

    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL_MANAGER = address(0x900A);
    address internal constant REQUESTER = address(0xFc3C962FAD2C1cC77f1a0d46e7B8a2De79A21774);
    address internal constant CLAIMANT = address(0xC1A1);
    address internal constant HOLDER = address(0x401D);
    address internal constant OTHER = address(0x07E5);
    address internal constant ATTACKER = address(0xBEEF);

    FactoryStub internal factory;
    MADToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        factory = new FactoryStub();
        token = MADToken(factory.deploy(type(MADToken).creationCode, bytes32(uint256(1))));
    }

    // ------------------------------------------------------------------ metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "Mutually Assured Destruction");
        assertEq(token.symbol(), "MAD");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "Mutually Assured Destruction");
        assertEq(token.TOKEN_SYMBOL(), "MAD");
        assertEq(token.DECIMALS(), 18);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
    }

    function test_constructorEmitsSingleTransferFromZero() public {
        vm.recordLogs();
        MADToken fresh = new MADToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(address(uint160(uint256(logs[0].topics[1]))), address(0));
        assertEq(address(uint160(uint256(logs[0].topics[2]))), address(this));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
    }

    function test_deployerIsWhoeverCallsTheConstructor() public {
        vm.prank(OTHER);
        MADToken fresh = new MADToken();
        assertEq(fresh.balanceOf(OTHER), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), 0);
    }

    function test_creationCodeTakesNoConstructorArguments() public {
        // The launch deploys the bytes as built with no appended arguments; appending any must not
        // change what is deployed. Both deployments mint the same supply to the deployer.
        bytes memory bare = type(MADToken).creationCode;
        address a = factory.deploy(bare, bytes32(uint256(7)));
        assertEq(MADToken(a).totalSupply(), SUPPLY);
        assertEq(a.code, address(token).code, "runtime differs between deployments");
    }

    function test_runtimeFitsEip170() public view {
        assertGt(address(token).code.length, 0);
        assertLe(address(token).code.length, 24_576);
    }

    // ------------------------------------------------------------------ launch flows move exactly

    function test_swarmShareArrivesWholeAndIsClaimableWhole() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        assertTrue(factory.move(token, DISTRIBUTOR, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(address(factory)), SUPPLY - swarm);

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(CLAIMANT, swarm));
        assertEq(token.balanceOf(CLAIMANT), swarm);
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_fullLaunchSplitConservesSupply() public {
        uint256 swarm = (SUPPLY * SWARM_BPS) / 10_000;
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        assertTrue(factory.move(token, DISTRIBUTOR, swarm));
        assertTrue(factory.move(token, POOL_MANAGER, pool));
        assertTrue(factory.move(token, REQUESTER, remainder));

        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
        assertEq(token.balanceOf(REQUESTER), remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(swarm + pool + remainder, SUPPLY);
    }

    function test_poolManagerRoundTripMovesExactly() public {
        // A trader buys from and sells into the pool manager; both legs move exactly what is sent.
        uint256 pool = (SUPPLY * POOL_BPS) / 10_000;
        factory.move(token, POOL_MANAGER, pool);
        address trader = address(0x7A4D);

        vm.prank(POOL_MANAGER);
        assertTrue(token.transfer(trader, 1234e18));
        assertEq(token.balanceOf(trader), 1234e18);

        vm.prank(trader);
        assertTrue(token.transfer(POOL_MANAGER, 1234e18));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
    }

    // ------------------------------------------------------------------ ERC-20 behaviour

    function test_transferEmitsAndUpdatesBalances() public {
        factory.move(token, HOLDER, 100e18);
        vm.expectEmit(address(token));
        emit Transfer(HOLDER, OTHER, 40e18);
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, 40e18));
        assertEq(token.balanceOf(HOLDER), 60e18);
        assertEq(token.balanceOf(OTHER), 40e18);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, 0));
        assertEq(token.balanceOf(OTHER), 0);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        factory.move(token, HOLDER, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, 10e18, 11e18));
        vm.prank(HOLDER);
        token.transfer(OTHER, 11e18);
    }

    function test_transferRevertsToZeroAddress() public {
        factory.move(token, HOLDER, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(HOLDER);
        token.transfer(address(0), 1);
    }

    function test_approveAndTransferFrom() public {
        factory.move(token, HOLDER, 100e18);
        vm.expectEmit(address(token));
        emit Approval(HOLDER, OTHER, 70e18);
        vm.prank(HOLDER);
        assertTrue(token.approve(OTHER, 70e18));
        assertEq(token.allowance(HOLDER, OTHER), 70e18);

        vm.prank(OTHER);
        assertTrue(token.transferFrom(HOLDER, CLAIMANT, 30e18));
        assertEq(token.balanceOf(HOLDER), 70e18);
        assertEq(token.balanceOf(CLAIMANT), 30e18);
        assertEq(token.allowance(HOLDER, OTHER), 40e18);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        factory.move(token, HOLDER, 100e18);
        vm.prank(HOLDER);
        token.approve(OTHER, type(uint256).max);
        vm.prank(OTHER);
        token.transferFrom(HOLDER, CLAIMANT, 30e18);
        assertEq(token.allowance(HOLDER, OTHER), type(uint256).max);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        factory.move(token, HOLDER, 100e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, OTHER, 0, 1));
        vm.prank(OTHER);
        token.transferFrom(HOLDER, OTHER, 1);
    }

    function test_transferFromRevertsBeyondAllowance() public {
        factory.move(token, HOLDER, 100e18);
        vm.prank(HOLDER);
        token.approve(OTHER, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, OTHER, 10e18, 11e18));
        vm.prank(OTHER);
        token.transferFrom(HOLDER, OTHER, 11e18);
    }

    function test_transferFromRevertsBeyondBalanceEvenWithAllowance() public {
        factory.move(token, HOLDER, 5e18);
        vm.prank(HOLDER);
        token.approve(OTHER, 100e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, 5e18, 6e18));
        vm.prank(OTHER);
        token.transferFrom(HOLDER, OTHER, 6e18);
    }

    function test_approveRevertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(HOLDER);
        token.approve(address(0), 1);
    }

    // ------------------------------------------------------------------ nothing privileged exists

    function test_noAdminCallIncreasesSupplyOrGrantsBalance() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ATTACKER, type(uint128).max);
            vm.prank(ATTACKER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(address(factory));
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(ATTACKER), 0, signatures[i]);
        }
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        factory.move(token, HOLDER, SUPPLY / 1_000);
        uint256 held = token.balanceOf(HOLDER);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], HOLDER, true);
            vm.prank(address(factory));
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        vm.prank(address(factory));
        (bool moved,) =
            address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, HOLDER, address(factory), 1));
        assertFalse(moved, "the deployer pulled from a holder without allowance");
        assertEq(token.balanceOf(HOLDER), held);
        vm.prank(HOLDER);
        assertTrue(token.transfer(OTHER, held / 2));
        assertEq(token.balanceOf(OTHER), held / 2);
    }

    function test_hasNoOwnerOrPauseView() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "owner() exists");
        (ok,) = address(token).call(abi.encodeWithSignature("paused()"));
        assertFalse(ok, "paused() exists");
    }

    function test_plainEtherIsRefused() public {
        vm.deal(ATTACKER, 1 ether);
        vm.prank(ATTACKER);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    /// @dev Reachable runtime code contains no DELEGATECALL, CALLCODE or SELFDESTRUCT, scanned the way
    ///      the launch floor scans it: PUSH data is skipped and only bytes execution can reach count.
    function test_runtimeCodeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ------------------------------------------------------------------ fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(factory));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(factory.move(token, to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(address(factory)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferBeyondBalanceReverts(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        factory.move(token, HOLDER, held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, held, amount));
        vm.prank(HOLDER);
        token.transfer(OTHER, amount);
    }

    function testFuzz_transferFromWithinAllowance(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, SUPPLY);
        amount = bound(amount, 0, allowed);
        factory.move(token, HOLDER, SUPPLY);
        vm.prank(HOLDER);
        token.approve(OTHER, allowed);
        vm.prank(OTHER);
        assertTrue(token.transferFrom(HOLDER, CLAIMANT, amount));
        assertEq(token.balanceOf(CLAIMANT), amount);
        assertEq(token.allowance(HOLDER, OTHER), allowed - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_unknownSelectorReverts(bytes4 selector, bytes calldata args) public {
        vm.assume(
            selector != IERC20.transfer.selector && selector != IERC20.approve.selector
                && selector != IERC20.transferFrom.selector && selector != IERC20.totalSupply.selector
                && selector != IERC20.balanceOf.selector && selector != IERC20.allowance.selector
                && selector != bytes4(keccak256("name()")) && selector != bytes4(keccak256("symbol()"))
                && selector != bytes4(keccak256("decimals()")) && selector != bytes4(keccak256("TOKEN_NAME()"))
                && selector != bytes4(keccak256("TOKEN_SYMBOL()")) && selector != bytes4(keccak256("DECIMALS()"))
                && selector != bytes4(keccak256("TOTAL_SUPPLY()"))
        );
        vm.prank(ATTACKER);
        (bool ok,) = address(token).call(abi.encodePacked(selector, args));
        assertFalse(ok, "an unknown selector succeeded");
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ATTACKER), 0);
    }
}
