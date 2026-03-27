// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20Upgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

import {PETFTokenStory, IPETFTrading, IPETFRD} from "./abstracts/storys/PETFTokenStory.sol";

import {Blacklistable} from "./abstracts/Blacklistable.sol";
import {Snapshot} from "./abstracts/Snapshot.sol";
import {Roles} from "./abstracts/Roles.sol";

/// @title PermissionedETF
/// @notice A contract for a permissioned ETF
/// @dev This contract is a permissioned ETF that allows for the creation of a token that can be used to track the price of a basket of assets
contract PETFToken is
    Initializable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable,
    PETFTokenStory,
    Blacklistable,
    Snapshot,
    Roles
{
    /// ======= Using =======
    using SafeERC20 for IERC20;

    /// ======= Error =======

    /// ======= Event =======

    /// ======= Constants =======

    /// ======= Storage =======

    /// ======= Enum =======

    /// ======= Constructor =======
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        uint96 boardLotSize
    ) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        // Set the board lot size
        _getPermissionedEtfStorage().boardLotSize = boardLotSize;
        _getPermissionedEtfStorage().hasMinAmount = true;
    }

    /// ======= Modifiers =======
    modifier checkETFAmount(uint256 cAmount) {
        _checkEtfAmount(cAmount);
        _;
    }

    /// ======= External Functions =======
    function createNewSnapshot()
        public
        onlyRole(SNAPSHOT_ADMIN)
        returns (uint256)
    {
        uint256 snapshotId = _snapshot();
        return snapshotId;
    }

    function setBoardLotSize(
        uint96 boardLotSize
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getPermissionedEtfStorage().boardLotSize = boardLotSize;
    }

    function getBoardLotSize() external view returns (uint96) {
        return _getPermissionedEtfStorage().boardLotSize;
    }

    function setHasMinAmount(
        bool hasMinAmount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getPermissionedEtfStorage().hasMinAmount = hasMinAmount;
    }

    function getHasMinAmount() external view returns (bool) {
        return _getPermissionedEtfStorage().hasMinAmount;
    }

    function setPetfTrading(
        address petfTrading
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getPermissionedEtfStorage().petfTrading = IPETFTrading(petfTrading);
    }

    function getPetfTrading() external view returns (address) {
        return address(_getPermissionedEtfStorage().petfTrading);
    }

    function setRewardDistributor(
        address _ETFRewardDistributor
    ) external onlyRole(ETF_ADMIN) {
        _getPermissionedEtfStorage().petfRewardDistributor = IPETFRD(
            _ETFRewardDistributor
        );
    }

    function getRewardDistributor() external view returns (address) {
        return address(_getPermissionedEtfStorage().petfRewardDistributor);
    }

    function setSupportedTokenAddress(
        IERC20 tokenAddress,
        bool isSupported
    ) external onlyRole(ETF_ADMIN) {
        _getPermissionedEtfStorage().supportedTokenAddress[
            tokenAddress
        ] = isSupported;
    }

    function getSupportedTokenAddress(
        IERC20 tokenAddress
    ) public view returns (bool) {
        return _getPermissionedEtfStorage().supportedTokenAddress[tokenAddress];
    }

    function setAssetRecipient(
        address assetRecipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getPermissionedEtfStorage().assetRecipient = assetRecipient;
    }

    function getAssetRecipient() external view returns (address) {
        return _getPermissionedEtfStorage().assetRecipient;
    }

    function setServiceFeeRecipient(
        address serviceFeeRecipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getPermissionedEtfStorage().serviceFeeRecipient = serviceFeeRecipient;
    }

    function getServiceFeeRecipient() external view returns (address) {
        return _getPermissionedEtfStorage().serviceFeeRecipient;
    }

    /**
     * @dev Sets the restriction for a batch of accounts.
     * @param accounts The addresses of the accounts to set the restriction for.
     * @param restriction The restriction to set.
     */
    function setBatchRestriction(
        address[] calldata accounts,
        Restriction restriction
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 len = accounts.length;
        bool shouldSweepBalance = restriction != Restriction.ALLOWED;
        address receiver = _msgSender();

        for (uint256 i = 0; i < len; ) {
            address account = accounts[i];

            if (getRestriction(account) != restriction) {
                _setRestriction(account, restriction);
                emit UserRestrictionsUpdated(account, restriction);
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

    /// =======Public Functions =======

    function pause() public onlyRole(ETF_ADMIN) {
        _pause();
    }

    function unpause() public onlyRole(ETF_ADMIN) {
        _unpause();
    }

    /**
     * @dev Force transfers tokens from one address to another.
     * @param from The address of the sender.
     * @param to The address of the recipient.
     * @param amount The amount of tokens to transfer.
     */
    function forceTransfer(
        address from,
        address to,
        uint256 amount
    ) public onlyRole(ETF_ADMIN) {
        if (to != address(0)) _snapshotAccount(to, balanceOf(to));

        if (from != address(0)) _snapshotAccount(from, balanceOf(from));

        _snapshotTotalSupply(totalSupply());

        super._update(from, to, amount);

        _snapshot();
        if (to != address(0)) _snapshotAccount(to, balanceOf(to));

        if (from != address(0)) _snapshotAccount(from, balanceOf(from));

        _snapshotTotalSupply(totalSupply());
    }

    /// ======= Internal Functions =======

    function _checkEtfAmount(uint256 cAmount) internal view {
        if (_getPermissionedEtfStorage().hasMinAmount) {
            uint256 lotSize = _getPermissionedEtfStorage().boardLotSize;

            if (lotSize == 0 || cAmount % lotSize != 0)
                revert InvalidTransferAmount(cAmount);
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @dev Updates the balance of the specified address and the total supply.
     *
     * Rules:
     * - `boardLotSize` must be configured (`boardLotSize != 0`).
     * - `value` must be a multiple of `boardLotSize` (including `value == 0`).
     *   Otherwise reverts with {InvalidTransferAmount}.
     *
     * @param from The address of the sender.
     * @param to The address of the recipient.
     * @param value The amount of tokens to transfer.
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        _enforcePermissionedTransferPolicy(from, to);

        if (to != address(0)) _snapshotAccount(to, balanceOf(to));

        _snapshotTotalSupply(totalSupply());

        super._update(from, to, value);
    }

    /**
     * @dev Enforces the permissioned transfer policy used in {_update}.
     *
     * Rules:
     * - Mint path (`from == address(0)`): only allowed when `to` is `Restriction.ALLOWED`.
     * - Burn path (`to == address(0)`): always forbidden on this path (user burn disabled).
     * - Peer transfer path (`from != 0 && to != 0`): always forbidden between users.
     *
     * Admin repair operations that must bypass these restrictions should call `super._update`.
     *
     * @param from Token source address.
     * @param to Token destination address.
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

    function _checkSupportedTokenAddress(IERC20 tokenAddress) internal view {
        if (!_getPermissionedEtfStorage().supportedTokenAddress[tokenAddress])
            revert UnsupportedTokenAddress(tokenAddress);
    }

    /// PETFTrading interface implementation
    function PETFTradingUpgradeToAndCall(
        address newImplementation,
        bytes memory data
    ) external payable onlyRole(DEFAULT_ADMIN_ROLE) {
        _getPermissionedEtfStorage().petfTrading.upgradeToAndCall(
            newImplementation,
            data
        );
    }

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

        _getPermissionedEtfStorage().petfTrading.onChainSubscribe(
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
        PermissionedEtfStorage storage $ = _getPermissionedEtfStorage();

        address account = $.petfTrading.getSubscriptionUser(subscriptionId);

        _notBlacklisted(account);

        $.petfTrading.updateOnChainSubscribe(
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
        IPETFTrading.SubscribeData memory sd = _getPermissionedEtfStorage()
            .petfTrading
            .getSubscribeData(subscriptionId);

        _getPermissionedEtfStorage().petfTrading.revertOnChainSubscribe(
            subscriptionId
        );

        IERC20(sd.usdAddress).safeTransfer(sd.user, sd.usdAmount);
    }

    function settleOnChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(TRADE_ADMIN) {
        PermissionedEtfStorage storage $ = _getPermissionedEtfStorage();
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
        PermissionedEtfStorage storage $ = _getPermissionedEtfStorage();

        _notBlacklisted($.petfTrading.getSubscriptionUser(subscriptionId));

        IPETFTrading.SubscribeData memory sd = $.petfTrading.getSubscribeData(
            subscriptionId
        );

        if (sd.user != _msgSender()) revert OnlyTheRedeemerCanClaim();

        if (!sd.isSettled) revert SubscriptionNotSettled();

        super._update(address(0), _msgSender(), sd.actualEtfAmount);

        if (sd.actualRefundUSDAmount > 0) {
            IERC20(sd.usdAddress).safeTransfer(
                sd.user,
                sd.actualRefundUSDAmount
            );
        }
        $.petfTrading.claim(subscriptionId);
    }

    function onChainRedemption(
        address usdAddress,
        uint128 actualEtfAmount,
        uint128 deadline,
        bytes calldata signature
    ) external whenNotPaused {
        _checkSupportedTokenAddress(IERC20(usdAddress));

        _notBlacklisted(_msgSender());

        if (deadline < block.timestamp) revert ExpiredOrder();

        _getPermissionedEtfStorage().petfTrading.onChainRedemption(
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
        PermissionedEtfStorage storage $ = _getPermissionedEtfStorage();

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
        _getPermissionedEtfStorage().petfTrading.revertOnChainRedemption(
            redemptionId
        );
    }

    function settleOnChainRedemption(
        uint96 redemptionId
    ) external onlyRole(TRADE_ADMIN) {
        PermissionedEtfStorage storage $ = _getPermissionedEtfStorage();

        IPETFTrading.RedemptionData memory rd = $.petfTrading.getRedemptionData(
            redemptionId
        );

        _notBlacklisted(rd.user);

        $.petfTrading.settleOnChainRedemption(redemptionId);

        _snapshotAccount(rd.user, balanceOf(rd.user));
        _snapshotTotalSupply(totalSupply());

        super._update(rd.user, address(0), rd.actualEtfAmount);

        emit TransferWithIdEvent(rd.user, address(0), rd.actualEtfAmount);
    }

    function claimUSD(uint96 redemptionId) public whenNotPaused {
        _notBlacklisted(_msgSender());

        PermissionedEtfStorage storage $ = _getPermissionedEtfStorage();

        if (getRedemptionUser(redemptionId) != _msgSender())
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

        _getPermissionedEtfStorage().petfTrading.offChainSubscribe(
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
        _getPermissionedEtfStorage().petfTrading.revertOffChainSubscribe(
            subscriptionId
        );
    }

    function settleOffChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(TRADE_ADMIN) {
        _getPermissionedEtfStorage().petfTrading.settleOffChainSubscribe(
            subscriptionId
        );
    }

    function distributeSubscribe(
        uint96 subscriptionId
    ) external onlyRole(TRADE_ADMIN) {
        PermissionedEtfStorage storage $ = _getPermissionedEtfStorage();

        IPETFTrading.SubscribeData memory sd = $.petfTrading.getSubscribeData(
            subscriptionId
        );
        _notBlacklisted(sd.user);

        super._update(address(0), sd.user, sd.actualEtfAmount);

        $.petfTrading.distributeSubscribe(subscriptionId);
    }

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

        _getPermissionedEtfStorage().petfTrading.offChainRedemption(
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
        _getPermissionedEtfStorage().petfTrading.revertOffChainRedemption(
            redemptionId
        );
    }

    function settleOffChainRedemption(
        uint96 redemptionId
    ) external onlyRole(TRADE_ADMIN) {
        _getPermissionedEtfStorage().petfTrading.settleOffChainRedemption(
            redemptionId
        );
    }

    function burnAdmin(uint96 redemptionId) external onlyRole(TRADE_ADMIN) {
        PermissionedEtfStorage storage $ = _getPermissionedEtfStorage();

        IPETFTrading.RedemptionData memory rd = $.petfTrading.getRedemptionData(
            redemptionId
        );

        $.petfTrading.burn(redemptionId);

        _snapshotAccount(rd.user, balanceOf(rd.user));
        _snapshotTotalSupply(totalSupply());

        super._update(rd.user, address(0), rd.actualEtfAmount);

        emit TransferWithIdEvent(rd.user, address(0), rd.actualEtfAmount);
    }

    function getSubscriptionUser(
        uint96 subscriptionId
    ) public view returns (address) {
        return
            _getPermissionedEtfStorage().petfTrading.getSubscriptionUser(
                subscriptionId
            );
    }

    function getRedemptionUser(
        uint96 redemptionId
    ) public view returns (address) {
        return
            _getPermissionedEtfStorage().petfTrading.getRedemptionUser(
                redemptionId
            );
    }

    function getSubscribeData(
        uint96 subscriptionId
    ) public view returns (IPETFTrading.SubscribeData memory) {
        return
            _getPermissionedEtfStorage().petfTrading.getSubscribeData(
                subscriptionId
            );
    }

    function getRedemptionData(
        uint96 redemptionId
    ) public view returns (IPETFTrading.RedemptionData memory) {
        return
            _getPermissionedEtfStorage().petfTrading.getRedemptionData(
                redemptionId
            );
    }

    function nonceOf(address user) public view returns (uint256) {
        return _getPermissionedEtfStorage().petfTrading.nonceOf(user);
    }

    function addOnRemoveAuthorizedSigner(
        address signer,
        bool isAdd
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getPermissionedEtfStorage().petfTrading.addOnRemoveAuthorizedSigner(
            signer,
            isAdd
        );
    }

    function _notBlacklisted(address account) internal view {
        if (getRestriction(account) == Restriction.BLOCKED)
            revert Blacklisted(account);
    }

    /*//////////////////////////////////////////////////////////////
                            IPETFRD
    //////////////////////////////////////////////////////////////*/

    function rewardPause() external onlyRole(DIVIDEND_ADMIN) {
        _getPermissionedEtfStorage().petfRewardDistributor.pause();
    }

    function rewardUnpause() external onlyRole(DIVIDEND_ADMIN) {
        _getPermissionedEtfStorage().petfRewardDistributor.unpause();
    }

    function getRewardPauseStatus() external view returns (bool) {
        return
            _getPermissionedEtfStorage()
                .petfRewardDistributor
                .getRewardPauseStatus();
    }

    function rewardPhaseCount() external view returns (uint256) {
        return
            _getPermissionedEtfStorage()
                .petfRewardDistributor
                .rewardPhaseCount();
    }

    function isClaimed(
        uint256 period,
        uint256 index
    ) external view returns (bool) {
        return
            _getPermissionedEtfStorage().petfRewardDistributor.isClaimed(
                period,
                index
            );
    }

    function getUnclaimedStatus(
        uint256 period,
        uint256 index
    )
        external
        view
        onlyRole(DIVIDEND_ADMIN)
        returns (bool claimed, bytes32 merkleRoot)
    {
        return
            _getPermissionedEtfStorage()
                .petfRewardDistributor
                .getUnclaimedStatus(period, index);
    }

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
        )
    {
        return
            _getPermissionedEtfStorage().petfRewardDistributor.getPhaseInfo(
                period
            );
    }

    function createRewardPhase(
        uint256 id,
        bytes32 merkleRoot,
        uint256 totalAmount,
        IERC20 rewardToken,
        address rewardSender
    ) external onlyRole(DIVIDEND_ADMIN) {
        _getPermissionedEtfStorage().petfRewardDistributor.createRewardPhase(
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
        _getPermissionedEtfStorage().petfRewardDistributor.updateMerkleRoot(
            period,
            merkleRoot
        );
    }

    function cancelRewardPhase(
        uint256 period,
        address recipient
    ) external onlyRole(DIVIDEND_ADMIN) {
        _getPermissionedEtfStorage().petfRewardDistributor.cancelRewardPhase(
            period,
            recipient
        );
    }

    function emergencyWithdrawReward(
        uint256 period,
        address recipient
    ) external onlyRole(DIVIDEND_ADMIN) {
        _getPermissionedEtfStorage().petfRewardDistributor.emergencyWithdraw(
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
        _getPermissionedEtfStorage().petfRewardDistributor.claimReward(
            period,
            amount,
            index,
            merkleProof,
            _msgSender()
        );
    }

    function getAuthorizedSigner(address signer) public view returns (bool) {
        return
            _getPermissionedEtfStorage().petfTrading.getAuthorizedSigner(
                signer
            );
    }
}
