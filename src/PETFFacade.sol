// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {AccessControlUpgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {PETFFacadeStory} from "./abstracts/storys/PETFFacadeStory.sol";
import {IPETFTrading} from "./interfaces/IPETFTrading.sol";
import {IPETFRD} from "./interfaces/IPETFRD.sol";
import {IPermissionedETF} from "./interfaces/IPETFToken.sol";
import {Roles} from "./abstracts/Roles.sol";

/// @title PETFFacade
/// @notice Facade contract that orchestrates all trading and reward-distribution
///         operations for the Permissioned ETF. Separated from PETFToken to keep
///         the token contract within the EIP-170 24 KB bytecode limit.
contract PETFFacade is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    PETFFacadeStory,
    Roles
{
    using SafeERC20 for IERC20;

    /// ======= Constructor =======
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address petfToken,
        address petfTrading,
        address petfRewardDistributor,
        address assetRecipient,
        address serviceFeeRecipient,
        uint96 boardLotSize
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());

        PETFFacadeStorage storage $ = _getFacadeStorage();
        $.petfToken = IPermissionedETF(petfToken);
        $.petfTrading = IPETFTrading(petfTrading);
        $.petfRewardDistributor = IPETFRD(petfRewardDistributor);
        $.assetRecipient = assetRecipient;
        $.serviceFeeRecipient = serviceFeeRecipient;
        $.boardLotSize = boardLotSize;
        $.hasMinAmount = true;
    }

    /// ======= Modifiers =======

    modifier onlyAllowed(address account) {
        if (!_getFacadeStorage().petfToken.isWhitelisted(account))
            revert NotAllowed(account);
        _;
    }

    modifier checkETFAmount(uint256 cAmount) {
        _checkEtfAmount(cAmount);
        _;
    }

    /// ======= Config Setters / Getters =======

    function setBoardLotSize(
        uint96 boardLotSize
    ) external onlyRole(CONTRACT_ADMIN) {
        _getFacadeStorage().boardLotSize = boardLotSize;
    }

    function getBoardLotSize() external view returns (uint96) {
        return _getFacadeStorage().boardLotSize;
    }

    function setHasMinAmount(
        bool hasMinAmount
    ) external onlyRole(CONTRACT_ADMIN) {
        _getFacadeStorage().hasMinAmount = hasMinAmount;
    }

    function getHasMinAmount() external view returns (bool) {
        return _getFacadeStorage().hasMinAmount;
    }

    function setPetfTrading(
        address petfTrading
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getFacadeStorage().petfTrading = IPETFTrading(petfTrading);
    }

    function setRewardDistributor(
        address petfRewardDistributor
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getFacadeStorage().petfRewardDistributor = IPETFRD(
            petfRewardDistributor
        );
    }

    function setSupportedTokenAddress(
        IERC20 tokenAddress,
        bool isSupported
    ) external onlyRole(CONTRACT_ADMIN) {
        _getFacadeStorage().supportedTokenAddress[tokenAddress] = isSupported;
    }

    function setAssetRecipient(
        address assetRecipient
    ) external onlyRole(CONTRACT_ADMIN) {
        _getFacadeStorage().assetRecipient = assetRecipient;
    }

    function setServiceFeeRecipient(
        address serviceFeeRecipient
    ) external onlyRole(CONTRACT_ADMIN) {
        _getFacadeStorage().serviceFeeRecipient = serviceFeeRecipient;
    }

    function pause() external onlyRole(CONTRACT_ADMIN) {
        _pause();
    }

    function unpause() external onlyRole(CONTRACT_ADMIN) {
        _unpause();
    }

    /// PETFTrading upgrade proxy passthrough
    function PETFTradingUpgradeToAndCall(
        address newImplementation,
        bytes memory data
    ) external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        _getFacadeStorage().petfTrading.upgradeToAndCall{value: msg.value}(
            newImplementation,
            data
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ON-CHAIN SUBSCRIBE
    //////////////////////////////////////////////////////////////*/

    function onChainSubscribe(
        uint128 usdAmount,
        uint128 orderEtfAmount,
        uint96 deadline,
        address usdAddress,
        bytes calldata signature
    )
        external
        whenNotPaused
        onlyAllowed(_msgSender())
        checkETFAmount(orderEtfAmount)
    {
        _checkSupportedTokenAddress(IERC20(usdAddress));

        if (block.timestamp > deadline) revert ExpiredOrder();

        uint256 balanceBefore = IERC20(usdAddress).balanceOf(address(this));
        IERC20(usdAddress).safeTransferFrom(
            _msgSender(),
            address(this),
            usdAmount
        );
        uint256 balanceAfter = IERC20(usdAddress).balanceOf(address(this));
        usdAmount = uint128(balanceAfter - balanceBefore);

        _getFacadeStorage().petfTrading.onChainSubscribe(
            usdAmount,
            orderEtfAmount,
            _msgSender(),
            deadline,
            usdAddress,
            signature
        );
    }

    function updateOnChainSubscribe(
        uint96 subscriptionId,
        uint96 actualPrice,
        uint128 actualEtfAmount,
        uint128 actualUSDAmount,
        uint128 actualRefundUSDAmount,
        uint80 actualTransactionFee,
        string memory offChainId
    ) external onlyRole(TRADE_ADMIN) checkETFAmount(actualEtfAmount) {
        address account = _getFacadeStorage().petfTrading.getSubscriptionUser(
            subscriptionId
        );
        _notBlacklisted(account);

        _getFacadeStorage().petfTrading.updateOnChainSubscribe(
            subscriptionId,
            actualPrice,
            actualEtfAmount,
            actualUSDAmount,
            actualRefundUSDAmount,
            actualTransactionFee,
            offChainId
        );
    }

    function revertOnChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(TRADE_ADMIN) {
        PETFFacadeStorage storage $ = _getFacadeStorage();
        IPETFTrading.SubscribeData memory sd = $.petfTrading.getSubscribeData(
            subscriptionId
        );

        $.petfTrading.revertOnChainSubscribe(subscriptionId);

        IERC20(sd.usdAddress).safeTransfer(sd.user, sd.usdAmount);
    }

    function settleOnChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(TRADE_ADMIN) {
        PETFFacadeStorage storage $ = _getFacadeStorage();
        IPETFTrading.SubscribeData memory sd = $.petfTrading.getSubscribeData(
            subscriptionId
        );

        _notBlacklisted($.petfTrading.getSubscriptionUser(subscriptionId));

        $.petfTrading.settleOnChainSubscribe(subscriptionId);

        if (sd.actualUSDAmount > 0)
            IERC20(sd.usdAddress).safeTransfer(
                $.assetRecipient,
                sd.actualUSDAmount
            );
        if (sd.actualTransactionFee > 0)
            IERC20(sd.usdAddress).safeTransfer(
                $.serviceFeeRecipient,
                sd.actualTransactionFee
            );
    }

    function claim(uint96 subscriptionId) external whenNotPaused {
        PETFFacadeStorage storage $ = _getFacadeStorage();

        _notBlacklisted($.petfTrading.getSubscriptionUser(subscriptionId));

        IPETFTrading.SubscribeData memory sd = $.petfTrading.getSubscribeData(
            subscriptionId
        );

        if (sd.user != _msgSender()) revert OnlyTheRedeemerCanClaim();
        if (!sd.isSettled) revert SubscriptionNotSettled();

        $.petfToken.mintETF(_msgSender(), sd.actualEtfAmount);

        if (sd.actualRefundUSDAmount > 0) {
            IERC20(sd.usdAddress).safeTransfer(
                sd.user,
                sd.actualRefundUSDAmount
            );
        }

        $.petfTrading.claim(subscriptionId);
    }

    /*//////////////////////////////////////////////////////////////
                            ON-CHAIN REDEMPTION
    //////////////////////////////////////////////////////////////*/

    function onChainRedemption(
        address usdAddress,
        uint128 actualEtfAmount,
        uint128 deadline,
        bytes calldata signature
    ) external whenNotPaused {
        _checkSupportedTokenAddress(IERC20(usdAddress));
        _notBlacklisted(_msgSender());
        _checkEtfAmount(actualEtfAmount);

        if (deadline < block.timestamp) revert ExpiredOrder();

        _getFacadeStorage().petfTrading.onChainRedemption(
            usdAddress,
            actualEtfAmount,
            deadline,
            _msgSender(),
            signature
        );
    }

    function updateOnChainRedemption(
        uint96 redemptionId,
        uint128 actualUSDAmount,
        uint96 actualPrice,
        uint80 actualTransactionFee
    ) external onlyRole(TRADE_ADMIN) {
        PETFFacadeStorage storage $ = _getFacadeStorage();
        _notBlacklisted($.petfTrading.getRedemptionUser(redemptionId));

        $.petfTrading.updateOnChainRedemption(
            redemptionId,
            actualUSDAmount,
            actualPrice,
            actualTransactionFee
        );
    }

    function revertOnChainRedemption(
        uint96 redemptionId
    ) external onlyRole(TRADE_ADMIN) {
        _getFacadeStorage().petfTrading.revertOnChainRedemption(redemptionId);
    }

    function settleOnChainRedemption(
        uint96 redemptionId
    ) external onlyRole(TRADE_ADMIN) {
        PETFFacadeStorage storage $ = _getFacadeStorage();
        IPETFTrading.RedemptionData memory rd = $.petfTrading.getRedemptionData(
            redemptionId
        );
        _notBlacklisted(rd.user);

        $.petfTrading.settleOnChainRedemption(redemptionId);
        $.petfToken.burnETF(rd.user, rd.actualEtfAmount);

        emit TransferWithIdEvent(rd.user, address(0), rd.actualEtfAmount);
    }

    function claimUSD(uint96 redemptionId) public whenNotPaused {
        _notBlacklisted(_msgSender());

        PETFFacadeStorage storage $ = _getFacadeStorage();

        if ($.petfTrading.getRedemptionUser(redemptionId) != _msgSender())
            revert OnlyTheRedeemerCanClaim();

        IPETFTrading.RedemptionData memory rd = $.petfTrading.getRedemptionData(
            redemptionId
        );

        $.petfTrading.claimUSD(redemptionId);

        IERC20(rd.usdAddress).safeTransferFrom(
            $.assetRecipient,
            rd.user,
            rd.actualUSDAmount
        );
    }

    /*//////////////////////////////////////////////////////////////
                            OFF-CHAIN SUBSCRIBE
    //////////////////////////////////////////////////////////////*/

    function offChainSubscribe(
        uint128 usdAmount,
        uint128 orderEtfAmount,
        uint128 actualEtfAmount,
        address usdAddress,
        address user,
        uint96 actualPrice,
        uint80 actualTransactionFee,
        string calldata offChainId
    ) external onlyRole(TRADE_ADMIN) {
        _checkSupportedTokenAddress(IERC20(usdAddress));
        _notBlacklisted(user);
        _checkEtfAmount(actualEtfAmount);

        _getFacadeStorage().petfTrading.offChainSubscribe(
            usdAmount,
            orderEtfAmount,
            actualEtfAmount,
            usdAddress,
            user,
            actualPrice,
            actualTransactionFee,
            offChainId
        );
    }

    function revertOffChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(TRADE_ADMIN) {
        _getFacadeStorage().petfTrading.revertOffChainSubscribe(subscriptionId);
    }

    function settleOffChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(TRADE_ADMIN) {
        _getFacadeStorage().petfTrading.settleOffChainSubscribe(subscriptionId);
    }

    function distributeSubscribe(
        uint96 subscriptionId
    ) external onlyRole(TRADE_ADMIN) {
        PETFFacadeStorage storage $ = _getFacadeStorage();
        IPETFTrading.SubscribeData memory sd = $.petfTrading.getSubscribeData(
            subscriptionId
        );
        _notBlacklisted(sd.user);

        $.petfToken.mintETF(sd.user, sd.actualEtfAmount);
        $.petfTrading.distributeSubscribe(subscriptionId);
    }

    /*//////////////////////////////////////////////////////////////
                            OFF-CHAIN REDEMPTION
    //////////////////////////////////////////////////////////////*/

    function offChainRedemption(
        uint128 actualUSDAmount,
        address usdAddress,
        uint128 actualEtfAmount,
        address user,
        uint96 actualPrice,
        uint80 actualTransactionFee,
        string calldata offChainId
    ) external onlyRole(TRADE_ADMIN) {
        _checkSupportedTokenAddress(IERC20(usdAddress));
        _notBlacklisted(user);

        _getFacadeStorage().petfTrading.offChainRedemption(
            actualUSDAmount,
            usdAddress,
            actualEtfAmount,
            user,
            actualPrice,
            actualTransactionFee,
            offChainId
        );
    }

    function revertOffChainRedemption(
        uint96 redemptionId
    ) external onlyRole(TRADE_ADMIN) {
        _getFacadeStorage().petfTrading.revertOffChainRedemption(redemptionId);
    }

    function settleOffChainRedemption(
        uint96 redemptionId
    ) external onlyRole(TRADE_ADMIN) {
        _getFacadeStorage().petfTrading.settleOffChainRedemption(redemptionId);
    }

    // function burnAdmin(uint96 redemptionId) external onlyRole(TRADE_ADMIN) {
    //     PETFFacadeStorage storage $ = _getFacadeStorage();
    //     IPETFTrading.RedemptionData memory rd = $.petfTrading.getRedemptionData(
    //         redemptionId
    //     );

    //     $.petfTrading.burn(redemptionId);
    //     $.petfToken.burnETF(rd.user, rd.actualEtfAmount);

    //     emit TransferWithIdEvent(rd.user, address(0), rd.actualEtfAmount);
    // }

    /*//////////////////////////////////////////////////////////////
                            VIEW PASSTHROUGH
    //////////////////////////////////////////////////////////////*/

    function getSubscribeData(
        uint96 subscriptionId
    ) public view returns (IPETFTrading.SubscribeData memory) {
        return _getFacadeStorage().petfTrading.getSubscribeData(subscriptionId);
    }

    function getRedemptionData(
        uint96 redemptionId
    ) public view returns (IPETFTrading.RedemptionData memory) {
        return _getFacadeStorage().petfTrading.getRedemptionData(redemptionId);
    }

    function nonceOf(address user) public view returns (uint256) {
        return _getFacadeStorage().petfTrading.nonceOf(user);
    }

    function addOnRemoveAuthorizedSigner(
        address signer,
        bool isAdd
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getFacadeStorage().petfTrading.addOnRemoveAuthorizedSigner(
            signer,
            isAdd
        );
    }

    function getAuthorizedSigner(address signer) public view returns (bool) {
        return _getFacadeStorage().petfTrading.getAuthorizedSigner(signer);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARD DISTRIBUTOR
    //////////////////////////////////////////////////////////////*/

    function createRewardPhase(
        uint256 id,
        bytes32 merkleRoot,
        uint256 totalAmount,
        IERC20 rewardToken,
        address rewardSender
    ) external onlyRole(DIVIDEND_ADMIN) {
        _getFacadeStorage().petfRewardDistributor.createRewardPhase(
            id,
            merkleRoot,
            totalAmount,
            rewardToken,
            rewardSender
        );
    }

    function updateRewardMerkleRoot(
        uint256 period,
        bytes32 merkleRoot
    ) external onlyRole(DIVIDEND_ADMIN) {
        _getFacadeStorage().petfRewardDistributor.updateMerkleRoot(
            period,
            merkleRoot
        );
    }

    function cancelRewardPhase(
        uint256 period,
        address recipient
    ) external onlyRole(DIVIDEND_ADMIN) {
        _getFacadeStorage().petfRewardDistributor.cancelRewardPhase(
            period,
            recipient
        );
    }

    function emergencyWithdrawReward(
        uint256 period,
        address recipient
    ) external onlyRole(DIVIDEND_ADMIN) {
        _getFacadeStorage().petfRewardDistributor.emergencyWithdraw(
            period,
            recipient
        );
    }

    function claimReward(
        uint256 period,
        uint256 amount,
        uint256 index,
        bytes32[] calldata merkleProof
    ) external whenNotPaused {
        _notBlacklisted(_msgSender());
        _getFacadeStorage().petfRewardDistributor.claimReward(
            period,
            amount,
            index,
            merkleProof,
            _msgSender()
        );
    }

    /// ======= Internal Helpers =======

    function _checkEtfAmount(uint256 cAmount) internal view {
        PETFFacadeStorage storage $ = _getFacadeStorage();
        if ($.hasMinAmount) {
            uint256 lotSize = $.boardLotSize;
            if (lotSize == 0 || cAmount % lotSize != 0)
                revert InvalidTransferAmount(cAmount);
        }
    }

    function _checkSupportedTokenAddress(IERC20 tokenAddress) internal view {
        if (!_getFacadeStorage().supportedTokenAddress[tokenAddress])
            revert UnsupportedTokenAddress(tokenAddress);
    }

    function _notBlacklisted(address account) internal view {
        if (_getFacadeStorage().petfToken.isBlacklisted(account))
            revert Blacklisted(account);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
