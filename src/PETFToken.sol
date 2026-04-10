// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {ERC20PausableUpgradeable, ERC20Upgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {PETFTokenStory} from "./abstracts/storys/PETFTokenStory.sol";
import {Blacklistable} from "./abstracts/Blacklistable.sol";
import {Snapshot} from "./abstracts/Snapshot.sol";
import {Roles} from "./abstracts/Roles.sol";

/// @title PermissionedETF Token
/// @notice ERC-20 token with whitelist, snapshot, and pause.
///         Trading configuration (board lot size, etc.) and all
///         business operations live in PETFFacade.
contract PETFToken is
    Initializable,
    ERC20PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable,
    PETFTokenStory,
    Blacklistable,
    Snapshot,
    Roles
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol
    ) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Pausable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /// ======= External Functions =======

    function createNewSnapshot()
        public
        onlyRole(DIVIDEND_ADMIN)
        returns (uint256)
    {
        return _snapshot();
    }

    /**
     * @dev Sets the restriction for a batch of accounts.
     * @param accounts The addresses of the accounts to set the restriction for.
     * @param restriction The restriction to set.
     */
    function setBatchRestriction(
        address[] calldata accounts,
        Restriction restriction
    ) external onlyRole(CONTRACT_ADMIN) {
        uint256 len = accounts.length;
        bool shouldSweepBalance = restriction != Restriction.ALLOWED;
        address receiver = _msgSender();

        for (uint256 i = 0; i < len; ) {
            address account = accounts[i];

            if (getRestriction(account) != restriction) {
                _setRestriction(account, restriction);
            }

            if (shouldSweepBalance) {
                uint256 balance = balanceOf(account);
                if (balance > 0) super._update(account, receiver, balance);
            }

            unchecked {
                ++i;
            }
        }
    }

    function pause() public onlyRole(CONTRACT_ADMIN) {
        _pause();
    }

    function unpause() public onlyRole(CONTRACT_ADMIN) {
        _unpause();
    }

    /**
     * @dev Force transfers tokens between addresses (admin repair operation).
     */
    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) public onlyRole(FIX_ADMIN) {
        if (to != address(0)) _snapshotAccount(to, balanceOf(to));
        if (from != address(0)) _snapshotAccount(from, balanceOf(from));
        _snapshotTotalSupply(totalSupply());

        ERC20Upgradeable._update(from, to, amount);

        _snapshot();
        if (to != address(0)) _snapshotAccount(to, balanceOf(to));
        if (from != address(0)) _snapshotAccount(from, balanceOf(from));
        _snapshotTotalSupply(totalSupply());
    }

    /**
     * @dev Mints ETF tokens to `to`. Callable only by PETFFacade (TRADE_ADMIN role).
     *      Bypasses the transfer-policy check — the facade is responsible for
     *      performing authorization before calling this.
     */
    function mintETF(
        address to,
        uint256 amount
    ) external onlyRole(TRADE_ADMIN) {
        _update(address(0), to, amount);
    }

    /**
     * @dev Burns ETF tokens from `from`. Callable only by PETFFacade (TRADE_ADMIN role).
     *      Takes a pre-burn snapshot before executing the burn.
     */
    function burnETF(
        address from,
        uint256 amount
    ) external onlyRole(TRADE_ADMIN) {
        _snapshotAccount(from, balanceOf(from));
        _snapshotTotalSupply(totalSupply());
        ERC20Upgradeable._update(from, address(0), amount);
    }

    /**
     * @dev Returns true if `account` is explicitly BLOCKED.
     */
    function isBlacklisted(address account) external view returns (bool) {
        return getRestriction(account) == Restriction.BLOCKED;
    }

    /**
     * @dev Returns true if `account` is explicitly ALLOWED (whitelisted).
     */
    function isWhitelisted(address account) external view returns (bool) {
        return getRestriction(account) == Restriction.ALLOWED;
    }

    /// ======= Internal Functions =======

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @dev Token transfer hook. Enforces the permissioned transfer policy and
     *      snapshots the receiver before every transfer.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20PausableUpgradeable) {
        _enforcePermissionedTransferPolicy(from, to);

        if (to != address(0)) _snapshotAccount(to, balanceOf(to));
        _snapshotTotalSupply(totalSupply());

        super._update(from, to, value);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value,
        bool emitEvent
    ) internal override(ERC20PausableUpgradeable) {
        revert ERC20InvalidSpender(spender);
    }

    /**
     * @dev Enforces the permissioned transfer policy:
     *   - Mint (from == 0): `to` must be ALLOWED.
     *   - Burn (to == 0): forbidden via user-initiated path.
     *   - Peer transfer: always forbidden.
     *
     * Admin operations that must bypass these rules should call `super._update` directly.
     */
    function _enforcePermissionedTransferPolicy(
        address from,
        address to
    ) internal view {
        if (from == address(0)) {
            if (getRestriction(to) != Restriction.ALLOWED)
                revert NotWhitelistedOrZeroAddress(to);
        } else if (to == address(0)) {
            revert UserBurnNotAllowed();
        } else {
            revert PeerTransferNotAllowed();
        }
    }
}
