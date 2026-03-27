// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IPETFTrading {
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

    function onChainSubscribe(
        uint128 usdAmount,
        uint128 orderEtfAmount,
        address user,
        uint96 deadline,
        address usdAddress,
        bytes calldata signature
    ) external;

    function updateOnChainSubscribe(
        uint96 subscriptionId,
        uint96 actualPrice,
        uint128 actualEtfAmount,
        uint128 actualUSDAmount,
        uint128 actualRefundUSDAmount,
        uint80 actualTransactionFee,
        string calldata offChainId
    ) external;

    function revertOnChainSubscribe(uint96 subscriptionId) external;

    function settleOnChainSubscribe(uint96 subscriptionId) external;

    function claim(uint96 subscriptionId) external;

    function onChainRedemption(
        address usdAddress,
        uint128 actualEtfAmount,
        uint128 deadline,
        address user,
        bytes calldata signature
    ) external;

    function updateOnChainRedemption(
        uint96 redemptionId,
        uint128 actualUSDAmount,
        uint96 actualPrice,
        uint80 actualTransactionFee
    ) external;

    function revertOnChainRedemption(uint96 redemptionId) external;

    function settleOnChainRedemption(uint96 redemptionId) external;

    function claimUSD(uint96 redemptionId) external;

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
    ) external;

    function revertOffChainSubscribe(uint96 subscriptionId) external;

    function settleOffChainSubscribe(uint96 subscriptionId) external;

    function distributeSubscribe(uint96 subscriptionId) external;

    function offChainRedemption(
        uint128 actualUSDAmount,
        address usdAddress,
        uint128 actualEtfAmount,
        address user,
        uint96 actualPrice,
        uint80 actualTransactionFee,
        string calldata offChainId
    ) external;

    function revertOffChainRedemption(uint96 redemptionId) external;

    function settleOffChainRedemption(uint96 redemptionId) external;

    function burn(uint96 redemptionId) external;

    function getSubscriptionUser(
        uint96 subscriptionId
    ) external view returns (address);

    function getRedemptionUser(
        uint96 redemptionId
    ) external view returns (address);

    function getSubscribeData(
        uint96 subscriptionId
    ) external view returns (SubscribeData memory);

    function getRedemptionData(
        uint96 redemptionId
    ) external view returns (RedemptionData memory);

    function nonceOf(address user) external view returns (uint256);

    function addOnRemoveAuthorizedSigner(address signer, bool isAdd) external;

    function getAuthorizedSigner(address signer) external view returns (bool);

    function upgradeToAndCall(
        address newImplementation,
        bytes memory data
    ) external payable;
}
