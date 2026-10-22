# Mutually Assured Destruction (MAD)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum (chain id 1).

| Property | Value |
| --- | --- |
| Solidity contract | `MADToken` (`src/MADToken.sol`) |
| Token name | Mutually Assured Destruction |
| Symbol | MAD |
| Decimals | 18 |
| Total supply | 1,000,000,000 MAD = `1000000000000000000000000000` minor units |
| Minting | Once, in the constructor, all of it to `msg.sender` (the deployer) |
| Constructor arguments | None |
| Owner / admin | None |
| Transfer fee, tax, burn-on-transfer | None |
| Pause, blacklist, freeze, seize | None |
| Upgradeability, delegatecall, selfdestruct | None |

## What the contract does

`MADToken` inherits OpenZeppelin's `ERC20` (v5.1.0) and adds nothing but constants and the
constructor. The constructor mints `TOTAL_SUPPLY` to `msg.sender` and never calls another contract,
so it deploys on an empty chain. After deployment the supply can only shrink if a holder sends tokens
to an unrecoverable address; nothing in the contract can mint, burn someone else's balance, pause,
or block a transfer. Every transfer, including the launch flows, moves exactly the amount requested.

The ERC-20 surface is the standard one: `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`,
`transfer`, `approve`, `allowance`, `transferFrom`, plus the public constants `TOKEN_NAME`,
`TOKEN_SYMBOL`, `DECIMALS` and `TOTAL_SUPPLY`. There is no `receive` or `fallback`, so plain ETH sent
to the token reverts.

## Assumptions

- The brief asked for a token with a name, a symbol and a fixed supply minted to the deployer. It did
  not ask for a burn function, a tax, vesting, reflections or governance, so none was added. The
  token is deliberately as small as the request allows.
- Under the IdentityMD launch, "the deployer" is the ProjectFactory. The factory receives the whole
  supply, sends 10% to the launch's MerkleDistributor, seeds 80% into the Uniswap v4 pool against
  FWA (`0xa0df17b5ac76ababa36e1450e2cbcd18a620c845`) and forwards the remaining 10% to the
  requester's `remainderTo` address. Because the token has no fee logic there is nothing to exempt,
  and the constructor takes no `$factory`, `$poolManager` or `$launchNumber` argument.
- Deployed anywhere else (a fork, a testnet, a manual deploy), the account that sends the creation
  transaction holds the whole supply. `script/Deploy.s.sol` does exactly that and nothing more.

## Deployment parameters

For the launch manifest, which the manifest step writes after this work is accepted:

- `token.contract`: `MADToken`
- `token.name`: `Mutually Assured Destruction`
- `token.symbol`: `MAD`
- `token.decimals`: `18`
- `token.constructorArgs`: `[]`
- `token.totalSupply`: `1000000000000000000000000000`
- Application contracts: none.
- Pool: paired currency FWA, fee 12500, tick spacing 60, as fixed by the launch policy.
- Economics: as given by the requester (`poolBps` 8000, `initialMarketCapWei`
  2,000,000 FWA, `remainderTo` `0xfc3c962fad2c1cc77f1a0d46e7b8a2de79a21774`).

The compiled bytecode is reproducible: `foundry.toml` pins `solc = "0.8.26"`, `evm_version =
"cancun"`, the optimizer at 200 runs, `bytecode_hash = "none"` and `cbor_metadata = false`.

### Deploying outside the launch

```
forge script script/Deploy.s.sol:DeployMADToken --rpc-url <url> --broadcast --sender <deployer> [signer flags]
```

The script has no configuration: the token takes no constructor arguments, and whoever signs the
transaction receives the supply.

## After launch

There is nothing to set. The token has no owner, no setter and no outside dependency.

## Operational responsibilities

- **The holder of the supply is responsible for it.** The constructor hands everything to the
  deployer; nothing in the contract can recover tokens sent to a wrong address or a contract that
  cannot move them. Any tokens sent to `address(0)` revert, but tokens sent to other dead addresses
  are gone.
- **No admin exists to call.** There is no pause to engage in an incident, no blacklist, no upgrade
  path. If a flaw were ever found, the only remedy would be a new token and a migration the
  community agrees to. This is a deliberate trust property, not an omission.
- **Allowances are the holder's business.** Standard ERC-20 approvals apply; an infinite approval
  to a spender is never decremented. Holders should approve only what a spender needs.
- **Explorer verification** of the deployed source and the audit of the launch flows belong to the
  network's deployer and the launch policy, not to this repository. Tests passing here are not a
  security audit.

## Repository layout

```
foundry.toml          compiler pins and build settings
remappings.txt        forge-std/ and @openzeppelin/contracts/ remappings
src/MADToken.sol      the token
script/Deploy.s.sol   local/testnet deployment helper
test/MADToken.t.sol   behaviour, launch-flow, negative, admin-surface and fuzz tests
test/Deploy.t.sol     tests the script's deploy() directly
lib/forge-std         forge-std 1.9.7 (src/ only), vendored as plain files
lib/openzeppelin-contracts
                      OpenZeppelin Contracts 5.1.0, only the files ERC20 needs
                      (ERC20, IERC20, IERC20Metadata, Context, draft-IERC6093), vendored as
                      plain files from commit 69c8def5f222ff96f2b5beff05dfba996368aa79
```

No git submodules are used. Nothing is fetched at build time.

## Tests

```
forge build
forge test
forge fmt --check
```

The suite covers:

- metadata, decimals and the exact supply minted to the deployer in one `Transfer` event;
- the deployer being whoever runs the constructor, through a CREATE2 factory stand-in;
- the launch flows (factory to distributor, distributor to claimant, pool manager round trip, the
  10/80/10 split) arriving whole and conserving supply;
- success and failure paths of `transfer`, `approve` and `transferFrom`, with the exact
  ERC-6093 error selectors and arguments;
- the privileged-call surface (`mint`, `pause`, `blacklist`, `freeze`, `burnFrom`, `seize`,
  `transferOwnership`, `upgradeTo`, ...) all reverting, from a stranger and from the deployer,
  without moving or freezing a holder;
- the runtime containing no reachable `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`, scanned the same
  way the launch floor scans it, and fitting under the EIP-170 size limit;
- fuzzed supply conservation, revert-on-overdraft, allowance accounting, and that every unknown
  selector reverts.

Tests read no environment variables and depend on no caller address, so they pass in any order and
in parallel. The fuzz tests were run with the verifier's seed
`0xc9ed7897aa6742f2673f675d24a75a4003226b769c8df7eee409961e817dd0eb`.

## Security review notes

Checked against the ethskills security checklist as adapted for this network:

- No external calls, so no reentrancy surface and no need for `SafeERC20` inside the token.
- No arithmetic beyond OpenZeppelin's checked ERC-20 accounting; no decimals conversions.
- No access control because there is no privileged function.
- No proxy, no `delegatecall`, no signatures (no `permit`), no oracle.
- Static analysers (Slither, Mythril) were not available on this machine and did not run; Foundry's
  compiler, tests and fuzzer did.
