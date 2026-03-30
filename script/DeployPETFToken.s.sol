// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {PETFToken} from "../src/PETFToken.sol";
import {PETFTrading} from "../src/PETFTrading.sol";
import {PETFRewardDistributor} from "../src/PETFRewardDistributor.sol";
import {PETFFacade} from "../src/PETFFacade.sol";

contract DeployPETFToken is Script {
    uint256 private PRIVATE_KEY;

    // Role constants (mirror Roles.sol)
    bytes32 constant ETF_ADMIN    = keccak256("ETF_ADMIN");
    bytes32 constant PERMISSIONED_ETF = keccak256("PERMISSIONED_ETF");

    function run() external {
        PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

        vm.createSelectFork("bsc-testnet");
        vm.startBroadcast(PRIVATE_KEY);

        // 1. Deploy PETFToken proxy
        address petfTokenProxy = Upgrades.deployUUPSProxy(
            "PETFToken.sol:PETFToken",
            abi.encodeCall(
                PETFToken.initialize,
                ("Permissioned ETF", "PETF")
            )
        );
        console2.log("PETFToken deployed at:", petfTokenProxy);

        // 2. Deploy PETFTrading proxy (grants PERMISSIONED_ETF to petfTokenProxy for now;
        //    we will also grant it to PETFFacade below)
        address petfTradingProxy = Upgrades.deployUUPSProxy(
            "PETFTrading.sol:PETFTrading",
            abi.encodeCall(PETFTrading.initialize, (petfTokenProxy))
        );
        console2.log("PETFTrading deployed at:", petfTradingProxy);

        // 3. Deploy PETFRewardDistributor proxy
        address petfRDProxy = Upgrades.deployUUPSProxy(
            "PETFRewardDistributor.sol:PETFRewardDistributor",
            abi.encodeCall(
                PETFRewardDistributor.initialize,
                (petfTokenProxy)
            )
        );
        console2.log("PETFRewardDistributor deployed at:", petfRDProxy);

        // 4. Deploy PETFFacade proxy
        address deployer = vm.addr(PRIVATE_KEY);
        address petfFacadeProxy = Upgrades.deployUUPSProxy(
            "PETFFacade.sol:PETFFacade",
            abi.encodeCall(
                PETFFacade.initialize,
                (
                    petfTokenProxy,
                    petfTradingProxy,
                    petfRDProxy,
                    deployer,   // assetRecipient — update after deploy
                    deployer,   // serviceFeeRecipient — update after deploy
                    5 ether     // boardLotSize
                )
            )
        );
        console2.log("PETFFacade deployed at:", petfFacadeProxy);

        // 5. Grant ETF_ADMIN on PETFToken to PETFFacade
        //    so the Facade can call mintETF / burnETF.
        IAccessControl(petfTokenProxy).grantRole(ETF_ADMIN, petfFacadeProxy);

        // 6. Grant PERMISSIONED_ETF on PETFTrading to PETFFacade
        //    so the Facade can call all trading functions.
        IAccessControl(petfTradingProxy).grantRole(PERMISSIONED_ETF, petfFacadeProxy);

        // 7. Grant PERMISSIONED_ETF on PETFRewardDistributor to PETFFacade
        IAccessControl(petfRDProxy).grantRole(PERMISSIONED_ETF, petfFacadeProxy);

        // 8. Revoke PERMISSIONED_ETF from PETFToken on PETFTrading and PETFRewardDistributor.
        //    PETFToken was granted this role during initialization but only PETFFacade
        //    should be able to call trading / reward-distributor functions.
        IAccessControl(petfTradingProxy).revokeRole(PERMISSIONED_ETF, petfTokenProxy);
        IAccessControl(petfRDProxy).revokeRole(PERMISSIONED_ETF, petfTokenProxy);

        vm.stopBroadcast();
    }
}
