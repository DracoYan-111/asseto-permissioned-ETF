// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @notice Minimal interface that PETFFacade uses to interact with PETFToken.
interface IPermissionedETF {
    /// @dev Mints ETF tokens to `to`. Callable only by ETF_ADMIN (i.e. PETFFacade).
    function mintETF(address to, uint256 amount) external;

    /// @dev Burns ETF tokens from `from` with a pre-burn snapshot. Callable only by ETF_ADMIN.
    function burnETF(address from, uint256 amount) external;

    /// @dev Returns true if `account` is explicitly BLOCKED.
    function isBlacklisted(address account) external view returns (bool);

    /// @dev Returns true if `account` is explicitly ALLOWED (whitelisted).
    function isWhitelisted(address account) external view returns (bool);
}
