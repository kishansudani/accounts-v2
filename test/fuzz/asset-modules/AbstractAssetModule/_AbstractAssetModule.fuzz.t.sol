/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { Fuzz_Test, Constants } from "../../Fuzz.t.sol";
import { AssetModuleMock } from "../../../utils/mocks/AssetModuleMock.sol";

/**
 * @notice Common logic needed by all "AbstractAssetModule" fuzz tests.
 */
abstract contract AbstractAssetModule_Fuzz_Test is Fuzz_Test {
    /*////////////////////////////////////////////////////////////////
                            TEST CONTRACTS
    /////////////////////////////////////////////////////////////// */

    AssetModuleMock internal assetModule;

    /* ///////////////////////////////////////////////////////////////
                              SETUP
    /////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();

        vm.prank(users.creatorAddress);
        assetModule = new AssetModuleMock(address(mainRegistryExtension), 0);
    }
}