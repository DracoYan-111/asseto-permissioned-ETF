// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

abstract contract PETFTokenStory {
    /// ======= Error =======
    error NotWhitelistedOrZeroAddress(address userAddress);
    error InvalidTransferAmount(uint256 amount);
    error PeerTransferNotAllowed();
    error UserBurnNotAllowed();
}
