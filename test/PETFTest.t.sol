// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PETFToken} from "../src/PETFToken.sol";
import {PETFTrading} from "../src/PETFTrading.sol";
import {IPETFTrading} from "../src/interfaces/IPETFTrading.sol";
import {Blacklistable} from "../src/abstracts/Blacklistable.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract PETFTest is Test {
    // ======= Contracts =======
    PETFToken token;
    PETFTrading trading;
    MockUSDC usdc;

    // ======= Role constants =======
    bytes32 constant ETF_ADMIN = keccak256("ETF_ADMIN");
    bytes32 constant TRADE_ADMIN = keccak256("TRADE_ADMIN");
    bytes32 constant SNAPSHOT_ADMIN = keccak256("SNAPSHOT_ADMIN");
    bytes32 constant PERMISSIONED_ETF = keccak256("PERMISSIONED_ETF");

    // ======= Actors =======
    address admin = address(this);
    address tradeAdmin = makeAddr("tradeAdmin");
    address assetRecipient = makeAddr("assetRecipient");
    address serviceFeeRecipient = makeAddr("serviceFeeRecipient");
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address stranger = makeAddr("stranger");

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
    uint96 constant BOARD_LOT_SIZE = 100e18;
    uint128 constant USD_AMOUNT = 1_000e6;      // 1000 USDC
    uint128 constant ORDER_ETF_AMOUNT = 100e18; // 1 lot

    // Typical settle params
    uint96 constant ACTUAL_PRICE = 10e6;        // 10 USDC per ETF
    uint128 constant ACTUAL_ETF = 100e18;
    uint128 constant ACTUAL_USD = 900e6;
    uint128 constant REFUND_USD = 100e6;
    uint80 constant TX_FEE = 0;

    // ======= Setup =======

    function setUp() public {
        signer = vm.addr(SIGNER_PRIV_KEY);

        usdc = new MockUSDC();

        // Deploy implementations
        PETFToken tokenImpl = new PETFToken();
        PETFTrading tradingImpl = new PETFTrading();

        // Deploy proxies
        token = PETFToken(
            address(
                new ERC1967Proxy(
                    address(tokenImpl),
                    abi.encodeCall(PETFToken.initialize, ("Permissioned ETF", "PETF", BOARD_LOT_SIZE))
                )
            )
        );
        trading = PETFTrading(
            address(
                new ERC1967Proxy(
                    address(tradingImpl),
                    abi.encodeCall(PETFTrading.initialize, (address(token)))
                )
            )
        );

        // Grant roles first (some setup calls below require them)
        token.grantRole(TRADE_ADMIN, tradeAdmin);
        token.grantRole(ETF_ADMIN, admin);
        token.grantRole(SNAPSHOT_ADMIN, admin);

        // Wire up contracts
        token.setPetfTrading(address(trading));
        token.setSupportedTokenAddress(IERC20(address(usdc)), true); // requires ETF_ADMIN
        token.setAssetRecipient(assetRecipient);
        token.setServiceFeeRecipient(serviceFeeRecipient);

        // Add authorized signer
        token.addOnRemoveAuthorizedSigner(signer, true);

        // Whitelist users for on-chain subscribe
        _allow(user);
        _allow(user2);

        // Fund users
        usdc.mint(user, 10_000e6);
        usdc.mint(user2, 10_000e6);

        vm.prank(user);
        usdc.approve(address(token), type(uint256).max);
        vm.prank(user2);
        usdc.approve(address(token), type(uint256).max);

        // Give assetRecipient USDC and approval for claimUSD flow
        usdc.mint(assetRecipient, 100_000e6);
        vm.prank(assetRecipient);
        usdc.approve(address(token), type(uint256).max);
    }

    // ======= Helpers =======

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
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("ETFTrading"),
                keccak256("1"),
                block.chainid,
                address(trading)
            )
        );
    }

    function _signSubscribe(
        address usdAddress,
        uint128 usdAmount,
        uint128 orderEtfAmount,
        address userAddress,
        uint96 deadline
    ) internal view returns (bytes memory) {
        uint256 nonce = token.nonceOf(userAddress);
        bytes32 structHash = keccak256(
            abi.encode(SUBSCRIBE_TYPEHASH, usdAddress, uint256(usdAmount), uint256(orderEtfAmount), userAddress, nonce, uint256(deadline))
        );
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
        uint256 nonce = token.nonceOf(userAddress);
        bytes32 structHash = keccak256(
            abi.encode(REDEEM_TYPEHASH, usdAddress, uint256(etfAmount), userAddress, nonce, uint256(deadline))
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIV_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Returns subscriptionId=1 after a full onChainSubscribe
    function _doSubscribe() internal returns (uint96) {
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);
        vm.prank(user);
        token.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
        return 1;
    }

    /// @dev Full settle flow for subscriptionId, returns the settled subscriptionId
    function _doSettleSubscribe(uint96 subscriptionId) internal {
        vm.startPrank(tradeAdmin);
        token.updateOnChainSubscribe(subscriptionId, ACTUAL_PRICE, ACTUAL_ETF, ACTUAL_USD, REFUND_USD, TX_FEE, "off-id-1");
        token.settleOnChainSubscribe(subscriptionId);
        vm.stopPrank();
    }

    /// @dev Full claim flow — user claims ETF after settlement
    function _doClaim(uint96 subscriptionId) internal {
        vm.prank(user);
        token.claim(subscriptionId);
    }

    /// @dev Give user ETF via off-chain subscribe flow
    function _mintEtfToUser(address recipient, uint128 amount) internal {
        address[] memory arr = new address[](1);
        arr[0] = recipient;
        // make sure recipient is not blocked (DEFAULT ok for offchain)
        vm.startPrank(tradeAdmin);
        token.offChainSubscribe(amount, amount, amount, address(usdc), recipient, ACTUAL_PRICE, TX_FEE, "mint-id");
        token.settleOffChainSubscribe(1);
        token.distributeSubscribe(1);
        vm.stopPrank();
    }

    // ======================================================
    //                  OnChain Subscribe
    // ======================================================

    function test_OnChainSubscribe_HappyPath() public {
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        uint256 userUsdBefore = usdc.balanceOf(user);
        uint256 contractUsdBefore = usdc.balanceOf(address(token));

        vm.prank(user);
        token.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);

        assertEq(usdc.balanceOf(user), userUsdBefore - USD_AMOUNT, "user USD not debited");
        assertEq(usdc.balanceOf(address(token)), contractUsdBefore + USD_AMOUNT, "contract USD not credited");

        IPETFTrading.SubscribeData memory sd = token.getSubscribeData(1);
        assertEq(sd.user, user);
        assertEq(sd.usdAmount, USD_AMOUNT);
        assertEq(sd.orderEtfAmount, ORDER_ETF_AMOUNT);
        assertEq(sd.usdAddress, address(usdc));
        assertTrue(sd.isOnChain);
        assertFalse(sd.isSettled);
    }

    function test_OnChainSubscribe_NonceIncremented() public {
        assertEq(token.nonceOf(user), 0);
        _doSubscribe();
        assertEq(token.nonceOf(user), 1);
    }

    function test_OnChainSubscribe_RevertExpiredOrder() public {
        uint96 deadline = uint96(block.timestamp - 1);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("ExpiredOrder()"));
        token.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
    }

    function test_OnChainSubscribe_RevertInvalidSignature() public {
        uint96 deadline = uint96(block.timestamp + 1 hours);
        // sign with wrong key
        bytes32 digest = keccak256("garbage");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBAD, digest);
        bytes memory badSig = abi.encodePacked(r, s, v);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        token.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), badSig);
    }

    function test_OnChainSubscribe_RevertNotWhitelisted() public {
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, stranger, deadline);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("NotAllowed(address)", stranger));
        token.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
    }

    function test_OnChainSubscribe_RevertInvalidLotSize() public {
        uint128 badAmount = 150e18; // not a multiple of BOARD_LOT_SIZE
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, badAmount, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidTransferAmount(uint256)", badAmount));
        token.onChainSubscribe(USD_AMOUNT, badAmount, deadline, address(usdc), sig);
    }

    function test_OnChainSubscribe_RevertUnsupportedToken() public {
        address fakeToken = makeAddr("fakeToken");
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(fakeToken, USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("UnsupportedTokenAddress(address)", fakeToken));
        token.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, fakeToken, sig);
    }

    // ======================================================
    //               Update OnChain Subscribe
    // ======================================================

    function test_UpdateOnChainSubscribe_HappyPath() public {
        uint96 subId = _doSubscribe();

        vm.prank(tradeAdmin);
        token.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, ACTUAL_USD, REFUND_USD, TX_FEE, "off-1");

        IPETFTrading.SubscribeData memory sd = token.getSubscribeData(subId);
        assertEq(sd.actualPrice, ACTUAL_PRICE);
        assertEq(sd.actualEtfAmount, ACTUAL_ETF);
        assertEq(sd.actualUSDAmount, ACTUAL_USD);
        assertEq(sd.actualRefundUSDAmount, REFUND_USD);
    }

    function test_UpdateOnChainSubscribe_RevertActualUSDExceedsTotal() public {
        uint96 subId = _doSubscribe();

        // actualUSDAmount alone > sd.usdAmount
        uint128 overUSD = USD_AMOUNT + 1;
        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("InvalidTransferAmount(uint256)", uint256(overUSD)));
        token.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, overUSD, 0, 0, "x");
    }

    function test_UpdateOnChainSubscribe_RevertZeroUSDAmount() public {
        uint96 subId = _doSubscribe();

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("InvalidTransferAmount(uint256)", uint256(0)));
        token.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, 0, 0, 0, "x");
    }

    function test_UpdateOnChainSubscribe_RevertNotTradeAdmin() public {
        uint96 subId = _doSubscribe();

        vm.prank(stranger);
        vm.expectRevert();
        token.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, ACTUAL_USD, REFUND_USD, TX_FEE, "x");
    }

    function test_UpdateOnChainSubscribe_RevertAlreadySettled() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionAlreadySettled()"));
        token.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, ACTUAL_USD, REFUND_USD, TX_FEE, "x");
    }

    // ======================================================
    //               Settle OnChain Subscribe
    // ======================================================

    function test_SettleOnChainSubscribe_TransfersUSDToRecipients() public {
        uint96 subId = _doSubscribe();

        uint80 fee = 10e6;
        uint128 actualUSD = 890e6;
        uint128 refund = 100e6;
        // actualUSD + refund + fee = 1000e6 = USD_AMOUNT

        vm.prank(tradeAdmin);
        token.updateOnChainSubscribe(subId, ACTUAL_PRICE, ACTUAL_ETF, actualUSD, refund, fee, "off-1");

        uint256 assetBefore = usdc.balanceOf(assetRecipient);
        uint256 feeBefore = usdc.balanceOf(serviceFeeRecipient);

        vm.prank(tradeAdmin);
        token.settleOnChainSubscribe(subId);

        assertEq(usdc.balanceOf(assetRecipient), assetBefore + actualUSD, "assetRecipient not credited");
        assertEq(usdc.balanceOf(serviceFeeRecipient), feeBefore + fee, "serviceFeeRecipient not credited");

        IPETFTrading.SubscribeData memory sd = token.getSubscribeData(subId);
        assertTrue(sd.isSettled);
    }

    function test_SettleOnChainSubscribe_RevertAlreadySettled() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionAlreadySettled()"));
        token.settleOnChainSubscribe(subId);
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
        token.claim(subId);

        assertEq(token.balanceOf(user), etfBefore + ACTUAL_ETF, "ETF not minted");
        assertEq(usdc.balanceOf(user), usdBefore + REFUND_USD, "USD not refunded");
    }

    function test_Claim_DeletesRecord() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(user);
        token.claim(subId);

        vm.expectRevert(abi.encodeWithSignature("SubscriptionDoesNotExist()"));
        token.getSubscribeData(subId);
    }

    function test_Claim_RevertNotOwner() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OnlyTheRedeemerCanClaim()"));
        token.claim(subId);
    }

    function test_Claim_RevertNotSettled() public {
        uint96 subId = _doSubscribe();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionNotSettled()"));
        token.claim(subId);
    }

    function test_Claim_RevertBlacklisted() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        _block(user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("Blacklisted(address)", user));
        token.claim(subId);
    }

    // ======================================================
    //             Revert OnChain Subscribe
    // ======================================================

    function test_RevertOnChainSubscribe_RefundsUser() public {
        uint96 subId = _doSubscribe();

        uint256 userUsdBefore = usdc.balanceOf(user);
        uint256 contractUsdBefore = usdc.balanceOf(address(token));

        vm.prank(tradeAdmin);
        token.revertOnChainSubscribe(subId);

        assertEq(usdc.balanceOf(user), userUsdBefore + USD_AMOUNT, "user not refunded");
        assertEq(usdc.balanceOf(address(token)), contractUsdBefore - USD_AMOUNT, "contract not debited");
    }

    function test_RevertOnChainSubscribe_DeletesRecord() public {
        uint96 subId = _doSubscribe();

        vm.prank(tradeAdmin);
        token.revertOnChainSubscribe(subId);

        vm.expectRevert(abi.encodeWithSignature("SubscriptionDoesNotExist()"));
        token.getSubscribeData(subId);
    }

    function test_RevertOnChainSubscribe_RevertAfterSettled() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionAlreadySettled()"));
        token.revertOnChainSubscribe(subId);
    }

    // ======================================================
    //                  OnChain Redemption
    // ======================================================

    function _doRedemption() internal returns (uint96 redemptionId) {
        // First give user some ETF
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);
        _doClaim(subId);

        // Now place redemption order
        uint128 deadline = uint128(block.timestamp + 1 hours);
        bytes memory sig = _signRedeem(address(usdc), ACTUAL_ETF, user, deadline);
        vm.prank(user);
        token.onChainRedemption(address(usdc), ACTUAL_ETF, deadline, sig);

        redemptionId = 2; // subscriptionId=1, redemptionId=2
    }

    function test_OnChainRedemption_HappyPath() public {
        uint96 redemptionId = _doRedemption();

        IPETFTrading.RedemptionData memory rd = token.getRedemptionData(redemptionId);
        assertEq(rd.user, user);
        assertEq(rd.actualEtfAmount, ACTUAL_ETF);
        assertEq(rd.usdAddress, address(usdc));
        assertTrue(rd.isOnChain);
        assertFalse(rd.isSettled);
    }

    function test_OnChainRedemption_RevertExpiredDeadline() public {
        // Give user ETF first
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);
        _doClaim(subId);

        uint128 deadline = uint128(block.timestamp - 1);
        bytes memory sig = _signRedeem(address(usdc), ACTUAL_ETF, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("ExpiredOrder()"));
        token.onChainRedemption(address(usdc), ACTUAL_ETF, deadline, sig);
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
        token.onChainRedemption(address(usdc), ACTUAL_ETF, deadline, sig);
    }

    // ======================================================
    //               Settle OnChain Redemption
    // ======================================================

    function test_SettleOnChainRedemption_BurnsETF() public {
        uint96 redemptionId = _doRedemption();

        vm.prank(tradeAdmin);
        token.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);

        uint256 etfBefore = token.balanceOf(user);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(tradeAdmin);
        token.settleOnChainRedemption(redemptionId);

        assertEq(token.balanceOf(user), etfBefore - ACTUAL_ETF, "ETF not burned");
        assertEq(token.totalSupply(), supplyBefore - ACTUAL_ETF, "total supply not reduced");

        IPETFTrading.RedemptionData memory rd = token.getRedemptionData(redemptionId);
        assertTrue(rd.isSettled);
    }

    function test_SettleOnChainRedemption_RevertAlreadySettled() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        token.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        token.settleOnChainRedemption(redemptionId);
        vm.expectRevert(abi.encodeWithSignature("RedemptionAlreadySettled()"));
        token.settleOnChainRedemption(redemptionId);
        vm.stopPrank();
    }

    // ======================================================
    //                       ClaimUSD
    // ======================================================

    function test_ClaimUSD_TransfersUSDToUser() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        token.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        token.settleOnChainRedemption(redemptionId);
        vm.stopPrank();

        uint256 userUsdBefore = usdc.balanceOf(user);
        uint256 assetBefore = usdc.balanceOf(assetRecipient);

        vm.prank(user);
        token.claimUSD(redemptionId);

        assertEq(usdc.balanceOf(user), userUsdBefore + ACTUAL_USD, "user USD not credited");
        assertEq(usdc.balanceOf(assetRecipient), assetBefore - ACTUAL_USD, "assetRecipient not debited");
    }

    function test_ClaimUSD_DeletesRecord() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        token.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        token.settleOnChainRedemption(redemptionId);
        vm.stopPrank();

        vm.prank(user);
        token.claimUSD(redemptionId);

        vm.expectRevert(abi.encodeWithSignature("RedemptionDoesNotExist()"));
        token.getRedemptionData(redemptionId);
    }

    function test_ClaimUSD_RevertNotOwner() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        token.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        token.settleOnChainRedemption(redemptionId);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSignature("OnlyTheRedeemerCanClaim()"));
        token.claimUSD(redemptionId);
    }

    function test_ClaimUSD_RevertNotSettled() public {
        uint96 redemptionId = _doRedemption();

        vm.prank(tradeAdmin);
        token.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RedemptionNotSettled()"));
        token.claimUSD(redemptionId);
    }

    // ======================================================
    //             Revert OnChain Redemption
    // ======================================================

    function test_RevertOnChainRedemption_DeletesRecord() public {
        uint96 redemptionId = _doRedemption();

        vm.prank(tradeAdmin);
        token.revertOnChainRedemption(redemptionId);

        vm.expectRevert(abi.encodeWithSignature("RedemptionDoesNotExist()"));
        token.getRedemptionData(redemptionId);
    }

    function test_RevertOnChainRedemption_RevertAfterSettled() public {
        uint96 redemptionId = _doRedemption();

        vm.startPrank(tradeAdmin);
        token.updateOnChainRedemption(redemptionId, ACTUAL_USD, ACTUAL_PRICE, TX_FEE);
        token.settleOnChainRedemption(redemptionId);
        vm.expectRevert(abi.encodeWithSignature("RedemptionAlreadySettled()"));
        token.revertOnChainRedemption(redemptionId);
        vm.stopPrank();
    }

    // ======================================================
    //                 OffChain Subscribe
    // ======================================================

    function test_OffChainSubscribe_CreatesRecord() public {
        vm.prank(tradeAdmin);
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        IPETFTrading.SubscribeData memory sd = token.getSubscribeData(1);
        assertEq(sd.user, user);
        assertEq(sd.usdAmount, USD_AMOUNT);
        assertEq(sd.actualEtfAmount, ACTUAL_ETF);
        assertFalse(sd.isOnChain);
        assertFalse(sd.isSettled);
    }

    function test_SettleOffChainSubscribe_MarksSettled() public {
        vm.prank(tradeAdmin);
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        vm.prank(tradeAdmin);
        token.settleOffChainSubscribe(1);

        IPETFTrading.SubscribeData memory sd = token.getSubscribeData(1);
        assertTrue(sd.isSettled);
    }

    function test_DistributeSubscribe_MintsETF() public {
        vm.prank(tradeAdmin);
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        vm.prank(tradeAdmin);
        token.settleOffChainSubscribe(1);

        uint256 etfBefore = token.balanceOf(user);

        vm.prank(tradeAdmin);
        token.distributeSubscribe(1);

        assertEq(token.balanceOf(user), etfBefore + ACTUAL_ETF, "ETF not minted");
    }

    function test_DistributeSubscribe_DeletesRecord() public {
        vm.prank(tradeAdmin);
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        vm.prank(tradeAdmin);
        token.settleOffChainSubscribe(1);

        vm.prank(tradeAdmin);
        token.distributeSubscribe(1);

        vm.expectRevert(abi.encodeWithSignature("SubscriptionDoesNotExist()"));
        token.getSubscribeData(1);
    }

    function test_DistributeSubscribe_RevertNotSettled() public {
        vm.prank(tradeAdmin);
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("SubscriptionNotSettled()"));
        token.distributeSubscribe(1);
    }

    function test_RevertOffChainSubscribe_DeletesRecord() public {
        vm.prank(tradeAdmin);
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");

        vm.prank(tradeAdmin);
        token.revertOffChainSubscribe(1);

        vm.expectRevert(abi.encodeWithSignature("SubscriptionDoesNotExist()"));
        token.getSubscribeData(1);
    }

    function test_OffChainSubscribe_RevertBlockedUser() public {
        _block(user);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("Blacklisted(address)", user));
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");
    }

    // ======================================================
    //                 OffChain Redemption
    // ======================================================

    function test_OffChainRedemption_CreatesRecord() public {
        vm.prank(tradeAdmin);
        token.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");

        IPETFTrading.RedemptionData memory rd = token.getRedemptionData(1);
        assertEq(rd.user, user);
        assertEq(rd.actualUSDAmount, ACTUAL_USD);
        assertEq(rd.actualEtfAmount, ACTUAL_ETF);
        assertFalse(rd.isOnChain);
        assertFalse(rd.isSettled);
    }

    function test_SettleOffChainRedemption_MarksSettled() public {
        vm.prank(tradeAdmin);
        token.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");

        vm.prank(tradeAdmin);
        token.settleOffChainRedemption(1);

        IPETFTrading.RedemptionData memory rd = token.getRedemptionData(1);
        assertTrue(rd.isSettled);
    }

    function test_RevertOffChainRedemption_DeletesRecord() public {
        vm.prank(tradeAdmin);
        token.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");

        vm.prank(tradeAdmin);
        token.revertOffChainRedemption(1);

        vm.expectRevert(abi.encodeWithSignature("RedemptionDoesNotExist()"));
        token.getRedemptionData(1);
    }

    function test_OffChainRedemption_RevertBlockedUser() public {
        _block(user);

        vm.prank(tradeAdmin);
        vm.expectRevert(abi.encodeWithSignature("Blacklisted(address)", user));
        token.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");
    }

    // ======================================================
    //                     BurnAdmin
    // ======================================================

    function test_BurnAdmin_BurnsETFAndDeletesRecord() public {
        // Give user ETF via offchain subscribe
        vm.startPrank(tradeAdmin);
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "oc-1");
        token.settleOffChainSubscribe(1);
        token.distributeSubscribe(1);
        vm.stopPrank();

        assertEq(token.balanceOf(user), ACTUAL_ETF);

        // Create a redemption order
        vm.prank(tradeAdmin);
        token.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");
        uint96 redemptionId = 2;

        uint256 etfBefore = token.balanceOf(user);
        uint256 supplyBefore = token.totalSupply();

        vm.prank(tradeAdmin);
        token.burnAdmin(redemptionId);

        assertEq(token.balanceOf(user), etfBefore - ACTUAL_ETF, "ETF not burned");
        assertEq(token.totalSupply(), supplyBefore - ACTUAL_ETF, "total supply not reduced");

        vm.expectRevert(abi.encodeWithSignature("RedemptionDoesNotExist()"));
        token.getRedemptionData(redemptionId);
    }

    function test_BurnAdmin_RevertNotTradeAdmin() public {
        vm.prank(tradeAdmin);
        token.offChainRedemption(ACTUAL_USD, address(usdc), ACTUAL_ETF, user, ACTUAL_PRICE, TX_FEE, "or-1");

        vm.prank(stranger);
        vm.expectRevert();
        token.burnAdmin(1);
    }

    // ======================================================
    //                  Access Control
    // ======================================================

    function test_AccessControl_OffChainSubscribeRequiresTradeAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.offChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, ACTUAL_ETF, address(usdc), user, ACTUAL_PRICE, TX_FEE, "x");
    }

    function test_AccessControl_SetBoardLotSizeRequiresAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.setBoardLotSize(200e18);
    }

    function test_AccessControl_PauseRequiresEtfAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.pause();
    }

    function test_AccessControl_AddSignerRequiresAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.addOnRemoveAuthorizedSigner(stranger, true);
    }

    // ======================================================
    //                   Board Lot Size
    // ======================================================

    function test_BoardLotSize_SetAndGet() public {
        token.setBoardLotSize(200e18);
        assertEq(token.getBoardLotSize(), 200e18);
    }

    function test_BoardLotSize_DisableCheck() public {
        token.setHasMinAmount(false);
        // Should not revert with non-multiple amount
        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, 150e18, user, deadline);
        vm.prank(user);
        token.onChainSubscribe(USD_AMOUNT, 150e18, deadline, address(usdc), sig);
    }

    // ======================================================
    //                    Pause
    // ======================================================

    function test_Pause_BlocksOnChainSubscribe() public {
        token.pause();

        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        vm.prank(user);
        vm.expectRevert();
        token.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
    }

    function test_Pause_BlocksClaim() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        token.pause();

        vm.prank(user);
        vm.expectRevert();
        token.claim(subId);
    }

    function test_Unpause_ResumesOperations() public {
        token.pause();
        token.unpause();

        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        vm.prank(user);
        token.claim(subId);
        assertEq(token.balanceOf(user), ACTUAL_ETF);
    }

    // ======================================================
    //                  Snapshot
    // ======================================================

    function test_Snapshot_RecordsBalanceBeforeClaim() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);

        uint256 snapId = token.createNewSnapshot();

        // balanceOfAt snapshot before claim should be 0
        assertEq(token.balanceOfAt(user, snapId), 0);

        vm.prank(user);
        token.claim(subId);

        // balance now updated
        assertEq(token.balanceOf(user), ACTUAL_ETF);
        // snapshot still shows 0
        assertEq(token.balanceOfAt(user, snapId), 0);
    }

    // ======================================================
    //          ForceTransfer (ETF_ADMIN)
    // ======================================================

    function test_ForceTransfer_MovesTokens() public {
        uint96 subId = _doSubscribe();
        _doSettleSubscribe(subId);
        _doClaim(subId);

        assertEq(token.balanceOf(user), ACTUAL_ETF);

        token.forceTransfer(user, admin, ACTUAL_ETF);

        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(admin), ACTUAL_ETF);
    }

    function test_ForceTransfer_RevertNotEtfAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        token.forceTransfer(user, admin, ACTUAL_ETF);
    }

    // ======================================================
    //              Authorized Signer Management
    // ======================================================

    function test_AddRemoveAuthorizedSigner() public {
        address newSigner = makeAddr("newSigner");
        assertFalse(token.getAuthorizedSigner(newSigner));

        token.addOnRemoveAuthorizedSigner(newSigner, true);
        assertTrue(token.getAuthorizedSigner(newSigner));

        token.addOnRemoveAuthorizedSigner(newSigner, false);
        assertFalse(token.getAuthorizedSigner(newSigner));
    }

    function test_RemovedSigner_InvalidatesSignatures() public {
        token.addOnRemoveAuthorizedSigner(signer, false);

        uint96 deadline = uint96(block.timestamp + 1 hours);
        bytes memory sig = _signSubscribe(address(usdc), USD_AMOUNT, ORDER_ETF_AMOUNT, user, deadline);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidSignature()"));
        token.onChainSubscribe(USD_AMOUNT, ORDER_ETF_AMOUNT, deadline, address(usdc), sig);
    }

    // ======================================================
    //                  getPETFToken
    // ======================================================

    function test_GetPETFToken_ReturnsTokenAddress() public view {
        assertEq(trading.getPETFToken(), address(token));
    }
}
