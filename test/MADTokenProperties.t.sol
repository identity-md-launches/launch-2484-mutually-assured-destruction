// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "src/MADToken.sol";

/// @notice Boundary and sequence properties supplementing the existing launch tests.
/// forge-config: default.fuzz.runs = 1000
contract MADTokenPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    MADToken internal token;
    address internal alice;
    address internal bob;
    address internal carol;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new MADToken();
        alice = makeAddr("MAD properties: Alice");
        bob = makeAddr("MAD properties: Bob");
        carol = makeAddr("MAD properties: Carol");
    }

    function test_oneWeiMovesExactly() public {
        vm.expectEmit(address(token));
        emit Transfer(address(this), alice, 1);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanLeaveAndReturnToDeployer() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        token.transfer(bob, 1);

        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsAndPreservesState() public {
        vm.prank(alice);
        token.approve(bob, 17);
        bytes32 beforeState = _state();

        vm.expectEmit(address(token));
        emit Transfer(alice, carol, 0);
        vm.prank(alice);
        assertTrue(token.transfer(carol, 0));
        assertEq(_state(), beforeState);
    }

    function test_selfTransferOfWholeSupplyEmitsAndPreservesState() public {
        token.approve(bob, 17);
        bytes32 beforeState = _state();

        vm.expectEmit(address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(_state(), beforeState);
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        bytes32 beforeState = _state();
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(_state(), beforeState);
    }

    function test_maximumTransferRevertsWithoutChangingState() public {
        bytes32 beforeState = _state();
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(_state(), beforeState);
    }

    function test_zeroTransferToZeroAddressIsRejected() public {
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(_state(), beforeState);
    }

    function test_zeroApprovalToZeroSpenderIsRejected() public {
        token.approve(bob, 17);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(_state(), beforeState);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_repeatedApprovalIsIdempotentAndEmits() public {
        token.approve(bob, 17);
        bytes32 beforeState = _state();
        vm.expectEmit(address(token));
        emit Approval(address(this), bob, 17);
        assertTrue(token.approve(bob, 17));
        assertEq(_state(), beforeState);
    }

    function test_approvalReplacementAndRevocationTakeEffectImmediately() public {
        token.approve(bob, 17);
        token.approve(carol, 23);
        vm.expectEmit(address(token));
        emit Approval(address(this), bob, 3);
        assertTrue(token.approve(bob, 3));
        assertEq(token.allowance(address(this), bob), 3);
        assertEq(token.allowance(address(this), carol), 23);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 3, 4));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 4);
        assertEq(_state(), beforeState);

        vm.expectEmit(address(token));
        emit Approval(address(this), bob, 0);
        assertTrue(token.approve(bob, 0));
        beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(_state(), beforeState);
        assertEq(token.allowance(address(this), carol), 23);
    }

    function test_exactAllowanceCanOnlyBeSpentOnce() public {
        token.approve(bob, 17);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, 17));
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(alice), 17);
        assertEq(token.balanceOf(address(this)), SUPPLY - 17);

        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 17));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 17);
        assertEq(_state(), beforeState);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        token.approve(bob, type(uint256).max - 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), bob), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_infiniteApprovalSurvivesRepeatedSpendingButCanBeRevoked() public {
        token.approve(bob, type(uint256).max);
        vm.startPrank(bob);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.transferFrom(address(this), carol, 2));
        vm.stopPrank();
        assertEq(token.allowance(address(this), bob), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(carol), 2);

        token.approve(bob, 0);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(_state(), beforeState);

        token.approve(bob, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(alice), 2);
    }

    function test_transferFromToSelfConsumesAllowanceWithoutMovingBalances() public {
        token.approve(bob, SUPPLY);
        vm.expectEmit(address(token));
        emit Transfer(address(this), address(this), SUPPLY);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromByHolderStillRequiresSelfApproval() public {
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(_state(), beforeState);

        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_zeroTransferFromNeedsNeitherBalanceNorAllowanceAndEmits() public {
        bytes32 beforeState = _state();
        vm.expectEmit(address(token));
        emit Transfer(alice, carol, 0);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 0));
        assertEq(_state(), beforeState);
    }

    function test_approvalCannotBeBorrowedByAnotherSpender() public {
        token.approve(bob, type(uint256).max);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, carol, 0, 1));
        vm.prank(carol);
        token.transferFrom(address(this), alice, 1);
        assertEq(_state(), beforeState);
    }

    function test_insufficientBalanceDoesNotConsumeAllowanceAndCanBeRetried() public {
        token.transfer(alice, 17);
        vm.prank(alice);
        token.approve(bob, 18);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 17, 18));
        vm.prank(bob);
        token.transferFrom(alice, carol, 18);
        assertEq(_state(), beforeState);

        token.transfer(alice, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, carol, 18));
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(carol), 18);
    }

    function test_zeroRecipientDoesNotConsumeFiniteAllowance() public {
        token.approve(bob, SUPPLY);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(address(this), address(0), SUPPLY);
        assertEq(_state(), beforeState);
    }

    function test_zeroTransferFromToZeroRecipientIsRejected() public {
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(alice, address(0), 0);
        assertEq(_state(), beforeState);
    }

    function testFuzz_selfTransferPreservesAllState(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, 0, held);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        bytes32 beforeState = _state();
        vm.prank(alice);
        assertTrue(token.transfer(alice, amount));
        assertEq(_state(), beforeState);
    }

    function testFuzz_transferRoundTripRestoresAllState(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(bob, 17);
        bytes32 beforeState = _state();
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(_state(), beforeState);
    }

    function testFuzz_partialSpendsExhaustExactlyOneApproval(uint256 budget, uint256 first) public {
        budget = bound(budget, 1, SUPPLY);
        first = bound(first, 0, budget);
        token.approve(bob, budget);
        token.approve(carol, type(uint256).max);

        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), bob), budget - first);
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), bob, budget - first));
        assertEq(token.allowance(address(this), bob), 0);
        assertEq(token.allowance(address(this), carol), type(uint256).max);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), budget - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - budget);

        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(_state(), beforeState);
    }

    function testFuzz_replacementApprovalIsTheEntireNewBudget(uint256 first, uint256 replacement) public {
        token.approve(bob, first);
        assertTrue(token.approve(bob, replacement));
        assertEq(token.allowance(address(this), bob), replacement);
        assertEq(token.balanceOf(address(this)), SUPPLY);

        uint256 spend = replacement < SUPPLY ? replacement : SUPPLY;
        vm.prank(bob);
        assertTrue(token.transferFrom(address(this), alice, spend));
        uint256 remaining = replacement == type(uint256).max ? replacement : replacement - spend;
        assertEq(token.allowance(address(this), bob), remaining);
        assertEq(token.balanceOf(alice), spend);
        assertEq(token.balanceOf(address(this)), SUPPLY - spend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedDelegatedTransferPreservesState(uint256 held, uint256 attempted, bool unlimited) public {
        held = bound(held, 0, SUPPLY);
        attempted = bound(attempted, held + 1, type(uint256).max);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, unlimited ? type(uint256).max : attempted);
        bytes32 beforeState = _state();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, attempted));
        vm.prank(bob);
        token.transferFrom(alice, carol, attempted);
        assertEq(_state(), beforeState);
    }

    function testFuzz_zeroRecipientPreservesAllowance(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max);
        token.approve(bob, allowed);
        bytes32 beforeState = _state();
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(bob);
        token.transferFrom(address(this), address(0), amount);
        assertEq(_state(), beforeState);
    }

    /// @dev Snapshot every balance and allowance reachable in this fixture, including zero.
    function _state() internal view returns (bytes32) {
        address[5] memory accounts = [address(this), alice, bob, carol, address(0)];
        bytes32 state = keccak256(abi.encode(token.totalSupply()));
        for (uint256 i; i < accounts.length; ++i) {
            state = keccak256(abi.encode(state, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; ++j) {
                state = keccak256(abi.encode(state, token.allowance(accounts[i], accounts[j])));
            }
        }
        return state;
    }
}
