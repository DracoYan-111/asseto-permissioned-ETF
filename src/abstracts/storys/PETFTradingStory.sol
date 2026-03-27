// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

abstract contract PETFTradingStory {
    /// ======= Error =======
    error InvalidSignature();
    error RedemptionNotSettled();
    error SubscriptionNotSettled();
    error RedemptionDoesNotExist();
    error SubscriptionDoesNotExist();
    error RedemptionAlreadySettled();
    error SubscriptionAlreadySettled();
    error InvalidTransferAmount(uint256 amount);

    /// ======= Event =======

    event SubscribeEvent(
        uint256 subscriptionId,
        uint256 usdAmount, //stablecoin amount
        address usdAddress, //stablecoin address
        uint256 actualEtfAmount, //ETF token amount
        uint256 orderEtfAmount, //number of lots
        address user, //user address
        uint256 actualPrice, //subscription price
        uint256 actualTransactionFee, //Service fee
        string offChainId
    );
    event OnChainSubscribeEvent(
        uint256 subscriptionId,
        uint256 actualUSDAmount,
        address usdAddress,
        address user,
        uint256 orderEtfAmount,
        bytes32 digest
    );

    event SettleOffChainSubscribeEvent(
        uint256 subscriptionId,
        uint256 actualEtfAmount,
        uint256 actualPrice,
        uint256 actualTransactionFee
    );

    event UpdateOnChainSubscribeEvent(
        uint256 subscriptionId,
        uint256 actualEtfAmount,
        uint256 actualPrice,
        uint256 actualUSDAmount,
        uint256 actualRefundUSDAmount,
        uint256 actualTransactionFee,
        string offChainId
    );

    event RevertOnChainSubscribeEvent(
        uint256 subscriptionId,
        uint256 usdAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        uint256 orderEtfAmount,
        address user,
        uint256 actualPrice,
        uint256 actualUSDAmount,
        uint256 actualRefundUSDAmount,
        uint256 actualTransactionFee
    );

    event RevertOffChainSubscribeEvent(
        uint256 subscriptionId,
        uint256 usdAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        uint256 orderEtfAmount,
        address user,
        uint256 actualPrice,
        uint256 actualTransactionFee
    );

    event SettleOnChainRedemptionEvent(
        uint256 redemptionId,
        uint256 usdAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        address user,
        uint256 actualPrice,
        uint256 actualTransactionFee
    );

    event SettleOnChainSubscribeEvent(
        uint256 subscriptionId,
        uint256 actualEtfAmount,
        uint256 actualPrice,
        uint256 actualUSDAmount,
        uint256 actualRefundUSDAmount,
        uint256 actualTransactionFee
    );
    event SettleOffChainRedemptionEvent(
        uint256 redemptionId,
        uint256 usdAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        address user,
        uint256 actualPrice,
        uint256 actualTransactionFee
    );

    event ClaimEvent(
        uint256 subscriptionId,
        uint256 usdAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        uint256 orderEtfAmount,
        address user,
        uint256 actualPrice,
        uint256 actualUSDAmount,
        uint256 actualRefundUSDAmount,
        uint256 actualTransactionFee,
        uint256 tokenId
    );

    event OnChainRedemptionEvent(
        uint256 redemptionId,
        address usdAddress,
        uint256 orderEtfAmount,
        address user,
        bytes32 digest
    );

    event UpdateOnChainRedemptionEvent(
        uint256 redemptionId,
        uint256 actualUSDAmount,
        uint256 actualPrice,
        uint256 actualTransactionFee
    );

    event RevertOnChainRedemptionEvent(
        uint256 redemptionId,
        uint256 usdAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        address user,
        uint256 actualPrice,
        uint256 actualTransactionFee
    );

    event ClaimUSDEvent(
        uint256 redemptionId,
        uint256 actualUSDAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        address user,
        uint256 actualPrice
    );

    event RevertOffChainRedemptionEvent(
        uint256 redemptionId,
        uint256 usdAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        address user,
        uint256 actualPrice
    );

    event RedemptionEvent(
        uint256 redemptionId,
        uint256 usdAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        address user,
        uint256 actualPrice,
        string offChainId
    );

    event BurnEvent(
        uint256 redemptionId,
        uint256 actualUSDAmount,
        address usdAddress,
        uint256 actualEtfAmount,
        address user,
        uint256 actualPrice
    );

    event AuthorizedSignerAdded(address indexed signer);
    event AuthorizedSignerRemoved(address indexed signer);

    /// ======= Struct =======
    struct SubscribeData {
        uint128 usdAmount;
        uint128 orderEtfAmount;
        uint128 actualEtfAmount;
        uint128 actualUSDAmount;
        address user;
        uint96 actualPrice;
        address usdAddress;
        uint80 actualTransactionFee;
        bool isSettled;
        bool isOnChain;
        uint128 actualRefundUSDAmount;
    }

    struct RedemptionData {
        uint128 actualUSDAmount;
        uint128 actualEtfAmount;
        address user;
        uint96 actualPrice;
        address usdAddress;
        uint80 actualTransactionFee;
        bool isSettled;
        bool isOnChain;
    }

    /// ======= Constants =======

    bytes32 public constant PERMISSIONED_ETF = keccak256("PERMISSIONED_ETF");

    // keccak256(abi.encode(uint256(keccak256("PermissionedETFTrading.storage.PermissionedETFTrading")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PermissionedETFTradingStorageLocation =
        0xc589f43e343d180cc9eda5dac9bea2364b1645f3a4448cc5dc35abc0d6eec400;

    bytes32 public constant SUBSCRIBE_ORDER_TYPEHASH =
        keccak256(
            "SubscribeOrder(address usdAddress,uint256 usdAmount,uint256 orderEtfAmount,address userAddress,uint256 nonce,uint256 deadline)"
        );

    bytes32 public constant REDEEM_ORDER_TYPEHASH =
        keccak256(
            "RedemptionOrder(address usdAddress,uint256 actualEtfAmount,address userAddress,uint256 nonce,uint256 deadline)"
        );

    /// ======= Storage =======
    /// @custom:storage-location erc7201:permissionedETF.storage.PermissionedETFTrading
    struct PermissionedETFTradingStorage {
        uint96 nextId;
        mapping(address => uint256) nonces;
        mapping(address => bool) isAuthorizedSigner;
        mapping(uint96 => SubscribeData) subscribeDataMap;
        mapping(uint96 => RedemptionData) redemptionDataMap;
    }

    function _getPermissionedETFTradingStorage()
        internal
        pure
        virtual
        returns (PermissionedETFTradingStorage storage $)
    {
        assembly {
            $.slot := PermissionedETFTradingStorageLocation
        }
    }
}
