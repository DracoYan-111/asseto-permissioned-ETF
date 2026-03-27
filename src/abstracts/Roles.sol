// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

abstract contract Roles {
    bytes32 constant ETF_ADMIN = keccak256("ETF_ADMIN");

    bytes32 constant DIVIDEND_ADMIN = keccak256("DIVIDEND_ADMIN");

    bytes32 constant TRADE_ADMIN = keccak256("TRADE_ADMIN");

    bytes32 constant SNAPSHOT_ADMIN = keccak256("SNAPSHOT_ADMIN");
}
