/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */

pragma solidity ^0.8.13;

library Constants {
    // Token decimals
    uint256 internal constant stableDecimals = 6;
    uint256 internal constant tokenDecimals = 18;

    // Oracle decimals
    uint256 internal constant stableOracleDecimals = 18;
    uint256 internal constant tokenOracleDecimals = 8;
    uint256 internal constant nftOracleDecimals = 8;
    uint256 internal constant erc1155OracleDecimals = 10;

    // See src/test_old/MerkleTrees
    bytes32 internal constant upgradeProof1To2 = 0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f;
    bytes32 internal constant upgradeRoot1To3 = 0x4a4a80da24004c581ecd9b9f53cb47269f979e9a0271f115ac01b91bd35349aa;
    bytes32 internal constant upgradeRoot1To2 = 0x472ba66bf173e177005d95fe17be2002ac4c417ff5bef6fb20a1e357f75bf394;
    bytes32 internal constant upgradeRoot1To1 = 0xcc69885fda6bcc1a4ace058b4a62bf5e179ea78fd58a1ccd71c22cc9b688792f;
}
