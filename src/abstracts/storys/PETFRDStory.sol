// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

abstract contract PETFRDStory {
    /// ======= Error =======
    error InvalidProof();
    error InvalidAmount();
    error InvalidPeriod();
    error AlreadyClaimed();
    error InvalidRecipient();
    error MissingMerkleRoot();
    error InvalidRewardToken();
    error InvalidArrayLength();
    error NoRewardsToWithdraw();
    error InsufficientRewards();
    error ClaimsStarted(uint256 claimedAmount);

    /// ======= Event =======

    event RewardPhaseCreated(
        uint256 indexed id,
        uint256 indexed period,
        bytes32 merkleRoot,
        uint256 totalAmount,
        IERC20 rewardToken
    );
    event RewardPhaseFunded(
        uint256 indexed period,
        uint256 amount,
        IERC20 rewardToken
    );
    event RewardPhaseCancelled(
        uint256 indexed period,
        uint256 refundedAmount,
        IERC20 rewardToken
    );
    event EmergencyWithdrawal(
        uint256 indexed period,
        uint256 amount,
        IERC20 rewardToken,
        address indexed recipient
    );
    event RewardClaimed(
        uint256 indexed period,
        address indexed account,
        uint256 index,
        uint256 amount,
        IERC20 rewardToken
    );
    event MerkleRootUpdated(uint256 indexed period, bytes32 merkleRoot);

    /// ======= Struct =======

    struct RewardPhase {
        IERC20 rewardToken;
        uint96 totalAmount;
        bytes32 merkleRoot;
        uint256 claimedAmount;
    }

    /// ======= Constants =======

    bytes32 public constant PERMISSIONED_ETF = keccak256("PERMISSIONED_ETF");

    // keccak256(abi.encode(uint256(keccak256("PETFRD.storage.PETFRD")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PETFRDStorageLocation =
        0xebe6a974fe65e24b72b8cec5ad2228962972e09f9faf8fc6956ed60077b7d100;

    /// ======= Storage =======
    /// @custom:storage-location erc7201:PETFRD.storage.PETFRD
    struct PETFRDStorage {
        address ETFToken;
        RewardPhase[] rewardPhases;
        mapping(uint256 => BitMaps.BitMap) claimed;
    }

    function _getPETFRDStorage()
        internal
        pure
        virtual
        returns (PETFRDStorage storage $)
    {
        assembly {
            $.slot := PETFRDStorageLocation
        }
    }
}
