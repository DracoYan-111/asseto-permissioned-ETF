// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPETFTrading} from "../../interfaces/IPETFTrading.sol";
import {IPETFRD} from "../../interfaces/IPETFRD.sol";

abstract contract PETFTokenStory {
    /// ======= Error =======
    error InvalidSubscriptionQuantity(uint256 subscriptionQuantity);
    error NotWhitelistedOrZeroAddress(address userAddress);
    error UnsupportedTokenAddress(IERC20 tokenAddress);
    error InvalidTransferAmount(uint256 amount);
    error InsufficientUAmountToSettle();
    error SubscriptionAlreadySettled();
    error RedemptionAlreadySettled();
    error SubscriptionDoesNotExist();
    error OnlyTheRedeemerCanClaim();

    error RedemptionDoesNotExist();
    error PeerTransferNotAllowed();
    error SubscriptionNotSettled();
    error RedemptionNotSettled();
    error UserBurnNotAllowed();
    error ExpiredOrder();
    /// ======= Event =======
    event TransferWithIdEvent(
        address indexed from,
        address indexed to,
        uint256 value
    );
    /// ======= Constants =======
    // keccak256(abi.encode(uint256(keccak256("permissionedETF.storage.PermissionedETF")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PermissionedETFStorageLocation =
        0x58f2a9a4d8a2aaf4e9defa82241851a3604415fdf0458e6b9bf75adaeab90300;

    /// ======= Storage =======
    /// @custom:storage-location erc7201:permissionedETF.storage.PermissionedETF
    struct PermissionedEtfStorage {
        bool hasMinAmount;
        uint96 boardLotSize;
        IPETFTrading petfTrading;
        IPETFRD petfRewardDistributor;
        address assetRecipient;
        address serviceFeeRecipient;
        mapping(IERC20 => bool) supportedTokenAddress;
    }

    /// ======= Enum =======

    /// ======= Constructor =======

    /// ======= Modifiers =======

    /// ======= External Functions =======

    /// ======= Internal Functions =======

    /**
     * @dev Returns the storage of the PermissionedETF contract.
     */
    function _getPermissionedEtfStorage()
        internal
        pure
        virtual
        returns (PermissionedEtfStorage storage $)
    {
        assembly {
            $.slot := PermissionedETFStorageLocation
        }
    }
}
