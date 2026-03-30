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
    // keccak256(abi.encode(uint256(keccak256("permissionedETF.storage.PETFFacade")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PETFFacadeStorageLocation =
        0x1cc621a296b912e0c4f817276810fcd70d33e6192fe935616c28ac0a0175e400;
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
     */
    function _getFacadeStorage()
        internal
        pure
        virtual
        returns (PETFFacadeStorage storage $)
    {
        assembly {
            $.slot := PETFFacadeStorageLocation
        }
    }
}
