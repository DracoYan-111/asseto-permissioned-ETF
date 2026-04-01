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

    // Role constants (mirror Roles.sol / PETFTradingStory / PETFRDStory)
    bytes32 constant TRADE_ADMIN = keccak256("TRADE_ADMIN");
    bytes32 constant PETF_FACADE = keccak256("PETF_FACADE");

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

        // 2. Deploy PETFTrading proxy (no constructor args)
        address petfTradingProxy = Upgrades.deployUUPSProxy(
            "PETFTrading.sol:PETFTrading",
            abi.encodeCall(PETFTrading.initialize, ())
        );
        console2.log("PETFTrading deployed at:", petfTradingProxy);

        // 3. Deploy PETFRewardDistributor proxy (no constructor args)
        address petfRDProxy = Upgrades.deployUUPSProxy(
            "PETFRewardDistributor.sol:PETFRewardDistributor",
            abi.encodeCall(PETFRewardDistributor.initialize, ())
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

        // 5. Grant TRADE_ADMIN on PETFToken to PETFFacade
        //    so the Facade can call mintETF / burnETF.
        IAccessControl(petfTokenProxy).grantRole(TRADE_ADMIN, petfFacadeProxy);

        // 6. Grant PETF_FACADE on PETFTrading to PETFFacade
        //    so the Facade can call all trading functions.
        IAccessControl(petfTradingProxy).grantRole(PETF_FACADE, petfFacadeProxy);

        // 7. Grant PETF_FACADE on PETFRewardDistributor to PETFFacade
        IAccessControl(petfRDProxy).grantRole(PETF_FACADE, petfFacadeProxy);

        vm.stopBroadcast();
    }
}
