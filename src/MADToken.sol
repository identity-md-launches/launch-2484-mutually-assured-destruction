// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Mutually Assured Destruction (MAD)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 MAD (18 decimals) is minted
///         once, in the constructor, to the deployer (`msg.sender`). There is no owner, no further
///         minting, no transfer fee, no pause, and no blacklist: once deployed, nobody has any
///         power over the token that an ordinary holder does not have over their own balance.
/// @dev    Under the IdentityMD launch the deployer is the ProjectFactory, which forwards the
///         swarm's share to the launch's MerkleDistributor, seeds the Uniswap v4 pool and sends the
///         remainder to the requester. Every one of those flows is a plain transfer and moves
///         exactly the amount requested.
contract MADToken is ERC20 {
    /// @notice The token's human-readable name.
    string public constant TOKEN_NAME = "Mutually Assured Destruction";

    /// @notice The token's ticker symbol.
    string public constant TOKEN_SYMBOL = "MAD";

    /// @notice Number of decimals, inherited unchanged from the ERC-20 default.
    uint8 public constant DECIMALS = 18;

    /// @notice The whole supply in minor units: 1,000,000,000 * 10^18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Mints `TOTAL_SUPPLY` to `msg.sender`. Takes no arguments and calls no other contract.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
