// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "src/MADToken.sol";

/// @dev Closed actor set: every successful transfer stays inside these four accounts.
/// Expected balances come from initial allocations and transfer history, never balanceOf().
/// Expected allowances come from the latest approval and subsequent delegated spending.
contract MADTokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    MADToken public immutable token;
    address[4] public actors;

    mapping(address => uint256) public initialBalance;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public lastApproval;
    mapping(address => mapping(address => uint256)) public spentSinceApproval;

    constructor(MADToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        initialBalance[actors_[0]] = SUPPLY / 2;
        initialBalance[actors_[1]] = SUPPLY / 4;
        initialBalance[actors_[2]] = SUPPLY / 4;
        // Actor 3 starts empty but can receive funds and use them later in a sequence.
    }

    function expectedBalance(address account) public view returns (uint256) {
        return initialBalance[account] + received[account] - sent[account];
    }

    function expectedAllowance(address owner, address spender) public view returns (uint256) {
        uint256 approved = lastApproval[owner][spender];
        return approved == type(uint256).max ? approved : approved - spentSinceApproval[owner][spender];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _edgeAmount(amountSeed, expectedBalance(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function approveUnlimited(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), type(uint256).max);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        _approve(_actor(ownerSeed), _actor(spenderSeed), 0);
    }

    /// @dev Uses approvals left by earlier calls; never silently grants fresh permission.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 available = expectedBalance(owner);
        uint256 allowed = expectedAllowance(owner, spender);
        uint256 cap = available < allowed ? available : allowed;
        _transferFrom(owner, spender, _actor(toSeed), _edgeAmount(amountSeed, cap));
    }

    function transferOverBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(_actor(toSeed), amount);
        // No ledger update: every invariant must still hold after a rejection.
    }

    /// @dev Unbounded amounts exercise both balance and allowance failures, including uint256.max.
    /// Exact revert matching makes an unexpected failure visible instead of swallowing it.
    function attemptTransferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance(owner, spender);
        uint256 balance = expectedBalance(owner);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
            );
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
        } else if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
            );
            vm.prank(spender);
            token.transferFrom(owner, to, amount);
        } else {
            _transferFrom(owner, spender, to, amount);
        }
    }

    function transferToZero(uint256 fromSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 amount = _edgeAmount(amountSeed, expectedBalance(from));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance(owner);
        uint256 allowed = expectedAllowance(owner, spender);
        uint256 amount = _edgeAmount(amountSeed, balance < allowed ? balance : allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(_actor(ownerSeed));
        token.approve(address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        lastApproval[owner][spender] = amount;
        spentSinceApproval[owner][spender] = 0;
    }

    function _transferFrom(address owner, address spender, address to, uint256 amount) internal {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        _recordTransfer(owner, to, amount);
        if (lastApproval[owner][spender] != type(uint256).max) {
            spentSinceApproval[owner][spender] += amount;
        }
    }

    function _recordTransfer(address from, address to, uint256 amount) internal {
        sent[from] += amount;
        received[to] += amount;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Deliberately visit zero, one wei, and the entire available balance/allowance frequently.
    function _edgeAmount(uint256 seed, uint256 cap) internal pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return cap == 0 ? 0 : 1;
        if (seed % 4 == 2) return cap;
        return bound(seed, 0, cap);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract MADTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    MADToken internal token;
    MADTokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        actors = [
            makeAddr("MAD invariant: deployer"),
            makeAddr("MAD invariant: Alice"),
            makeAddr("MAD invariant: Bob"),
            makeAddr("MAD invariant: Carol")
        ];
        vm.prank(actors[0]);
        token = new MADToken();
        vm.startPrank(actors[0]);
        token.transfer(actors[1], SUPPLY / 4);
        token.transfer(actors[2], SUPPLY / 4);
        vm.stopPrank();

        handler = new MADTokenHandler(token, actors);
        // Finite and unlimited delegated transfers are reachable from the first random call.
        handler.approve(0, 1, SUPPLY / 4);
        handler.approveUnlimited(1, 2);

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.approveUnlimited.selector;
        selectors[3] = handler.revoke.selector;
        selectors[4] = handler.transferFrom.selector;
        selectors[5] = handler.transferOverBalance.selector;
        selectors[6] = handler.attemptTransferFrom.selector;
        selectors[7] = handler.transferToZero.selector;
        selectors[8] = handler.transferFromToZero.selector;
        selectors[9] = handler.approveZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyEqualsAllBalances() public view {
        uint256 total;
        for (uint256 i; i < actors.length; ++i) {
            total += token.balanceOf(actors[i]);
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed after constructor");
        assertEq(total, SUPPLY, "balances do not conserve the constructor supply");
        assertEq(token.balanceOf(address(0)), 0, "tokens reached the zero address");
        assertEq(token.balanceOf(address(handler)), 0, "handler unexpectedly received funds");
        assertEq(token.balanceOf(address(token)), 0, "token unexpectedly received funds");
    }

    function invariant_balancesMatchTransferHistory() public view {
        for (uint256 i; i < actors.length; ++i) {
            address account = actors[i];
            assertEq(
                token.balanceOf(account) + handler.sent(account),
                handler.initialBalance(account) + handler.received(account),
                "balance differs from authorized incoming and outgoing transfers"
            );
        }
    }

    function invariant_allowancesMatchLatestApprovalAndSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance differs from approval and spending history"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0, "zero spender received approval");
        }
    }

    /// @dev Deterministic harness check: exercise every target, successful nonzero delegation,
    /// allowance exhaustion/revocation, a balance failure, and recovery after replenishment.
    function test_handlerExercisesSpendingFailuresAndRecovery() public {
        handler.approve(0, 1, 17);
        handler.attemptTransferFrom(0, 1, 3, 10);
        assertEq(token.balanceOf(actors[3]), 10);
        assertEq(token.allowance(actors[0], actors[1]), 7);
        handler.attemptTransferFrom(0, 1, 3, 8); // Too little allowance.
        handler.transferFromToZero(0, 1, 2); // Attempts to spend all 7, then rejects the recipient.
        assertEq(token.allowance(actors[0], actors[1]), 7);
        handler.transferFrom(0, 1, 3, 2); // Spend the remaining allowance.
        assertEq(token.balanceOf(actors[3]), 17);
        assertEq(token.allowance(actors[0], actors[1]), 0);

        handler.approveUnlimited(3, 2);
        handler.attemptTransferFrom(3, 2, 0, 18); // Too little balance, despite unlimited approval.
        handler.transfer(0, 3, 1); // Replenish with one wei.
        handler.transferFrom(3, 2, 0, 2); // Drain all 18 wei.
        assertEq(token.balanceOf(actors[3]), 0);
        assertEq(token.allowance(actors[3], actors[2]), type(uint256).max);
        handler.revoke(3, 2);
        handler.attemptTransferFrom(3, 2, 0, 1);
        handler.transferOverBalance(3, 0, type(uint256).max);
        handler.transferToZero(0, 1);
        handler.approveZeroSpender(0, type(uint256).max);

        invariant_fixedSupplyEqualsAllBalances();
        invariant_balancesMatchTransferHistory();
        invariant_allowancesMatchLatestApprovalAndSpending();
    }
}
