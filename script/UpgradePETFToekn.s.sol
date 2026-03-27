// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.27;

// import "forge-std/Script.sol";
// import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
// import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

// import {PETFToken} from "../src/PETFToken.sol";
// import {PETFTrading} from "../src/PETFTrading.sol";
// import {PETFRewardDistributor} from "../src/PETFRewardDistributor.sol";

// contract UpgradePETFToken is Script {
//     uint256 private PRIVATE_KEY;

//     PETFToken petfToken;
//     PETFTrading petfTrading;
//     PETFRewardDistributor petfRewardDistributor;

//     function run() external {
//         PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

//         vm.createSelectFork("bsc-testnet");
//         vm.startBroadcast(PRIVATE_KEY);

//         Options memory opts;
//         opts.referenceBuildInfoDir = "/old-builds/build-info-v1";
//         opts.referenceContract = "build-info-v1:MyContract";
//         Upgrades.upgradeProxy(proxy, "MyContract.sol", "", opts);

//     }
// }
