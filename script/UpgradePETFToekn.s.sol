// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradePETFToken is Script {
    uint256 private PRIVATE_KEY;

    function run() external {
        PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

        address petfTokenProxy          = vm.envAddress("PETF_TOKEN_PROXY");
        address petfTradingProxy        = vm.envAddress("PETF_TRADING_PROXY");
        address petfRDProxy             = vm.envAddress("PETF_RD_PROXY");
        address petfFacadeProxy         = vm.envAddress("PETF_FACADE_PROXY");

        vm.createSelectFork("bsc-testnet");
        vm.startBroadcast(PRIVATE_KEY);

        // Upgrade PETFToken implementation
        Upgrades.upgradeProxy(
            petfTokenProxy,
            "PETFToken.sol:PETFToken",
            ""
        );
        console2.log("PETFToken upgraded. Proxy:", petfTokenProxy);

        // Upgrade PETFTrading implementation
        Upgrades.upgradeProxy(
            petfTradingProxy,
            "PETFTrading.sol:PETFTrading",
            ""
        );
        console2.log("PETFTrading upgraded. Proxy:", petfTradingProxy);

        // Upgrade PETFRewardDistributor implementation
        Upgrades.upgradeProxy(
            petfRDProxy,
            "PETFRewardDistributor.sol:PETFRewardDistributor",
            ""
        );
        console2.log("PETFRewardDistributor upgraded. Proxy:", petfRDProxy);

        // Upgrade PETFFacade implementation
        Upgrades.upgradeProxy(
            petfFacadeProxy,
            "PETFFacade.sol:PETFFacade",
            ""
        );
        console2.log("PETFFacade upgraded. Proxy:", petfFacadeProxy);

        vm.stopBroadcast();
    }
}
