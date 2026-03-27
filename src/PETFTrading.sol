// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {EIP712Upgradeable, Initializable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {PETFTradingStory} from "./abstracts/storys/PETFTradingStory.sol";
import {Roles} from "./abstracts/Roles.sol";

contract PETFTrading is
    Initializable,
    AccessControlEnumerableUpgradeable,
    EIP712Upgradeable,
    UUPSUpgradeable,
    PETFTradingStory,
    Roles
{
    /// ======= Using =======
    using SafeERC20 for IERC20;

    /// ======= Enum =======

    /// ======= Modifiers =======

    /// ======= Constructor =======
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _permissionedETF) public initializer {
        __AccessControl_init();
        __EIP712_init("ETFTrading", "1");

        _grantRole(PERMISSIONED_ETF, _permissionedETF);
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(ETF_ADMIN, _msgSender());
    }

    // /*//////////////////////////////////////////////////////////////
    //                    Interface Implementation
    // //////////////////////////////////////////////////////////////*/

    // /*//////////////////////////////////////////////////////////////
    //                            onChain
    // //////////////////////////////////////////////////////////////*/

    function onChainSubscribe(
        uint128 usdAmount,
        uint128 orderEtfAmount,
        address user,
        uint96 deadline,
        address usdAddress,
        bytes calldata signature
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SUBSCRIBE_ORDER_TYPEHASH,
                    usdAddress,
                    usdAmount,
                    orderEtfAmount,
                    user,
                    $.nonces[user]++,
                    deadline
                )
            )
        );

        if (!$.isAuthorizedSigner[ECDSA.recover(digest, signature)])
            revert InvalidSignature();

        uint96 subscriptionId = ++$.nextId;

        SubscribeData storage sd = $.subscribeDataMap[subscriptionId];
        sd.usdAmount = usdAmount;
        sd.usdAddress = usdAddress;
        sd.orderEtfAmount = orderEtfAmount;
        sd.user = user;
        sd.isOnChain = true;

        emit OnChainSubscribeEvent(
            subscriptionId,
            usdAmount,
            usdAddress,
            user,
            orderEtfAmount,
            digest
        );
    }

    function updateOnChainSubscribe(
        uint96 subscriptionId,
        uint96 actualPrice,
        uint128 actualEtfAmount,
        uint128 actualUSDAmount,
        uint128 actualRefundUSDAmount,
        uint80 actualTransactionFee,
        string calldata offChainId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        SubscribeData storage sd = $.subscribeDataMap[subscriptionId];
        if (sd.user == address(0)) revert SubscriptionDoesNotExist();

        if (actualUSDAmount == 0 || actualUSDAmount > sd.usdAmount)
            revert InvalidTransferAmount(actualUSDAmount);

        if (sd.isSettled) revert SubscriptionAlreadySettled();

        sd.actualEtfAmount = actualEtfAmount;
        sd.actualPrice = actualPrice;
        sd.actualUSDAmount = actualUSDAmount;
        sd.actualRefundUSDAmount = actualRefundUSDAmount;
        sd.actualTransactionFee = actualTransactionFee;

        emit UpdateOnChainSubscribeEvent(
            subscriptionId,
            actualEtfAmount,
            actualPrice,
            actualUSDAmount,
            actualRefundUSDAmount,
            actualTransactionFee,
            offChainId
        );
    }

    function revertOnChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        SubscribeData storage sd = $.subscribeDataMap[subscriptionId];

        if (sd.user == address(0)) revert SubscriptionDoesNotExist();

        if (sd.isSettled) revert SubscriptionAlreadySettled();

        emit RevertOnChainSubscribeEvent(
            subscriptionId,
            sd.usdAmount,
            sd.usdAddress,
            sd.actualEtfAmount,
            sd.orderEtfAmount,
            sd.user,
            sd.actualPrice,
            sd.actualUSDAmount,
            sd.actualRefundUSDAmount,
            sd.actualTransactionFee
        );
        delete $.subscribeDataMap[subscriptionId];
    }

    function settleOnChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        SubscribeData storage sd = $.subscribeDataMap[subscriptionId];
        if (sd.user == address(0)) revert SubscriptionDoesNotExist();

        if (sd.isSettled) revert SubscriptionAlreadySettled();

        sd.isSettled = true;

        emit SettleOnChainSubscribeEvent(
            subscriptionId,
            sd.actualEtfAmount,
            sd.actualPrice,
            sd.actualUSDAmount,
            sd.actualRefundUSDAmount,
            sd.actualTransactionFee
        );
    }

    function claim(uint96 subscriptionId) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        SubscribeData storage sd = $.subscribeDataMap[subscriptionId];

        emit ClaimEvent(
            subscriptionId,
            sd.usdAmount,
            sd.usdAddress,
            sd.actualEtfAmount,
            sd.orderEtfAmount,
            sd.user,
            sd.actualPrice,
            sd.actualUSDAmount,
            sd.actualRefundUSDAmount,
            sd.actualTransactionFee,
            uint256(0)
        );
        delete $.subscribeDataMap[subscriptionId];
    }

    function onChainRedemption(
        address usdAddress,
        uint128 actualEtfAmount,
        uint128 deadline,
        address user,
        bytes calldata signature
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    REDEEM_ORDER_TYPEHASH,
                    usdAddress,
                    actualEtfAmount,
                    user,
                    $.nonces[user]++,
                    deadline
                )
            )
        );

        address recovered = ECDSA.recover(digest, signature);
        if (!$.isAuthorizedSigner[recovered]) revert InvalidSignature();

        uint96 redemptionId = ++$.nextId;

        RedemptionData storage rd = $.redemptionDataMap[redemptionId];

        rd.usdAddress = usdAddress;
        rd.actualEtfAmount = actualEtfAmount;
        rd.user = user;
        rd.isOnChain = true;

        emit OnChainRedemptionEvent(
            redemptionId,
            usdAddress,
            actualEtfAmount,
            user,
            digest
        );
    }

    function updateOnChainRedemption(
        uint96 redemptionId,
        uint128 actualUSDAmount,
        uint96 actualPrice,
        uint80 actualTransactionFee
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();
        RedemptionData storage rd = $.redemptionDataMap[redemptionId];

        if (rd.user == address(0)) revert RedemptionDoesNotExist();
        if (rd.isSettled) revert RedemptionAlreadySettled();
        if (actualUSDAmount == 0) revert InvalidTransferAmount(actualUSDAmount);

        rd.actualUSDAmount = actualUSDAmount;
        rd.actualPrice = actualPrice;
        rd.actualTransactionFee = actualTransactionFee;

        emit UpdateOnChainRedemptionEvent(
            redemptionId,
            actualUSDAmount,
            actualPrice,
            actualTransactionFee
        );
    }

    function revertOnChainRedemption(
        uint96 redemptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();
        RedemptionData storage rd = $.redemptionDataMap[redemptionId];

        if (rd.user == address(0)) revert RedemptionDoesNotExist();
        if (rd.isSettled) revert RedemptionAlreadySettled();

        emit RevertOnChainRedemptionEvent(
            redemptionId,
            rd.actualUSDAmount,
            rd.usdAddress,
            rd.actualEtfAmount,
            rd.user,
            rd.actualPrice,
            rd.actualTransactionFee
        );
        delete $.redemptionDataMap[redemptionId];
    }

    function settleOnChainRedemption(
        uint96 redemptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        RedemptionData storage rd = $.redemptionDataMap[redemptionId];

        if (rd.user == address(0)) revert RedemptionDoesNotExist();
        if (rd.isSettled) revert RedemptionAlreadySettled();

        rd.isSettled = true;

        emit SettleOnChainRedemptionEvent(
            redemptionId,
            rd.actualUSDAmount,
            rd.usdAddress,
            rd.actualEtfAmount,
            rd.user,
            rd.actualPrice,
            rd.actualTransactionFee
        );
    }

    function claimUSD(uint96 redemptionId) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        RedemptionData storage rd = $.redemptionDataMap[redemptionId];
        if (rd.user == address(0)) revert RedemptionDoesNotExist();
        if (!rd.isSettled) revert RedemptionNotSettled();

        emit ClaimUSDEvent(
            redemptionId,
            rd.actualUSDAmount,
            rd.usdAddress,
            rd.actualEtfAmount,
            rd.user,
            rd.actualPrice
        );
        delete $.redemptionDataMap[redemptionId];
    }

    // /*//////////////////////////////////////////////////////////////
    //                            offChain
    // //////////////////////////////////////////////////////////////*/

    function offChainSubscribe(
        uint128 usdAmount,
        uint128 orderEtfAmount,
        uint128 actualEtfAmount,
        address usdAddress,
        address user,
        uint96 actualPrice,
        uint80 actualTransactionFee,
        string calldata offChainId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        uint96 subscriptionId = ++$.nextId;

        $.subscribeDataMap[subscriptionId] = SubscribeData({
            usdAmount: usdAmount,
            usdAddress: usdAddress,
            actualEtfAmount: actualEtfAmount,
            orderEtfAmount: orderEtfAmount,
            user: user,
            actualPrice: actualPrice,
            actualUSDAmount: 0,
            actualRefundUSDAmount: 0,
            actualTransactionFee: actualTransactionFee,
            isSettled: false,
            isOnChain: false
        });

        emit SubscribeEvent(
            subscriptionId,
            usdAmount,
            usdAddress,
            actualEtfAmount,
            orderEtfAmount,
            user,
            actualPrice,
            actualTransactionFee,
            offChainId
        );
    }

    function revertOffChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        SubscribeData storage sd = $.subscribeDataMap[subscriptionId];
        if (sd.user == address(0)) revert SubscriptionDoesNotExist();
        if (sd.isSettled) revert SubscriptionAlreadySettled();

        emit RevertOffChainSubscribeEvent(
            subscriptionId,
            sd.usdAmount,
            sd.usdAddress,
            sd.actualEtfAmount,
            sd.orderEtfAmount,
            sd.user,
            sd.actualPrice,
            sd.actualTransactionFee
        );
        delete $.subscribeDataMap[subscriptionId];
    }

    function settleOffChainSubscribe(
        uint96 subscriptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();
        SubscribeData storage sd = $.subscribeDataMap[subscriptionId];

        if (sd.user == address(0)) revert SubscriptionDoesNotExist();
        if (sd.isSettled) revert SubscriptionAlreadySettled();

        sd.isSettled = true;
        emit SettleOffChainSubscribeEvent(
            subscriptionId,
            sd.actualEtfAmount,
            sd.actualPrice,
            sd.actualTransactionFee
        );
    }

    function distributeSubscribe(
        uint96 subscriptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();
        SubscribeData storage sd = $.subscribeDataMap[subscriptionId];

        if (sd.user == address(0)) revert SubscriptionDoesNotExist();

        if (!sd.isSettled) revert SubscriptionNotSettled();

        emit ClaimEvent(
            subscriptionId,
            sd.usdAmount,
            sd.usdAddress,
            sd.actualEtfAmount,
            sd.orderEtfAmount,
            sd.user,
            sd.actualPrice,
            sd.actualUSDAmount,
            sd.actualRefundUSDAmount,
            sd.actualTransactionFee,
            0
        );
        delete $.subscribeDataMap[subscriptionId];
    }

    function offChainRedemption(
        uint128 actualUSDAmount,
        address usdAddress,
        uint128 actualEtfAmount,
        address user,
        uint96 actualPrice,
        uint80 actualTransactionFee,
        string calldata offChainId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();
        uint96 redemptionId = ++$.nextId;

        $.redemptionDataMap[redemptionId] = RedemptionData({
            actualUSDAmount: actualUSDAmount,
            usdAddress: usdAddress,
            actualEtfAmount: actualEtfAmount,
            user: user,
            actualPrice: actualPrice,
            actualTransactionFee: actualTransactionFee,
            isSettled: false,
            isOnChain: false
        });
        emit RedemptionEvent(
            redemptionId,
            actualUSDAmount,
            usdAddress,
            actualEtfAmount,
            user,
            actualPrice,
            offChainId
        );
    }

    function revertOffChainRedemption(
        uint96 redemptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        RedemptionData storage rd = $.redemptionDataMap[redemptionId];

        if (rd.user == address(0)) revert RedemptionDoesNotExist();
        if (rd.isSettled) revert RedemptionAlreadySettled();

        emit RevertOffChainRedemptionEvent(
            redemptionId,
            rd.actualUSDAmount,
            rd.usdAddress,
            rd.actualEtfAmount,
            rd.user,
            rd.actualPrice
        );
        delete $.redemptionDataMap[redemptionId];
    }

    function settleOffChainRedemption(
        uint96 redemptionId
    ) external onlyRole(PERMISSIONED_ETF) {
        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();
        RedemptionData storage rd = $.redemptionDataMap[redemptionId];

        if (rd.user == address(0)) revert RedemptionDoesNotExist();
        if (rd.isSettled) revert RedemptionAlreadySettled();

        rd.isSettled = true;

        emit SettleOffChainRedemptionEvent(
            redemptionId,
            rd.actualUSDAmount,
            rd.usdAddress,
            rd.actualEtfAmount,
            rd.user,
            rd.actualPrice,
            rd.actualTransactionFee
        );
    }

    function burn(uint96 redemptionId) external {
        if (
            !hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) &&
            !hasRole(PERMISSIONED_ETF, _msgSender())
        )
            revert AccessControlUnauthorizedAccount(
                _msgSender(),
                DEFAULT_ADMIN_ROLE
            );

        PermissionedETFTradingStorage
            storage $ = _getPermissionedETFTradingStorage();

        RedemptionData storage rd = $.redemptionDataMap[redemptionId];

        if (rd.user == address(0)) revert RedemptionDoesNotExist();

        emit BurnEvent(
            redemptionId,
            rd.actualUSDAmount,
            rd.usdAddress,
            rd.actualEtfAmount,
            rd.user,
            rd.actualPrice
        );
        delete $.redemptionDataMap[redemptionId];
    }

    function getSubscriptionUser(
        uint96 subscriptionId
    ) external view onlyRole(PERMISSIONED_ETF) returns (address) {
        return
            _getPermissionedETFTradingStorage()
                .subscribeDataMap[subscriptionId]
                .user;
    }

    function getRedemptionUser(
        uint96 redemptionId
    ) external view onlyRole(PERMISSIONED_ETF) returns (address) {
        return
            _getPermissionedETFTradingStorage()
                .redemptionDataMap[redemptionId]
                .user;
    }

    function getSubscribeData(
        uint96 subscriptionId
    ) external view onlyRole(PERMISSIONED_ETF) returns (SubscribeData memory) {
        SubscribeData memory sd = _getPermissionedETFTradingStorage()
            .subscribeDataMap[subscriptionId];
        if (sd.user == address(0)) revert SubscriptionDoesNotExist();
        return sd;
    }

    function getRedemptionData(
        uint96 redemptionId
    ) external view onlyRole(PERMISSIONED_ETF) returns (RedemptionData memory) {
        RedemptionData memory rd = _getPermissionedETFTradingStorage()
            .redemptionDataMap[redemptionId];
        if (rd.user == address(0)) revert RedemptionDoesNotExist();
        return rd;
    }

    /*//////////////////////////////////////////////////////////////
                                get and set
    //////////////////////////////////////////////////////////////*/

    // function getBoardLotSize()
    //     external
    //     view
    //     onlyRole(PERMISSIONED_ETF)
    //     returns (uint96)
    // {
    //     return _getPermissionedETFTradingStorage().boardLotSize;
    // }

    // function setBoardLotSize(
    //     uint96 newLotSize
    // ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    //     _getPermissionedETFTradingStorage().boardLotSize = newLotSize;
    // }

    function nonceOf(address user) external view returns (uint256) {
        return _getPermissionedETFTradingStorage().nonces[user];
    }

    function addOnRemoveAuthorizedSigner(
        address signer,
        bool isAdd
    ) external onlyRole(PERMISSIONED_ETF) {
        _getPermissionedETFTradingStorage().isAuthorizedSigner[signer] = isAdd;

        if (isAdd) emit AuthorizedSignerAdded(signer);
        else emit AuthorizedSignerRemoved(signer);
    }

    function getAuthorizedSigner(
        address signer
    ) external view onlyRole(PERMISSIONED_ETF) returns (bool) {
        return _getPermissionedETFTradingStorage().isAuthorizedSigner[signer];
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(PERMISSIONED_ETF) {}

    function getPETFToken() external view returns (address) {
        return getRoleMember(PERMISSIONED_ETF, 0);
    }
}
