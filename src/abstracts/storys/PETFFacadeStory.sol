// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPETFTrading} from "../../interfaces/IPETFTrading.sol";
import {IPETFRD} from "../../interfaces/IPETFRD.sol";
import {IPermissionedETF} from "../../interfaces/PETFToken.sol";

abstract contract PETFFacadeStory {
    /// ======= Error =======
    error UnsupportedTokenAddress(IERC20 tokenAddress);
    error InvalidTransferAmount(uint256 amount);
    error OnlyTheRedeemerCanClaim();
    error SubscriptionNotSettled();
    error RedemptionNotSettled();
    error ExpiredOrder();
    error NotAllowed(address account);
    error Blacklisted(address account);

    /// ======= Event =======
    event TransferWithIdEvent(
        address indexed from,
        address indexed to,
        uint256 value
    );

    /// ======= Storage =======
    /// @custom:storage-location erc7201:permissionedETF.storage.PETFFacade
    struct PETFFacadeStorage {
        IPermissionedETF petfToken;
        IPETFTrading petfTrading;
        IPETFRD petfRewardDistributor;
        address assetRecipient;
        address serviceFeeRecipient;
        mapping(IERC20 => bool) supportedTokenAddress;
        bool hasMinAmount;
        uint96 boardLotSize;
    }

    /**
     * @dev Returns the storage of the PETFFacade contract.
     *      Slot = keccak256("permissionedETF.storage.PETFFacade") & ~bytes32(uint256(0xff))
     */
    function _getFacadeStorage()
        internal
        pure
        virtual
        returns (PETFFacadeStorage storage $)
    {
        // Computed at call-time to avoid the assembly restriction on non-literal constants.
        bytes32 slot = keccak256("permissionedETF.storage.PETFFacade") & ~bytes32(uint256(0xff));
        assembly {
            $.slot := slot
        }
    }
}
