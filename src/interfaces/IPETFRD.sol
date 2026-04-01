// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPETFRD {
    /*//////////////////////////////////////////////////////////////
                                Errors
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                                Views
    //////////////////////////////////////////////////////////////*/

    function rewardPhaseCount() external view returns (uint256);

    function isClaimed(uint256 period, uint256 index) external view returns (bool);

    function getUnclaimedStatus(
        uint256 period,
        uint256 index
    ) external view returns (bool claimed, bytes32 merkleRoot);

    function getPhaseInfo(
        uint256 period
    )
        external
        view
        returns (
            bytes32 merkleRoot,
            uint256 totalAmount,
            uint256 claimedAmount,
            IERC20 rewardToken
        );

    /*//////////////////////////////////////////////////////////////
                            Phase Management
    //////////////////////////////////////////////////////////////*/

    function createRewardPhase(
        uint256 id,
        bytes32 merkleRoot,
        uint256 totalAmount,
        IERC20 rewardToken,
        address rewardSender
    ) external;

    function updateMerkleRoot(uint256 period, bytes32 merkleRoot) external;

    function cancelRewardPhase(uint256 period, address recipient) external;

    function emergencyWithdraw(uint256 period, address recipient) external;

    /*//////////////////////////////////////////////////////////////
                                Claim
    //////////////////////////////////////////////////////////////*/

    function claimReward(
        uint256 period,
        uint256 amount,
        uint256 index,
        bytes32[] calldata merkleProof,
        address sender
    ) external;
}
