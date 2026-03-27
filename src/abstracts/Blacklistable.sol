// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

abstract contract Blacklistable {
    /// ======= Using =======

    /// ======= Error =======

    error NotAllowed(address account);
    /// @dev The operation failed because the user account is restricted.
    error Blacklisted(address account);

    /// ======= Event =======
    /// @dev Emitted when a user account's restriction is updated.
    event UserRestrictionsUpdated(
        address indexed account,
        Restriction restriction
    );
    event UnBlacklisted(address indexed account);
    event BlacklisterAdminAdd(address indexed admin);

    /// ======= Constants =======
    // keccak256(abi.encode(uint256(keccak256("blacklistable.storage.Blacklistable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BlacklistableStorageLocation =
        0xac36935a01e919396c82e034781650092a25e363ad9dcbf503a24d72933de700;

    /// ======= Storage =======
    /// @custom:storage-location erc7201:blacklistable.storage.Blacklistable
    struct BlacklistableStorage {
        mapping(address account => Restriction) restrictions;
    }

    /// ======= Enum =======
    enum Restriction {
        DEFAULT, // User has no explicit restriction
        BLOCKED, // User is explicitly blocked
        ALLOWED // User is explicitly allowed
    }

    modifier onlyAllowed(address account) {
        if (getRestriction(account) != Restriction.ALLOWED)
            revert NotAllowed(account);
        _;
    }

    // modifier notBlacklisted(address account) {
    //     if (getRestriction(account) == Restriction.BLOCKED)
    //         revert Blacklisted(account);
    //     _;
    // }

    /// @dev Returns the restriction of a user account.
    function getRestriction(
        address account
    ) public view virtual returns (Restriction) {
        return _getBlacklistableStorage().restrictions[account];
    }

    /**
     * @dev Returns whether a user account is allowed to interact with the token.
     *
     * Default implementation only disallows explicitly BLOCKED accounts (i.e. a blocklist).
     *
     * To convert into an allowlist, override as:
     *
     * ```solidity
     * function isUserAllowed(address account) public view virtual override returns (bool) {
     *     return getRestriction(account) == Restriction.ALLOWED;
     * }
     * ```
     */
    function isUserAllowed(address account) public view virtual returns (bool) {
        return getRestriction(account) != Restriction.BLOCKED; // i.e. DEFAULT && ALLOWED
    }

    // We don't check restrictions for approvals since the actual transfer
    // will be checked in _update. This allows for more flexible approval patterns.

    /// @dev Updates the restriction of a user account.
    function _setRestriction(
        address account,
        Restriction restriction
    ) internal virtual {
        if (getRestriction(account) != restriction) {
            _getBlacklistableStorage().restrictions[account] = restriction;
            emit UserRestrictionsUpdated(account, restriction);
        } // no-op if restriction is unchanged
    }

    /// @dev Checks if a user account is restricted. Reverts with {ERC20Restricted} if so.
    function _checkRestriction(address account) internal view virtual {
        require(isUserAllowed(account), Blacklisted(account));
    }

    /**
     * @dev Returns the storage of the Blacklistable contract.
     */
    function _getBlacklistableStorage()
        private
        pure
        returns (BlacklistableStorage storage $)
    {
        assembly {
            $.slot := BlacklistableStorageLocation
        }
    }
}
