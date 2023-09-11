/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { Constants, Factory_Fuzz_Test } from "./Factory.fuzz.t.sol";

/**
 * @notice Fuzz tests for the "blockAccountVersion" of contract "Factory".
 */
contract BlockAccountVersion_Factory_Fuzz_Test is Factory_Fuzz_Test {
    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public override {
        Factory_Fuzz_Test.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                              TESTS
    //////////////////////////////////////////////////////////////*/
    function testRevert_blockAccountVersion_NonOwner(uint16 accountVersion, address unprivilegedAddress_) public {
        vm.assume(unprivilegedAddress_ != users.creatorAddress);

        uint256 currentVersion = factory.latestAccountVersion();
        vm.assume(accountVersion <= currentVersion);
        vm.assume(accountVersion != 0);

        vm.startPrank(unprivilegedAddress_);
        vm.expectRevert("UNAUTHORIZED");
        factory.blockAccountVersion(accountVersion);
        vm.stopPrank();
    }

    function testRevert_blockAccountVersion_BlockNonExistingAccountVersion(uint16 accountVersion) public {
        uint256 currentVersion = factory.latestAccountVersion();
        vm.assume(accountVersion > currentVersion || accountVersion == 0);

        vm.startPrank(users.creatorAddress);
        vm.expectRevert("FTRY_BVV: Invalid version");
        factory.blockAccountVersion(accountVersion);
        vm.stopPrank();
    }

    function testSuccess_blockAccountVersion(uint16 accountVersion) public {
        uint256 currentVersion = factory.latestAccountVersion();
        vm.assume(accountVersion <= currentVersion);
        vm.assume(accountVersion != 0);

        vm.startPrank(users.creatorAddress);
        vm.expectEmit(true, true, true, true);
        emit AccountVersionBlocked(accountVersion);
        factory.blockAccountVersion(accountVersion);
        vm.stopPrank();

        assertTrue(factory.accountVersionBlocked(accountVersion));
    }
}
