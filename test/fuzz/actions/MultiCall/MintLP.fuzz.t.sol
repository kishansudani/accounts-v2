/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { MultiCall_Fuzz_Test } from "./_MultiCall.fuzz.t.sol";

import { ERC20Mock } from "../../.././utils/mocks/ERC20Mock.sol";
import { NonfungiblePositionManagerMock } from "../../.././utils/mocks/NonFungiblePositionManager.sol";

/**
 * @notice Fuzz tests for the "checkAmountOut" of contract "MultiCall".
 */
contract MintLP_MultiCall_Fuzz_Test is MultiCall_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                            VARIABLES
    /////////////////////////////////////////////////////////////// */

    ERC20Mock token0;
    ERC20Mock token1;
    NonfungiblePositionManagerMock univ3PosMgr;

    uint24 fee = 300;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override(MultiCall_Fuzz_Test) {
        MultiCall_Fuzz_Test.setUp();
        univ3PosMgr = new NonfungiblePositionManagerMock();

        deployUniswapV3PricingModule();

        token0 = new ERC20Mock('Token 0', 'TOK0', 18);
        token1 = new ERC20Mock('Token 1', 'TOK1', 18);
        (token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
        token0.mint(users.creatorAddress, 10 ** 38);
        token1.mint(users.creatorAddress, 10 ** 38);

        vm.prank(users.creatorAddress);
        uniV3PricingModule.addAsset(address(univ3PosMgr));
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Success_MintLP(int24 tickLower, int24 tickUpper, uint96 amount0Desired, uint96 amount1Desired)
        public
    {
        token0.mint(address(this), amount0Desired);
        token1.mint(address(this), amount1Desired);
        token0.approve(address(univ3PosMgr), amount0Desired);
        token1.approve(address(univ3PosMgr), amount1Desired);

        amount0Desired = 10 ** 10;
        amount1Desired = 10 ** 10;

        vm.assume(tickLower < tickUpper);

        NonfungiblePositionManagerMock.MintParams memory params = NonfungiblePositionManagerMock.MintParams({
            token0: address(token0),
            token1: address(token1),
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: type(uint256).max
        });

        bytes memory data = abi.encodeWithSelector(hex"88316456", params);

        assertEq(action.assets(), new address[](0));
        assertEq(action.ids(), new uint256[](0));
        action.mintLP(address(univ3PosMgr), data);

        uint256 tokenId = univ3PosMgr.id();
        address[] memory assetArr = new address[](1);
        assetArr[0] = address(univ3PosMgr);
        uint256[] memory idArr = new uint256[](1);
        idArr[0] = tokenId;

        assertEq(action.assets(), assetArr);
        assertEq(action.ids(), idArr);
    }
}
