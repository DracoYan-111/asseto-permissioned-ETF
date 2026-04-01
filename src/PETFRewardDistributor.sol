// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlEnumerableUpgradeable,Initializable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {PETFRDStory} from "./abstracts/storys/PETFRDStory.sol";

contract PETFRewardDistributor is
    Initializable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable,
    PETFRDStory
{
    /// ======= Using =======
    using SafeERC20 for IERC20;
    using BitMaps for BitMaps.BitMap;

    /// ======= Constructor =======
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /*//////////////////////////////////////////////////////////////
                                Views
    //////////////////////////////////////////////////////////////*/

    function rewardPhaseCount()
        external
        view
        onlyRole(PETF_FACADE)
        returns (uint256)
    {
        return _getPETFRDStorage().rewardPhases.length;
    }

    function isClaimed(
        uint256 period,
        uint256 index
    ) public view onlyRole(PETF_FACADE) returns (bool) {
        return _getPETFRDStorage().claimed[period].get(index);
    }

    function getUnclaimedStatus(
        uint256 period,
        uint256 index
    )
        external
        view
        onlyRole(PETF_FACADE)
        returns (bool claimed, bytes32 merkleRoot)
    {
        PETFRDStorage storage $ = _getPETFRDStorage();

        if (period >= $.rewardPhases.length) revert InvalidPeriod();
        claimed = $.claimed[period].get(index);
        merkleRoot = $.rewardPhases[period].merkleRoot;
    }

    function getPhaseInfo(
        uint256 period
    )
        external
        view
        onlyRole(PETF_FACADE)
        returns (
            bytes32 merkleRoot,
            uint256 totalAmount,
            uint256 claimedAmount,
            IERC20 rewardToken
        )
    {
        PETFRDStorage storage $ = _getPETFRDStorage();

        if (period >= $.rewardPhases.length) revert InvalidPeriod();
        RewardPhase storage phase = $.rewardPhases[period];
        return (
            phase.merkleRoot,
            uint256(phase.totalAmount),
            phase.claimedAmount,
            phase.rewardToken
        );
    }

    /*//////////////////////////////////////////////////////////////
                            Phase Management
    //////////////////////////////////////////////////////////////*/

    function createRewardPhase(
        uint256 id,
        bytes32 merkleRoot,
        uint256 totalAmount,
        IERC20 rewardToken,
        address rewardSender
    ) external onlyRole(PETF_FACADE) {
        _createRewardPhase(
            id,
            merkleRoot,
            totalAmount,
            rewardToken,
            rewardSender
        );
    }

    function updateMerkleRoot(
        uint256 period,
        bytes32 merkleRoot
    ) external onlyRole(PETF_FACADE) {
        PETFRDStorage storage $ = _getPETFRDStorage();

        if (period >= $.rewardPhases.length) revert InvalidPeriod();
        if ($.rewardPhases[period].claimedAmount > 0)
            revert ClaimsStarted($.rewardPhases[period].claimedAmount);

        $.rewardPhases[period].merkleRoot = merkleRoot;
        emit MerkleRootUpdated(period, merkleRoot);
    }

    function cancelRewardPhase(
        uint256 period,
        address recipient
    ) external onlyRole(PETF_FACADE) {
        PETFRDStorage storage $ = _getPETFRDStorage();

        if (period >= $.rewardPhases.length) revert InvalidPeriod();
        if (recipient == address(0)) revert InvalidRecipient();

        RewardPhase storage phase = $.rewardPhases[period];
        if (phase.claimedAmount > 0) revert ClaimsStarted(phase.claimedAmount);

        uint256 refundAmount = uint256(phase.totalAmount);
        phase.totalAmount = 0;
        phase.claimedAmount = 0;
        phase.merkleRoot = bytes32(0);

        if (refundAmount > 0) {
            phase.rewardToken.safeTransfer(recipient, refundAmount);
        }

        emit RewardPhaseCancelled(period, refundAmount, phase.rewardToken);
    }

    function emergencyWithdraw(
        uint256 period,
        address recipient
    ) external onlyRole(PETF_FACADE) {
        PETFRDStorage storage $ = _getPETFRDStorage();

        if (period >= $.rewardPhases.length) revert InvalidPeriod();
        if (recipient == address(0)) revert InvalidRecipient();

        RewardPhase storage phase = $.rewardPhases[period];

        uint256 remainingAmount = uint256(phase.totalAmount) -
            phase.claimedAmount;
        if (remainingAmount == 0) revert NoRewardsToWithdraw();

        phase.totalAmount = uint96(phase.claimedAmount);
        phase.rewardToken.safeTransfer(recipient, remainingAmount);

        emit EmergencyWithdrawal(
            period,
            remainingAmount,
            phase.rewardToken,
            recipient
        );
    }

    /*//////////////////////////////////////////////////////////////
                                Claim
    //////////////////////////////////////////////////////////////*/

    function claimReward(
        uint256 period,
        uint256 amount,
        uint256 index,
        bytes32[] calldata merkleProof,
        address sender
    ) external onlyRole(PETF_FACADE) {
        _claim(sender, period, amount, index, merkleProof);
    }

    /*//////////////////////////////////////////////////////////////
                            Internal
    //////////////////////////////////////////////////////////////*/

    function _createRewardPhase(
        uint256 id,
        bytes32 merkleRoot,
        uint256 totalAmount,
        IERC20 rewardToken,
        address rewardSender
    ) internal {
        if (address(rewardToken) == address(0)) revert InvalidRewardToken();
        if (totalAmount > type(uint96).max) revert InvalidAmount();

        PETFRDStorage storage $ = _getPETFRDStorage();

        $.rewardPhases.push(
            RewardPhase({
                rewardToken: rewardToken,
                totalAmount: uint96(totalAmount),
                merkleRoot: merkleRoot,
                claimedAmount: 0
            })
        );
        uint256 period = $.rewardPhases.length - 1;
        if (totalAmount > 0) {
            rewardToken.safeTransferFrom(
                rewardSender,
                address(this),
                totalAmount
            );
            emit RewardPhaseFunded(period, totalAmount, rewardToken);
        }
        emit RewardPhaseCreated(
            id,
            period,
            merkleRoot,
            totalAmount,
            rewardToken
        );
    }

    function _claim(
        address account,
        uint256 period,
        uint256 amount,
        uint256 index,
        bytes32[] calldata merkleProof
    ) internal {
        PETFRDStorage storage $ = _getPETFRDStorage();

        if (period >= $.rewardPhases.length) revert InvalidPeriod();
        if (amount == 0) revert InvalidAmount();

        RewardPhase storage phase = $.rewardPhases[period];

        bytes32 merkleRoot = phase.merkleRoot;
        if (merkleRoot == bytes32(0)) revert MissingMerkleRoot();
        if ($.claimed[period].get(index)) revert AlreadyClaimed();

        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        if (!MerkleProof.verify(merkleProof, merkleRoot, leaf))
            revert InvalidProof();

        if (phase.claimedAmount + amount > uint256(phase.totalAmount))
            revert InsufficientRewards();

        $.claimed[period].set(index);
        unchecked {
            phase.claimedAmount += amount;
        }

        IERC20 rewardToken = phase.rewardToken;
        rewardToken.safeTransfer(account, amount);

        emit RewardClaimed(period, account, index, amount, rewardToken);
    }
}
