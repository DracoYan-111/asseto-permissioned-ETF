// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PETFToken} from "../src/PETFToken.sol";
import {PETFTrading} from "../src/PETFTrading.sol";
import {PETFFacade} from "../src/PETFFacade.sol";
import {IPETFTrading} from "../src/interfaces/IPETFTrading.sol";
import {Blacklistable} from "../src/abstracts/Blacklistable.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract PETFTest is Test {
    // ======= Contracts =======
    PETFToken   token;
    PETFTrading trading;
    PETFFacade  facade;
    MockUSDC    usdc;

    // ======= Role constants =======
    bytes32 constant TRADE_ADMIN    = keccak256("TRADE_ADMIN");
    bytes32 constant CONTRACT_ADMIN = keccak256("CONTRACT_ADMIN");
    bytes32 constant FIX_ADMIN      = keccak256("FIX_ADMIN");
    bytes32 constant DIVIDEND_ADMIN = keccak256("DIVIDEND_ADMIN");
    bytes32 constant PETF_FACADE    = keccak256("PETF_FACADE");

    // ======= Actors =======
    address admin               = address(this);
    address tradeAdmin          = makeAddr("tradeAdmin");
    address assetRecipient      = makeAddr("assetRecipient");
    address serviceFeeRecipient = makeAddr("serviceFeeRecipient");
    address user                = makeAddr("user");
    address user2               = makeAddr("user2");
    address stranger            = makeAddr("stranger");

    // ======= Signer =======
    uint256 constant SIGNER_PRIV_KEY = 0xA11CE;
    address signer;

    // ======= EIP-712 type hashes =======
    bytes32 constant SUBSCRIBE_TYPEHASH = keccak256(
        "SubscribeOrder(address usdAddress,uint256 usdAmount,uint256 orderEtfAmount,address userAddress,uint256 nonce,uint256 deadline)"
    );
    bytes32 constant REDEEM_TYPEHASH = keccak256(
        "RedemptionOrder(address usdAddress,uint256 actualEtfAmount,address userAddress,uint256 nonce,uint256 deadline)"
    );

    // ======= Test parameters =======
    uint96  constant BOARD_LOT_SIZE   = 100e18;
    uint128 constant USD_AMOUNT       = 1_000e6;
    uint128 constant ORDER_ETF_AMOUNT = 100e18;

    uint96  constant ACTUAL_PRICE = 10e6;
    uint128 constant ACTUAL_ETF   = 100e18;
    uint128 constant ACTUAL_USD   = 900e6;
    uint128 constant REFUND_USD   = 100e6;
    uint80  constant TX_FEE       = 0;

    // ======= Setup =======

    function setUp() public {
        signer = vm.addr(SIGNER_PRIV_KEY);
        usdc = new MockUSDC();

        // Deploy implementations
        PETFToken   tokenImpl  = new PETFToken();
        PETFTrading tradingImpl = new PETFTrading();
        PETFFacade  facadeImpl = new PETFFacade();

        // Deploy proxies
        token = PETFToken(address(new ERC1967Proxy(
            address(tokenImpl),
            abi.encodeCall(PETFToken.initialize, ("Permissioned ETF", "PETF"))
        )));

        // PETFTrading.initialize() takes no arguments
        trading = PETFTrading(address(new ERC1967Proxy(
            address(tradingImpl),
            abi.encodeCall(PETFTrading.initialize, ())
        )));

        facade = PETFFacade(address(new ERC1967Proxy(
            address(facadeImpl),
            abi.encodeCall(PETFFacade.initialize, (
                address(token),
                address(trading),
                address(0),          // no RewardDistributor in these tests
                assetRecipient,
                serviceFeeRecipient,
                BOARD_LOT_SIZE
            ))
        )));

        // ---- Roles on PETFToken ----
        token.grantRole(TRADE_ADMIN,    address(facade)); // mintETF / burnETF
        token.grantRole(CONTRACT_ADMIN, admin);           // setBatchRestriction, pause/unpause
        token.grantRole(FIX_ADMIN,      admin);           // forceTransfer
        token.grantRole(DIVIDEND_ADMIN, admin);           // createNewSnapshot

        // ---- Roles on PETFTrading ----
        trading.grantRole(PETF_FACADE, address(facade)); // all trading functions

        // ---- Roles on PETFFacade ----
        facade.grantRole(CONTRACT_ADMIN, admin);      // pause/unpause, setBoardLotSize, setHasMinAmount
        facade.grantRole(TRADE_ADMIN,    tradeAdmin); // update / settle / revert operations

        // ---- Configure facade ----
        facade.setSupportedTokenAddress(IERC20(address(usdc)), true);
        facade.addOnRemoveAuthorizedSigner(signer, true);

        // Whitelist users
        _allow(user);
        _allow(user2);

        // Fund users
        usdc.mint(user,  10_000e6);
        usdc.mint(user2, 10_000e6);

        vm.prank(user);
        usdc.approve(address(facade), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(facade), type(uint256).max);

        // Fund assetRecipient for claimUSD flow
        usdc.mint(assetRecipient, 100_000e6);
        vm.prank(assetRecipient);
        usdc.approve(address(facade), type(uint256).max);
    }

    // ======= Helpers =======

    bytes32 constant TRADING_STORAGE_SLOT =
        0xc589f43e343d180cc9eda5dac9bea2364b1645f3a4448cc5dc35abc0d6eec400;

    function _currentNextId() internal view returns (uint96) {
        return uint96(uint256(vm.load(address(trading), TRADING_STORAGE_SLOT)));
    }

    function _allow(address account) internal {
        address[] memory arr = new address[](1);
        arr[0] = account;
        token.setBatchRestriction(arr, Blacklistable.Restriction.ALLOWED);
    }

    function _block(address account) internal {
        address[] memory arr = new address[](1);
        arr[0] = account;
        token.setBatchRestriction(arr, Blacklistable.Restriction.BLOCKED);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("ETFTrading"),
            keccak256("1"),
            block.chainid,
            address(trading)
        ));
    }

    function _signSubscribe(
        address usdAddress,
        uint128 usdAmount,
        uint128 orderEtfAmount,
        address userAddress,
        uint96  deadline
    ) internal view returns (bytes memory) {
        uint256 nonce = facade.nonceOf(userAddress);
        bytes32 structHash = keccak256(abi.encode(
            SUBSCRIBE_TYPEHASH,
            usdAddress,
            uint256(usdAmount),
            uint256(orderEtfAmount),
            userAddress,
            nonce,
            uint256(deadline)
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIV_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _signRedeem(
        address usdAddress,
        uint128 etfAmount,
        address userAddress,
        uint128 deadline
    ) internal view returns (bytes memory) {
        uint256 nonce = facade.nonceOf(userAddress);
        bytes32 structHash = keccak256(abi.encode(
            REDEEM_TYPEHASH,
            usdAddress,
            uint256(etfAmount),
            userAddress,
            nonce,
            uint256(deadline)
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIV_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function _doSubscribe() internal returns (uint96) {
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);
        vm.prank(user);
        facade.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
        return 1;
    }

    function _doSettleSubscribe(uint96 subscriptionId) internal {
        vm.startPrank(tradeAdmin);
        facade.updateOnChainSubscribe(subscriptionId, ACTUAL_PRICE, ACTUAL_ETF, ACTUAL_USD, REFUND_USD, TX_FEE, "off-id-1");
        facade.settleOnChainSubscribe(subscriptionId);
        vm.stopPrank();
    }

    function _doClaim(uint96 subscriptionId) internal {
        vm.prank(user);
        facade.claim(subscriptionId);
    }

    function _mintEtfToUser(address recipient, uint128 amount) internal {
        uint96 subId = _currentNextId() + 1;
        vm.startPrank(tradeAdmin);
        facade.offChainSubscribe(amount, amount, amount, address(usdc), recipient, ACTUAL_PRICE, TX_FEE, "mint-id");
        facade.settleOffChainSubscribe(subId);
        facade.distributeSubscribe(subId);
        vm.stopPrank();
    }

    // ======================================================
    //                  OnChain Subscribe
    // ======================================================

    function test_OnChainSubscribe_HappyPath() public {
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        uint256 userUsdBefore     = usdc.balanceOf(user);
        uint256 contractUsdBefore = usdc.balanceOf(address(facade));

        vm.prank(user);
        facade.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);

        assertEq(usdc.balanceOf(user),            userUsdBefore - USD_AMOUNT);
        assertEq(usdc.balanceOf(address(facade)), contractUsdBefore + USD_AMOUNT);

        IPETFTrading.SubscribeData memory sd = facade.getSubscribeData(1);
        assertEq(sd.user,           user);
        assertEq(sd.usdAmount,      USD_AMOUNT);
        assertEq(sd.orderEtfAmount, ORDER_ETF_AMOUNT);
        assertEq(sd.usdAddress,     address(usdc));
        assertTrue(sd.isOnChain);
        assertFalse(sd.isSettled);
    }

    function test_OnChainSubscribe_NonceIncremented() public {
        assertEq(facade.nonceOf(user), 0);
        _doSubscribe();
        assertEq(facade.nonceOf(user), 1);
    }

    function test_OnChainSubscribe_RevertExpiredOrder() public {
        uint96 deadline = uint96(block.timestamp - 1);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("ExpiredOrder()"));
        facade.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
    }

    function test_OnChainSubscribe_RevertInvalidSignature() public {
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes32 digest = keccak256("garbage");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        facade.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), badSig);
    }

    function test_OnChainSubscribe_RevertNotWhitelisted() public {
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, stranger, deadline);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("NotAllowed(address)", stranger));
        facade.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
    }

    function test_OnChainSubscribe_RevertInvalidLotSize() public {
        uint128 badAmount = 150e18;
        uint96  deadline  = uint96(block.timestamp + 1 hours);
        bytes memory sig  = _signSubscribe(address(usdc), USD_AMOUNT, badAmount, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidTransferAmount(uint256)", badAmount));
        facade.onChainSubscribe(USD_AMOUNT, badAmount, deadline, address(usdc), sig);
    }

    function test_OnChainSubscribe_RevertUnsupportedToken() public {
        address fakeToken = makeAddr("fakeToken");
        uint96  deadline  = uint96(block.timestamp + 1 hours);
        bytes memory sig  = _signSubscribe(fakeToken, USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("UnsupportedTokenAddress(address)", fakeToken));
        facade.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, fakeToken, sig);
    }

    // ======================================================
    //               Update OnChain Subscribe
    // ======================================================

    function test_UpdateOnChainSubscribe_HappyPath() public {
        uint96 subId = _doSubscribe();

        vm.prank(tradeAdmin);
        facade.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, ACTUAL_USD, REFUND_USD, TX_FEE, "off-1");

        IPETFTrading.SubscribeData memory sd = facade.getSubscribeData(subId);
        assertEq(sd.actualPrice,           ACTUAL_PRICE);
        assertEq(sd.actualEtfAmount,       ACTUAL_ETF);
        assertEq(sd.actualUSDAmount,       ACTUAL_USD);
        assertEq(sd.actualRefundUSDAmount, REFUND_USD);
    }

    function test_UpdateOnChainSubscribe_RevertActualUSDExceedsTotal() public {
        uint96  subId   = _doSubscribe();
        uint128 overUSD = USD_AMOUNT + 1;

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("InvalidTransferAmount(uint256)", uint256(overUSD)));
        facade.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, overUSD, 0, 0, "x");
    }

    function test_UpdateOnChainSubscribe_RevertZeroUSDAmount() public {
        uint96 subId = _doSubscribe();

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("InvalidTransferAmount(uint256)", uint256(0)));
        facade.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, 0, 0, 0, "x");
    }

    function test_UpdateOnChainSubscribe_RevertNotTradeAdmin() public {
        uint96 subId = _doSubscribe();

        vm.prank(stranger);
        vm.expectRevert();
        facade.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, ACTUAL_USD, REFUND_USD, TX_FEE, "x");
    }

    function test_UpdateOnChainSubscribe_RevertAlreadySettled() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionAlreadySettled()"));
        facade.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, ACTUAL_USD, REFUND_USD, TX_FEE, "x");
    }

    // ======================================================
    //               Settle OnChain Subscribe
    // ======================================================

    function test_SettleOnChainSubscribe_TransfersUSDToRecipients() public {
        uint96  subId     = _doSubscribe();
        uint80  fee       = 10e6;
        uint128 actualUSD = 890e6;
        uint128 refund    = 100e6;

        vm.prank(tradeAdmin);
        facade.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, actualUSD, refund, fee, "off-1");

        uint256 assetBefore = usdc.balanceOf(assetRecipient);
        uint256 feeBefore   = usdc.balanceOf(serviceFeeRecipient);

        vm.prank(tradeAdmin);
        facade.settleOnChainSubscribe(subId);

        assertEq(usdc.balanceOf(assetRecipient),      assetBefore + actualUSD);
        assertEq(usdc.balanceOf(serviceFeeRecipient), feeBefore + fee);
        assertTrue(facade.getSubscribeData(subId).isSettled);
    }

    function test_SettleOnChainSubscribe_RevertAlreadySettled() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionAlreadySettled()"));
        facade.settleOnChainSubscribe(subId);
    }

    // ======================================================
    //                      Claim
    // ======================================================

    function test_Claim_MintsETFAndRefundsUSD() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        uint256 etfBefore = token.balanceOf(user);
        uint256 usdBefore = usdc.balanceOf(user);

        vm.prank(user);
        facade.claim(subId);

        assertEq(token.balanceOf(user), etfBefore + ACTUAL_ETF);
        assertEq(usdc.balanceOf(user),  usdBefore + REFUND_USD);
    }

    function test_Claim_DeletesRecord() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(user);
        facade.claim(subId);

        vm.expectRevert(abi.encodeWithSignature("SubscriptionDoesNotExist()"));
        facade.getSubscribeData(subId);
    }

    function test_Claim_RevertNotOwner() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OnlyTheRedeemerCanClaim()"));
        facade.claim(subId);
    }

    function test_Claim_RevertNotSettled() public {
        uint96 subId = _doSubscribe();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionNotSettled()"));
        facade.claim(subId);
    }

    function test_Claim_RevertBlacklisted() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);
        _block(user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Blacklisted(address)", user));
        facade.claim(subId);
    }

    // ======================================================
    //             Revert OnChain Subscribe
    // ======================================================

    function test_RevertOnChainSubscribe_RefundsUser() public {
        uint96 subId = _doSubscribe();

        uint256 userUsdBefore     = usdc.balanceOf(user);
        uint256 contractUsdBefore = usdc.balanceOf(address(facade));

        vm.prank(tradeAdmin);
        facade.revertOnChainSubscribe(subId);

        assertEq(usdc.balanceOf(user),            userUsdBefore + USD_AMOUNT);
        assertEq(usdc.balanceOf(address(facade)), contractUsdBefore - USD_AMOUNT);
    }

    function test_RevertOnChainSubscribe_DeletesRecord() public {
        uint96 subId = _doSubscribe();

        vm.prank(tradeAdmin);
        facade.revertOnChainSubscribe(subId);

        vm.expectRevert(abi.encodeWithSignature("SubscriptionDoesNotExist()"));
        facade.getSubscribeData(subId);
    }

    function test_RevertOnChainSubscribe_RevertAfterSettled() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionAlreadySettled()"));
        facade.revertOnChainSubscribe(subId);
    }

    // ======================================================
    //                  OnChain Redemption
    // ======================================================

    function _doRedemption() internal returns (uint96 redemptionId) {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);
        _doClaim(subId);

        redemptionId = _currentNextId() + 1;

        uint128 deadline = uint128(block.timestamp + 1 hours);
        bytes memory sig = _signRedeem(address(usdc), ACTUAL_ETF, user, deadline);
        vm.prank(user);
        facade.onChainRedemption(address(usdc), ACTUAL_ETF, deadline, sig);
    }

    function test_OnChainRedemption_HappyPath() public {
        uint96 redemptionId = _doRedemption();

        IPETFTrading.RedemptionData memory rd = facade.getRedemptionData(redemptionId);
        assertEq(rd.user,            user);
        assertEq(rd.actualEtfAmount, ACTUAL_ETF);
        assertEq(rd.usdAddress,      address(usdc));
        assertTrue(rd.isOnChain);
        assertFalse(rd.isSettled);
    }

    function test_OnChainRedemption_RevertExpiredDeadline() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);
        _doClaim(subId);

        uint128 deadline = uint128(block.timestamp - 1);
        bytes memory sig = _signRedeem(address(usdc), ACTUAL_ETF, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("ExpiredOrder()"));
        facade.onChainRedemption(address(usdc), ACTUAL_ETF, deadline, sig);
    }

    function test_OnChainRedemption_RevertBlacklisted() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);
        _doClaim(subId);
        _block(user);

        uint128 deadline = uint128(block.timestamp + 1 hours);
        bytes memory sig = _signRedeem(address(usdc), ACTUAL_ETF, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Blacklisted(address)", user));
        facade.onChainRedemption(address(usdc), ACTUAL_ETF, deadline, sig);
    }

    // ======================================================
    //               Settle OnChain Redemption
    // ======================================================

    function test_SettleOnChainRedemption_BurnsETF() public {
        uint96 redemptionId = _doRedemption();

        vm.prank(tradeAdmin);
        facade.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);

        uint256 etfBefore    = token.balanceOf(user);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(tradeAdmin);
        facade.settleOnChainRedemption(redemptionId);

        assertEq(token.balanceOf(user), etfBefore - ACTUAL_ETF);
        assertEq(token.totalSupply(),   supplyBefore - ACTUAL_ETF);
        assertTrue(facade.getRedemptionData(redemptionId).isSettled);
    }

    function test_SettleOnChainRedemption_RevertAlreadySettled() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        facade.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        facade.settleOnChainRedemption(redemptionId);
        vm.expectRevert(abi.encodeWithSignature("RedemptionAlreadySettled()"));
        facade.settleOnChainRedemption(redemptionId);
        vm.stopPrank();
    }

    // ======================================================
    //                       ClaimUSD
    // ======================================================

    function test_ClaimUSD_TransfersUSDToUser() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        facade.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        facade.settleOnChainRedemption(redemptionId);
        vm.stopPrank();

        uint256 userUsdBefore = usdc.balanceOf(user);
        uint256 assetBefore   = usdc.balanceOf(assetRecipient);

        vm.prank(user);
        facade.claimUSD(redemptionId);

        assertEq(usdc.balanceOf(user),           userUsdBefore + ACTUAL_USD);
        assertEq(usdc.balanceOf(assetRecipient), assetBefore - ACTUAL_USD);
    }

    function test_ClaimUSD_DeletesRecord() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        facade.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        facade.settleOnChainRedemption(redemptionId);
        vm.stopPrank();

        vm.prank(user);
        facade.claimUSD(redemptionId);

        vm.expectRevert(abi.encodeWithSignature("RedemptionDoesNotExist()"));
        facade.getRedemptionData(redemptionId);
    }

    function test_ClaimUSD_RevertNotOwner() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        facade.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        facade.settleOnChainRedemption(redemptionId);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OnlyTheRedeemerCanClaim()"));
        facade.claimUSD(redemptionId);
    }

    function test_ClaimUSD_RevertNotSettled() public {
        uint96 redemptionId = _doRedemption();

        vm.prank(tradeAdmin);
        facade.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RedemptionNotSettled()"));
        facade.claimUSD(redemptionId);
    }

    // ======================================================
    //             Revert OnChain Redemption
    // ======================================================

    function test_RevertOnChainRedemption_DeletesRecord() public {
        uint96 redemptionId = _doRedemption();

        vm.prank(tradeAdmin);
        facade.revertOnChainRedemption(redemptionId);

        vm.expectRevert(abi.encodeWithSignature("RedemptionDoesNotExist()"));
        facade.getRedemptionData(redemptionId);
    }

    function test_RevertOnChainRedemption_RevertAfterSettled() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        facade.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        facade.settleOnChainRedemption(redemptionId);
        vm.expectRevert(abi.encodeWithSignature("RedemptionAlreadySettled()"));
        facade.revertOnChainRedemption(redemptionId);
        vm.stopPrank();
    }

    // ======================================================
    //                 OffChain Subscribe
    // ======================================================

    function test_OffChainSubscribe_CreatesRecord() public {
        vm.prank(tradeAdmin);
        facade.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        IPETFTrading.SubscribeData memory sd = facade.getSubscribeData(1);
        assertEq(sd.user,            user);
        assertEq(sd.usdAmount,       USD_AMOUNT);
        assertEq(sd.actualEtfAmount, ACTUAL_ETF);
        assertFalse(sd.isOnChain);
        assertFalse(sd.isSettled);
    }

    function test_SettleOffChainSubscribe_MarksSettled() public {
        vm.prank(tradeAdmin);
        facade.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        vm.prank(tradeAdmin);
        facade.settleOffChainSubscribe(1);

        assertTrue(facade.getSubscribeData(1).isSettled);
    }

    function test_DistributeSubscribe_MintsETF() public {
        vm.prank(tradeAdmin);
        facade.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");
        vm.prank(tradeAdmin);
        facade.settleOffChainSubscribe(1);

        uint256 etfBefore = token.balanceOf(user);

        vm.prank(tradeAdmin);
        facade.distributeSubscribe(1);

        assertEq(token.balanceOf(user), etfBefore + ACTUAL_ETF);
    }

    function test_DistributeSubscribe_DeletesRecord() public {
        vm.prank(tradeAdmin);
        facade.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");
        vm.prank(tradeAdmin);
        facade.settleOffChainSubscribe(1);
        vm.prank(tradeAdmin);
        facade.distributeSubscribe(1);

        vm.expectRevert(abi.encodeWithSignature("SubscriptionDoesNotExist()"));
        facade.getSubscribeData(1);
    }

    function test_DistributeSubscribe_RevertNotSettled() public {
        vm.prank(tradeAdmin);
        facade.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionNotSettled()"));
        facade.distributeSubscribe(1);
    }

    function test_RevertOffChainSubscribe_DeletesRecord() public {
        vm.prank(tradeAdmin);
        facade.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");
        vm.prank(tradeAdmin);
        facade.revertOffChainSubscribe(1);

        vm.expectRevert(abi.encodeWithSignature("SubscriptionDoesNotExist()"));
        facade.getSubscribeData(1);
    }

    function test_OffChainSubscribe_RevertBlockedUser() public {
        _block(user);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("Blacklisted(address)", user));
        facade.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");
    }

    // ======================================================
    //                 OffChain Redemption
    // ======================================================

    function test_OffChainRedemption_CreatesRecord() public {
        vm.prank(tradeAdmin);
        facade.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");

        IPETFTrading.RedemptionData memory rd = facade.getRedemptionData(1);
        assertEq(rd.user,            user);
        assertEq(rd.actualUSDAmount, ACTUAL_USD);
        assertEq(rd.actualEtfAmount, ACTUAL_ETF);
        assertFalse(rd.isOnChain);
        assertFalse(rd.isSettled);
    }

    function test_SettleOffChainRedemption_MarksSettled() public {
        vm.prank(tradeAdmin);
        facade.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");
        vm.prank(tradeAdmin);
        facade.settleOffChainRedemption(1);

        assertTrue(facade.getRedemptionData(1).isSettled);
    }

    function test_RevertOffChainRedemption_DeletesRecord() public {
        vm.prank(tradeAdmin);
        facade.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");
        vm.prank(tradeAdmin);
        facade.revertOffChainRedemption(1);

        vm.expectRevert(abi.encodeWithSignature("RedemptionDoesNotExist()"));
        facade.getRedemptionData(1);
    }

    function test_OffChainRedemption_RevertBlockedUser() public {
        _block(user);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("Blacklisted(address)", user));
        facade.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");
    }

    // ======================================================
    //                  Access Control
    // ======================================================

    function test_AccessControl_OffChainSubscribeRequiresTradeAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        facade.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "x");
    }

    function test_AccessControl_SetBoardLotSizeRequiresContractAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        facade.setBoardLotSize(200e18);
    }

    function test_AccessControl_PauseRequiresContractAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        facade.pause();
    }

    function test_AccessControl_AddSignerRequiresDefaultAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        facade.addOnRemoveAuthorizedSigner(stranger, true);
    }

    // ======================================================
    //                   Board Lot Size
    // ======================================================

    function test_BoardLotSize_SetAndGet() public {
        facade.setBoardLotSize(200e18);
        assertEq(facade.getBoardLotSize(), 200e18);
    }

    function test_BoardLotSize_DisableCheck() public {
        facade.setHasMinAmount(false);
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, 150e18, user, deadline);
        vm.prank(user);
        facade.onChainSubscribe(USD_AMOUNT, 150e18, deadline, address(usdc), sig);
    }

    // ======================================================
    //                       Pause
    // ======================================================

    function test_Pause_BlocksOnChainSubscribe() public {
        facade.pause();

        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        vm.prank(user);
        vm.expectRevert();
        facade.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
    }

    function test_Pause_BlocksClaim() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        facade.pause();

        vm.prank(user);
        vm.expectRevert();
        facade.claim(subId);
    }

    function test_Unpause_ResumesOperations() public {
        facade.pause();
        facade.unpause();

        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(user);
        facade.claim(subId);
        assertEq(token.balanceOf(user), ACTUAL_ETF);
    }

    // ======================================================
    //                    Snapshot
    // ======================================================

    function test_Snapshot_RecordsBalanceBeforeClaim() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        uint256 snapId = token.createNewSnapshot();
        assertEq(token.balanceOfAt(user, snapId), 0);

        vm.prank(user);
        facade.claim(subId);

        assertEq(token.balanceOf(user),           ACTUAL_ETF);
        assertEq(token.balanceOfAt(user, snapId), 0);
    }

    // ======================================================
    //              ForceTransfer (FIX_ADMIN)
    // ======================================================

    function test_ForceTransfer_MovesTokens() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);
        _doClaim(subId);

        assertEq(token.balanceOf(user), ACTUAL_ETF);

        token.forceTransfer(user, admin, ACTUAL_ETF);

        assertEq(token.balanceOf(user),  0);
        assertEq(token.balanceOf(admin), ACTUAL_ETF);
    }

    function test_ForceTransfer_RevertNotFixAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.forceTransfer(user, admin, ACTUAL_ETF);
    }

    // ======================================================
    //              Authorized Signer Management
    // ======================================================

    function test_AddRemoveAuthorizedSigner() public {
        address newSigner = makeAddr("newSigner");
        assertFalse(facade.getAuthorizedSigner(newSigner));

        facade.addOnRemoveAuthorizedSigner(newSigner, true);
        assertTrue(facade.getAuthorizedSigner(newSigner));

        facade.addOnRemoveAuthorizedSigner(newSigner, false);
        assertFalse(facade.getAuthorizedSigner(newSigner));
    }

    function test_RemovedSigner_InvalidatesSignatures() public {
        facade.addOnRemoveAuthorizedSigner(signer, false);

        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        facade.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
    }

    // ======================================================
    //                  Role Sanity Checks
    // ======================================================

    function test_Roles_FacadeHasPETF_FACACEOnTrading() public view {
        assertTrue(trading.hasRole(PETF_FACADE, address(facade)));
    }

    function test_Roles_FacadeHasTRADE_ADMINOnToken() public view {
        assertTrue(token.hasRole(TRADE_ADMIN, address(facade)));
    }
}
