// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {PETFToken} from "../src/PETFToken.sol";
import {PETFTrading} from "../src/PETFTrading.sol";
import {PETFRewardDistributor} from "../src/PETFRewardDistributor.sol";

contract DeployPETFToken is Script {
    uint256 private PRIVATE_KEY;

    PETFToken petfToken;
    PETFTrading petfTrading;
    PETFRewardDistributor petfRewardDistributor;

    function run() external {
        PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

        vm.createSelectFork("bsc-testnet");
        vm.startBroadcast(PRIVATE_KEY);

        address petfTokenProxy = Upgrades.deployUUPSProxy(
            "PETFToken.sol:PETFToken",
            abi.encodeCall(
                PETFToken.initialize,
                ("Permissioned ETF", "PETF", 5 ether)
            )
        );

        petfToken = PETFToken(petfTokenProxy);
        console2.log("PETFToken deployed at:", address(petfToken));

        address petfTradingProxy = Upgrades.deployUUPSProxy(
            "PETFTrading.sol:PETFTrading",
            abi.encodeCall(PETFTrading.initialize, (address(petfToken)))
        );

        petfTrading = PETFTrading(petfTradingProxy);
        console2.log("PETFTrading deployed at:", address(petfTrading));

        address petfRewardDistributorProxy = Upgrades.deployUUPSProxy(
            "PETFRewardDistributor.sol:PETFRewardDistributor",
            abi.encodeCall(
                PETFRewardDistributor.initialize,
                (address(petfToken))
            )
        );

        petfRewardDistributor = PETFRewardDistributor(
            petfRewardDistributorProxy
        );
        console2.log(
            "PETFRewardDistributor deployed at:",
            address(petfRewardDistributor)
        );

        vm.stopBroadcast();
    }
}
