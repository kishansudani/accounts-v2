/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { MainRegistry_Fuzz_Test } from "./_MainRegistry.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "addOracle" of contract "MainRegistry".
 */
contract AddOracle_MainRegistry_Fuzz_Test is MainRegistry_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        MainRegistry_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testFuzz_Revert_addOracle_NonAssetModule(address unprivilegedAddress_) public {
        vm.assume(!mainRegistryExtension.isOracleModule(unprivilegedAddress_));

        vm.prank(users.creatorAddress);
        vm.expectRevert("MR: Only OracleMod.");
        mainRegistryExtension.addOracle();
    }

    function testFuzz_Success_addOracle(address oracleModule_, uint256 oracleCounterLast) public {
        vm.assume(!mainRegistryExtension.isOracleModule(oracleModule_));
        vm.prank(users.creatorAddress);
        mainRegistryExtension.addOracleModule(oracleModule_);

        oracleCounterLast = bound(oracleCounterLast, 0, type(uint80).max);
        mainRegistryExtension.setOracleCounter(oracleCounterLast);

        vm.prank(oracleModule_);
        uint256 oracleId = mainRegistryExtension.addOracle();

        assertEq(oracleId, oracleCounterLast);
        assertEq(mainRegistryExtension.getOracleToOracleModule(oracleId), oracleModule_);
        assertEq(mainRegistryExtension.getOracleCounter(), oracleCounterLast + 1);
    }
}