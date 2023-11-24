/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

/// @notice Abstract contract containing all the events emitted by the protocol.
abstract contract Events {
    /*//////////////////////////////////////////////////////////////////////////
                                      ERC-721
    //////////////////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 indexed id);

    /*//////////////////////////////////////////////////////////////////////////
                                      ERC-1155
    //////////////////////////////////////////////////////////////////////////*/

    event TransferSingle(
        address indexed operator, address indexed from, address indexed to, uint256 id, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////////////////
                                      PROXY
    //////////////////////////////////////////////////////////////////////////*/

    event Upgraded(address indexed implementation);

    /*//////////////////////////////////////////////////////////////////////////
                                     FACTORY
    //////////////////////////////////////////////////////////////////////////*/

    event AccountUpgraded(address indexed accountAddress, uint88 indexed newVersion);
    event AccountVersionAdded(uint88 indexed version, address indexed registry, address indexed logic);
    event AccountVersionBlocked(uint88 version);

    /*//////////////////////////////////////////////////////////////////////////
                                      ACCOUNT
    //////////////////////////////////////////////////////////////////////////*/

    event AssetManagerSet(address indexed owner, address indexed assetManager, bool value);
    event BaseCurrencySet(address indexed baseCurrency);
    event MarginAccountChanged(address indexed creditor, address indexed liquidator);

    /*//////////////////////////////////////////////////////////////////////////
                                BASE GUARDIAN
    //////////////////////////////////////////////////////////////////////////*/

    event GuardianChanged(address indexed oldGuardian, address indexed newGuardian);

    /*//////////////////////////////////////////////////////////////////////////
                                FACTORY GUARDIAN
    //////////////////////////////////////////////////////////////////////////*/

    event PauseUpdated(bool createPauseUpdate);

    /*//////////////////////////////////////////////////////////////////////////
                            MAIN REGISTRY GUARDIAN
    //////////////////////////////////////////////////////////////////////////*/

    event PauseFlagsUpdated(bool withdrawPauseUpdate, bool depositPauseUpdate);

    /*//////////////////////////////////////////////////////////////////////////
                                   REGISTRY
    //////////////////////////////////////////////////////////////////////////*/

    event AllowedActionSet(address indexed action, bool allowed);
    event AssetAdded(address indexed assetAddress, address indexed assetModule);
    event AssetModuleAdded(address assetModule);
    event OracleAdded(uint256 indexed oracleId, address indexed oracleModule);
    event OracleModuleAdded(address oracleModule);

    /*//////////////////////////////////////////////////////////////////////////
                                PRICING MODULE
    //////////////////////////////////////////////////////////////////////////*/

    event RiskManagerUpdated(address riskManager);
    event RiskVariablesSet(
        address indexed asset, uint8 indexed baseCurrencyId, uint16 collateralFactor, uint16 liquidationFactor
    );
    event MaxExposureSet(address indexed asset, uint128 maxExposure);

    /*//////////////////////////////////////////////////////////////////////////
                            DERIVED PRICING MODULE
    //////////////////////////////////////////////////////////////////////////*/

    event MaxUsdExposureProtocolSet(uint256 maxExposure);
}
