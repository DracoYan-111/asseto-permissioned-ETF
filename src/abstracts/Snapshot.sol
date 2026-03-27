// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.6.0
pragma solidity ^0.8.27;

abstract contract Snapshot {
    struct Snapshots {
        uint256[] ids;
        uint256[] values;
    }

    // keccak256(abi.encode(uint256(keccak256("snapshot.storage.Snapshot")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant SnapshotStorageLocation =
        0xb93964ebb264439b65aca2fd688bf0618a01ef07a85a71748cf1c72c7ba94800;

    /// @custom:storage-location erc7201:snapshot.storage.Snapshot
    struct SnapshotStorage {
        uint256 currentSnapshotId;
        mapping(address => Snapshots) accountSnapshots;
        Snapshots totalSupplySnapshots;
    }

    function _getCurrentSnapshotId() internal view returns (uint256) {
        return _getSnapshotStorage().currentSnapshotId;
    }

    /* ========= Core Snapshot ========= */

    function _snapshot() internal returns (uint256) {
        return ++_getSnapshotStorage().currentSnapshotId;
    }

    function _writeSnapshot(
        Snapshots storage snapshots,
        uint256 currentValue
    ) private {
        SnapshotStorage storage $ = _getSnapshotStorage();
        uint256 len = snapshots.ids.length;
        if (len == 0 || snapshots.ids[len - 1] < $.currentSnapshotId) {
            snapshots.ids.push($.currentSnapshotId);
            snapshots.values.push(currentValue);
        }
    }

    /* ========= Hooks for Child Contract ========= */

    function _snapshotAccount(
        address account,
        uint256 currentBalance
    ) internal {
        _writeSnapshot(
            _getSnapshotStorage().accountSnapshots[account],
            currentBalance
        );
    }

    function _snapshotTotalSupply(uint256 currentTotalSupply) internal {
        _writeSnapshot(
            _getSnapshotStorage().totalSupplySnapshots,
            currentTotalSupply
        );
    }

    /* ========= View ========= */

    function balanceOfAt(
        address account,
        uint256 snapshotId
    ) public view returns (uint256) {
        return
            _valueAt(
                snapshotId,
                _getSnapshotStorage().accountSnapshots[account]
            );
    }

    function totalSupplyAt(uint256 snapshotId) public view returns (uint256) {
        return _valueAt(snapshotId, _getSnapshotStorage().totalSupplySnapshots);
    }

    function _valueAt(
        uint256 snapshotId,
        Snapshots storage snapshots
    ) private view returns (uint256) {
        uint256 len = snapshots.ids.length;
        if (len == 0) return 0;

        for (uint256 i = len; i > 0; ) {
            if (snapshots.ids[i - 1] <= snapshotId) {
                return snapshots.values[i - 1];
            }
            unchecked {
                --i;
            }
        }
        return 0;
    }

    function _getSnapshotStorage()
        private
        pure
        returns (SnapshotStorage storage $)
    {
        assembly {
            $.slot := SnapshotStorageLocation
        }
    }
}
