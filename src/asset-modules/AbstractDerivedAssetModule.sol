/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { AssetModule } from "./AbstractAssetModule.sol";
import { FixedPointMathLib } from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import { IRegistry } from "./interfaces/IRegistry.sol";
import { AssetValuationLib, AssetValueAndRiskFactors } from "../libraries/AssetValuationLib.sol";

/**
 * @title Derived Asset Module
 * @author Pragma Labs
 * @notice Abstract contract with the minimal implementation of a Derived Asset Module.
 * @dev Derived Assets are assets with underlying assets, the underlying assets can be Primary Assets or also Derived Assets.
 * For Derived Assets there are no direct external oracles.
 * USD values of assets must be calculated in a recursive manner via the pricing logic of the Underlying Assets.
 */
abstract contract DerivedAssetModule is AssetModule {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // Identifier indicating that it is a Derived Asset Module.
    bool internal constant PRIMARY_FLAG = false;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // Map with the risk parameters of the protocol for each Creditor.
    mapping(address creditor => RiskParameters riskParameters) public riskParams;
    // Map with the last exposures of each asset for each Creditor.
    mapping(address creditor => mapping(bytes32 assetKey => ExposuresPerAsset)) internal lastExposuresAsset;
    // Map with the last amount of exposure of each underlying asset for each asset for each Creditor.
    mapping(address creditor => mapping(bytes32 assetKey => mapping(bytes32 underlyingAssetKey => uint256 exposure)))
        internal lastExposureAssetToUnderlyingAsset;

    // Struct with the risk parameters of the protocol for a specific Creditor.
    struct RiskParameters {
        // The exposure in USD of the Creditor to the protocol at the last interaction, 18 decimals precision.
        uint112 lastUsdExposureProtocol;
        // The maximum exposure in USD of the Creditor to the protocol, 18 decimals precision.
        uint112 maxUsdExposureProtocol;
        // The risk factor of the protocol for a Creditor, 4 decimals precision.
        uint16 riskFactor;
    }

    // Struct with the exposures of a specific asset for a specific Creditor.
    struct ExposuresPerAsset {
        // The amount of exposure of the Creditor to the asset at the last interaction.
        uint112 lastExposureAsset;
        // The exposure in USD of the Creditor to the asset at the last interaction, 18 decimals precision.
        uint112 lastUsdExposureAsset;
    }

    /* //////////////////////////////////////////////////////////////
                                ERRORS
    ////////////////////////////////////////////////////////////// */

    error RiskFactorNotInLimits();

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param registry_ The contract address of the Registry.
     * @param assetType_ Identifier for the token standard of the asset.
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155.
     * ...
     */
    constructor(address registry_, uint256 assetType_) AssetModule(registry_, assetType_) { }

    /*///////////////////////////////////////////////////////////////
                        ASSET INFORMATION
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the unique identifiers of the underlying assets.
     * @param assetKey The unique identifier of the asset.
     * @return underlyingAssetKeys The unique identifiers of the underlying assets.
     */
    function _getUnderlyingAssets(bytes32 assetKey)
        internal
        view
        virtual
        returns (bytes32[] memory underlyingAssetKeys);

    /**
     * @notice Calculates the USD rate of 10**18 underlying assets.
     * @param creditor The contract address of the Creditor.
     * @param underlyingAssetKeys The unique identifiers of the underlying assets.
     * @return rateUnderlyingAssetsToUsd The USD rates of 10**18 tokens of underlying asset, with 18 decimals precision.
     * @dev The USD price per 10**18 tokens is used (instead of the USD price per token) to guarantee sufficient precision.
     */
    function _getRateUnderlyingAssetsToUsd(address creditor, bytes32[] memory underlyingAssetKeys)
        internal
        view
        virtual
        returns (AssetValueAndRiskFactors[] memory rateUnderlyingAssetsToUsd)
    {
        uint256 length = underlyingAssetKeys.length;

        address[] memory underlyingAssets = new address[](length);
        uint256[] memory underlyingAssetIds = new uint256[](length);
        uint256[] memory amounts = new uint256[](length);
        for (uint256 i; i < length;) {
            (underlyingAssets[i], underlyingAssetIds[i]) = _getAssetFromKey(underlyingAssetKeys[i]);
            // We use the USD price per 10**18 tokens instead of the USD price per token to guarantee
            // sufficient precision.
            amounts[i] = 1e18;

            unchecked {
                ++i;
            }
        }

        rateUnderlyingAssetsToUsd =
            IRegistry(REGISTRY).getValuesInUsd(creditor, underlyingAssets, underlyingAssetIds, amounts);
    }

    /**
     * @notice Calculates for a given amount of an Asset the corresponding amount(s) of Underlying Asset(s).
     * @param creditor The contract address of the Creditor.
     * @param assetKey The unique identifier of the asset.
     * @param assetAmount The amount of the asset, in the decimal precision of the Asset.
     * @param underlyingAssetKeys The unique identifiers of the underlying assets.
     * @return underlyingAssetsAmounts The corresponding amount(s) of Underlying Asset(s), in the decimal precision of the Underlying Asset.
     * @return rateUnderlyingAssetsToUsd The USD rates of 10**18 tokens of underlying asset, with 18 decimals precision.
     * @dev The USD price per 10**18 tokens is used (instead of the USD price per token) to guarantee sufficient precision.
     */
    function _getUnderlyingAssetsAmounts(
        address creditor,
        bytes32 assetKey,
        uint256 assetAmount,
        bytes32[] memory underlyingAssetKeys
    )
        internal
        view
        virtual
        returns (uint256[] memory underlyingAssetsAmounts, AssetValueAndRiskFactors[] memory rateUnderlyingAssetsToUsd);

    /*///////////////////////////////////////////////////////////////
                    RISK VARIABLES MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the risk factors of an asset for a Creditor.
     * @param creditor The contract address of the Creditor.
     * @param asset The contract address of the asset.
     * @param assetId The id of the asset.
     * @return collateralFactor The collateral factor of the asset for the Creditor, 4 decimals precision.
     * @return liquidationFactor The liquidation factor of the asset for the Creditor, 4 decimals precision.
     */
    function getRiskFactors(address creditor, address asset, uint256 assetId)
        external
        view
        virtual
        override
        returns (uint16 collateralFactor, uint16 liquidationFactor)
    {
        bytes32[] memory underlyingAssetKeys = _getUnderlyingAssets(_getKeyFromAsset(asset, assetId));

        uint256 length = underlyingAssetKeys.length;
        address[] memory assets = new address[](length);
        uint256[] memory assetIds = new uint256[](length);
        for (uint256 i; i < length;) {
            (assets[i], assetIds[i]) = _getAssetFromKey(underlyingAssetKeys[i]);

            unchecked {
                ++i;
            }
        }

        (uint16[] memory collateralFactors, uint16[] memory liquidationFactors) =
            IRegistry(REGISTRY).getRiskFactors(creditor, assets, assetIds);

        // Initialize risk factors with first elements of array.
        collateralFactor = collateralFactors[0];
        liquidationFactor = liquidationFactors[0];

        // Keep the lowest risk factor of all underlying assets.
        for (uint256 i = 1; i < length;) {
            if (collateralFactor > collateralFactors[i]) collateralFactor = collateralFactors[i];

            if (liquidationFactor > liquidationFactors[i]) liquidationFactor = liquidationFactors[i];

            unchecked {
                ++i;
            }
        }

        // Cache riskFactor
        uint256 riskFactor = riskParams[creditor].riskFactor;

        // Lower risk factors with the protocol wide risk factor.
        collateralFactor = uint16(riskFactor.mulDivDown(collateralFactor, AssetValuationLib.ONE_4));
        liquidationFactor = uint16(riskFactor.mulDivDown(liquidationFactor, AssetValuationLib.ONE_4));
    }

    /**
     * @notice Sets the risk parameters of the Protocol for a given Creditor.
     * @param creditor The contract address of the Creditor.
     * @param maxUsdExposureProtocol_ The maximum USD exposure of the protocol for each Creditor, denominated in USD with 18 decimals precision.
     * @param riskFactor The risk factor of the asset for the Creditor, 4 decimals precision.
     */
    function setRiskParameters(address creditor, uint112 maxUsdExposureProtocol_, uint16 riskFactor)
        external
        onlyRegistry
    {
        if (riskFactor > AssetValuationLib.ONE_4) revert RiskFactorNotInLimits();

        riskParams[creditor].maxUsdExposureProtocol = maxUsdExposureProtocol_;
        riskParams[creditor].riskFactor = riskFactor;
    }

    /*///////////////////////////////////////////////////////////////
                          PRICING LOGIC
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the USD value of an asset.
     * @param creditor The contract address of the Creditor.
     * @param asset The contract address of the asset.
     * @param assetId The id of the asset.
     * @param assetAmount The amount of assets.
     * @return valueInUsd The value of the asset denominated in USD, with 18 Decimals precision.
     * @return collateralFactor The collateral factor of the asset for a given Creditor, with 4 decimals precision.
     * @return liquidationFactor The liquidation factor of the asset for a given Creditor, with 4 decimals precision.
     */
    function getValue(address creditor, address asset, uint256 assetId, uint256 assetAmount)
        public
        view
        virtual
        override
        returns (uint256 valueInUsd, uint256 collateralFactor, uint256 liquidationFactor)
    {
        bytes32 assetKey = _getKeyFromAsset(asset, assetId);
        bytes32[] memory underlyingAssetKeys = _getUnderlyingAssets(assetKey);

        (uint256[] memory underlyingAssetsAmounts, AssetValueAndRiskFactors[] memory rateUnderlyingAssetsToUsd) =
            _getUnderlyingAssetsAmounts(creditor, assetKey, assetAmount, underlyingAssetKeys);

        // Check if rateToUsd for the underlying assets was already calculated in _getUnderlyingAssetsAmounts().
        if (rateUnderlyingAssetsToUsd.length == 0) {
            // If not, get the USD value of the underlying assets recursively.
            rateUnderlyingAssetsToUsd = _getRateUnderlyingAssetsToUsd(creditor, underlyingAssetKeys);
        }

        (valueInUsd, collateralFactor, liquidationFactor) =
            _calculateValueAndRiskFactors(creditor, underlyingAssetsAmounts, rateUnderlyingAssetsToUsd);
    }

    /**
     * @notice Returns the USD value of an asset.
     * @param creditor The contract address of the Creditor.
     * @param underlyingAssetsAmounts The corresponding amount(s) of Underlying Asset(s), in the decimal precision of the Underlying Asset.
     * @param rateUnderlyingAssetsToUsd The USD rates of 10**18 tokens of underlying asset, with 18 decimals precision.
     * @return valueInUsd The value of the asset denominated in USD, with 18 Decimals precision.
     * @return collateralFactor The collateral factor of the asset for a given Creditor, with 4 decimals precision.
     * @return liquidationFactor The liquidation factor of the asset for a given Creditor, with 4 decimals precision.
     * @dev We take the most conservative (lowest) risk factor of all underlying assets.
     */
    function _calculateValueAndRiskFactors(
        address creditor,
        uint256[] memory underlyingAssetsAmounts,
        AssetValueAndRiskFactors[] memory rateUnderlyingAssetsToUsd
    ) internal view virtual returns (uint256 valueInUsd, uint256 collateralFactor, uint256 liquidationFactor) {
        // Initialize variables with first elements of array.
        // "rateUnderlyingAssetsToUsd" is the USD value with 18 decimals precision for 10**18 tokens of Underlying Asset.
        // To get the USD value (also with 18 decimals) of the actual amount of underlying assets, we have to multiply
        // the actual amount with the rate for 10**18 tokens, and divide by 10**18.
        valueInUsd = underlyingAssetsAmounts[0].mulDivDown(rateUnderlyingAssetsToUsd[0].assetValue, 1e18);

        collateralFactor = rateUnderlyingAssetsToUsd[0].collateralFactor;
        liquidationFactor = rateUnderlyingAssetsToUsd[0].liquidationFactor;

        // Update variables with elements from index 1 until end of arrays:
        //  - Add USD value of all underlying assets together.
        //  - Keep the lowest risk factor of all underlying assets.
        uint256 length = underlyingAssetsAmounts.length;
        for (uint256 i = 1; i < length;) {
            valueInUsd += underlyingAssetsAmounts[i].mulDivDown(rateUnderlyingAssetsToUsd[i].assetValue, 1e18);

            if (collateralFactor > rateUnderlyingAssetsToUsd[i].collateralFactor) {
                collateralFactor = rateUnderlyingAssetsToUsd[i].collateralFactor;
            }

            if (liquidationFactor > rateUnderlyingAssetsToUsd[i].liquidationFactor) {
                liquidationFactor = rateUnderlyingAssetsToUsd[i].liquidationFactor;
            }

            unchecked {
                ++i;
            }
        }

        uint256 riskFactor = riskParams[creditor].riskFactor;

        // Lower risk factors with the protocol wide risk factor.
        liquidationFactor = riskFactor.mulDivDown(liquidationFactor, AssetValuationLib.ONE_4);
        collateralFactor = riskFactor.mulDivDown(collateralFactor, AssetValuationLib.ONE_4);
    }

    /*///////////////////////////////////////////////////////////////
                    WITHDRAWALS AND DEPOSITS
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Increases the exposure to an asset on a direct deposit.
     * @param creditor The contract address of the Creditor.
     * @param asset The contract address of the asset.
     * @param assetId The id of the asset.
     * @param amount The amount of tokens.
     * @return assetType Identifier for the type of the asset:
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155
     * ...
     */
    function processDirectDeposit(address creditor, address asset, uint256 assetId, uint256 amount)
        public
        virtual
        override
        onlyRegistry
        returns (uint256 assetType)
    {
        bytes32 assetKey = _getKeyFromAsset(asset, assetId);

        // Calculate and update the new exposure to Asset.
        uint256 exposureAsset = _getAndUpdateExposureAsset(creditor, assetKey, int256(amount));

        _processDeposit(creditor, assetKey, exposureAsset);

        assetType = ASSET_TYPE;
    }

    /**
     * @notice Increases the exposure to an asset on an indirect deposit.
     * @param creditor The contract address of the Creditor.
     * @param asset The contract address of the asset.
     * @param assetId The id of the asset.
     * @param exposureUpperAssetToAsset The amount of exposure of the upper asset to the asset of this Asset Module.
     * @param deltaExposureUpperAssetToAsset The increase or decrease in exposure of the upper asset to the asset of this Asset Module since last interaction.
     * @return primaryFlag Identifier indicating if it is a Primary or Derived Asset Module.
     * @return usdExposureUpperAssetToAsset The USD value of the exposure of the upper asset to the asset of this Asset Module, 18 decimals precision.
     * @dev An indirect deposit, is initiated by a deposit of another derived asset (the upper asset),
     * from which the asset of this Asset Module is an underlying asset.
     */
    function processIndirectDeposit(
        address creditor,
        address asset,
        uint256 assetId,
        uint256 exposureUpperAssetToAsset,
        int256 deltaExposureUpperAssetToAsset
    ) public virtual override onlyRegistry returns (bool primaryFlag, uint256 usdExposureUpperAssetToAsset) {
        bytes32 assetKey = _getKeyFromAsset(asset, assetId);

        // Calculate and update the new exposure to "Asset".
        uint256 exposureAsset = _getAndUpdateExposureAsset(creditor, assetKey, deltaExposureUpperAssetToAsset);

        uint256 usdExposureAsset = _processDeposit(creditor, assetKey, exposureAsset);

        if (exposureAsset == 0 || usdExposureAsset == 0) {
            usdExposureUpperAssetToAsset = 0;
        } else {
            // Calculate the USD value of the exposure of the upper asset to the underlying asset.
            usdExposureUpperAssetToAsset = usdExposureAsset.mulDivDown(exposureUpperAssetToAsset, exposureAsset);
        }

        return (PRIMARY_FLAG, usdExposureUpperAssetToAsset);
    }

    /**
     * @notice Decreases the exposure to an asset on a direct withdrawal.
     * @param creditor The contract address of the Creditor.
     * @param asset The contract address of the asset.
     * @param assetId The id of the asset.
     * @param amount The amount of tokens.
     * @return assetType Identifier for the type of the asset:
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155
     * ...
     */
    function processDirectWithdrawal(address creditor, address asset, uint256 assetId, uint256 amount)
        public
        virtual
        override
        onlyRegistry
        returns (uint256 assetType)
    {
        bytes32 assetKey = _getKeyFromAsset(asset, assetId);

        // Calculate and update the new exposure to "Asset".
        uint256 exposureAsset = _getAndUpdateExposureAsset(creditor, assetKey, -int256(amount));

        _processWithdrawal(creditor, assetKey, exposureAsset);

        assetType = ASSET_TYPE;
    }

    /**
     * @notice Decreases the exposure to an asset on an indirect withdrawal.
     * @param creditor The contract address of the Creditor.
     * @param asset The contract address of the asset.
     * @param assetId The id of the asset.
     * @param exposureUpperAssetToAsset The amount of exposure of the upper asset to the asset of this Asset Module.
     * @param deltaExposureUpperAssetToAsset The increase or decrease in exposure of the upper asset to the asset of this Asset Module since last interaction.
     * @return primaryFlag Identifier indicating if it is a Primary or Derived Asset Module.
     * @return usdExposureUpperAssetToAsset The USD value of the exposure of the upper asset to the asset of this Asset Module, 18 decimals precision.
     * @dev An indirect withdrawal is initiated by a withdrawal of another Derived Asset (the upper asset),
     * from which the asset of this Asset Module is an Underlying Asset.
     */
    function processIndirectWithdrawal(
        address creditor,
        address asset,
        uint256 assetId,
        uint256 exposureUpperAssetToAsset,
        int256 deltaExposureUpperAssetToAsset
    ) public virtual override onlyRegistry returns (bool primaryFlag, uint256 usdExposureUpperAssetToAsset) {
        bytes32 assetKey = _getKeyFromAsset(asset, assetId);

        // Calculate and update the new exposure to "Asset".
        uint256 exposureAsset = _getAndUpdateExposureAsset(creditor, assetKey, deltaExposureUpperAssetToAsset);

        uint256 usdExposureAsset = _processWithdrawal(creditor, assetKey, exposureAsset);

        if (exposureAsset == 0 || usdExposureAsset == 0) {
            usdExposureUpperAssetToAsset = 0;
        } else {
            // Calculate the USD value of the exposure of the Upper Asset to the Underlying asset.
            usdExposureUpperAssetToAsset = usdExposureAsset.mulDivDown(exposureUpperAssetToAsset, exposureAsset);
        }

        return (PRIMARY_FLAG, usdExposureUpperAssetToAsset);
    }

    /**
     * @notice Update the exposure to an asset and its underlying asset(s) on deposit.
     * @param creditor The contract address of the Creditor.
     * @param assetKey The unique identifier of the asset.
     * @param exposureAsset The updated exposure to the asset.
     * @return usdExposureAsset The USD value of the exposure of the asset, 18 decimals precision.
     * @dev The checks on exposures are only done to block deposits that would over-expose a Creditor to a certain asset or protocol.
     * Underflows will not revert, but the exposure is instead set to 0.
     */
    function _processDeposit(address creditor, bytes32 assetKey, uint256 exposureAsset)
        internal
        virtual
        returns (uint256 usdExposureAsset)
    {
        // Get the unique identifier(s) of the underlying asset(s).
        bytes32[] memory underlyingAssetKeys = _getUnderlyingAssets(assetKey);

        // Get the exposure to the asset's underlying asset(s) (in the decimal precision of the underlying assets).
        (uint256[] memory exposureAssetToUnderlyingAssets,) =
            _getUnderlyingAssetsAmounts(creditor, assetKey, exposureAsset, underlyingAssetKeys);

        int256 deltaExposureAssetToUnderlyingAsset;
        address underlyingAsset;
        uint256 underlyingId;

        for (uint256 i; i < underlyingAssetKeys.length;) {
            // Calculate the change in exposure to the underlying assets since last interaction.
            deltaExposureAssetToUnderlyingAsset = int256(exposureAssetToUnderlyingAssets[i])
                - int256(uint256(lastExposureAssetToUnderlyingAsset[creditor][assetKey][underlyingAssetKeys[i]]));

            // Update "lastExposureAssetToUnderlyingAsset".
            lastExposureAssetToUnderlyingAsset[creditor][assetKey][underlyingAssetKeys[i]] =
                uint128(exposureAssetToUnderlyingAssets[i]); // ToDo: safecast?

            // Get the USD Value of the total exposure of "Asset" for its "Underlying Assets" at index "i".
            // If the "underlyingAsset" has one or more underlying assets itself, the lower level
            // Asset Module(s) will recursively update their respective exposures and return
            // the requested USD value to this Asset Module.
            (underlyingAsset, underlyingId) = _getAssetFromKey(underlyingAssetKeys[i]);
            usdExposureAsset += IRegistry(REGISTRY).getUsdValueExposureToUnderlyingAssetAfterDeposit(
                creditor,
                underlyingAsset,
                underlyingId,
                exposureAssetToUnderlyingAssets[i],
                deltaExposureAssetToUnderlyingAsset
            );

            unchecked {
                ++i;
            }
        }

        // Cache and update lastUsdExposureAsset.
        uint256 lastUsdExposureAsset = lastExposuresAsset[creditor][assetKey].lastUsdExposureAsset;
        lastExposuresAsset[creditor][assetKey].lastUsdExposureAsset = uint112(usdExposureAsset); // ToDo safecast.

        // Cache lastUsdExposureProtocol.
        uint256 lastUsdExposureProtocol = riskParams[creditor].lastUsdExposureProtocol;

        // Update lastUsdExposureProtocol.
        uint256 usdExposureProtocol;
        unchecked {
            if (usdExposureAsset >= lastUsdExposureAsset) {
                usdExposureProtocol = lastUsdExposureProtocol + (usdExposureAsset - lastUsdExposureAsset);
            } else if (lastUsdExposureProtocol > lastUsdExposureAsset - usdExposureAsset) {
                usdExposureProtocol = lastUsdExposureProtocol - (lastUsdExposureAsset - usdExposureAsset);
            }
            // For the else case: (lastUsdExposureProtocol < lastUsdExposureAsset - usdExposureAsset),
            // usdExposureProtocol is set to 0, but usdExposureProtocol is already 0.
        }
        // The exposure must be strictly smaller than the maxExposure, not equal to or smaller than.
        // This is to ensure that all deposits revert when maxExposure is set to 0, also deposits with 0 amounts.
        if (usdExposureProtocol >= riskParams[creditor].maxUsdExposureProtocol) {
            revert AssetModule.ExposureNotInLimits();
        }
        riskParams[creditor].lastUsdExposureProtocol = uint112(usdExposureProtocol);
    }

    /**
     * @notice Update the exposure to an asset and its underlying asset(s) on withdrawal.
     * @param creditor The contract address of the Creditor.
     * @param assetKey The unique identifier of the asset.
     * @param exposureAsset The updated exposure to the asset.
     * @return usdExposureAsset The USD value of the exposure of the asset, 18 decimals precision.
     * @dev The checks on exposures are only done to block deposits that would over-expose a Creditor to a certain asset or protocol.
     * Underflows will not revert, but the exposure is instead set to 0.
     */
    function _processWithdrawal(address creditor, bytes32 assetKey, uint256 exposureAsset)
        internal
        virtual
        returns (uint256 usdExposureAsset)
    {
        // Get the unique identifier(s) of the underlying asset(s).
        bytes32[] memory underlyingAssetKeys = _getUnderlyingAssets(assetKey);

        // Get the exposure to the asset's underlying asset(s) (in the decimal precision of the underlying assets).
        (uint256[] memory exposureAssetToUnderlyingAssets,) =
            _getUnderlyingAssetsAmounts(creditor, assetKey, exposureAsset, underlyingAssetKeys);

        int256 deltaExposureAssetToUnderlyingAsset;
        address underlyingAsset;
        uint256 underlyingId;

        for (uint256 i; i < underlyingAssetKeys.length;) {
            // Calculate the change in exposure to the underlying assets since last interaction.
            deltaExposureAssetToUnderlyingAsset = int256(exposureAssetToUnderlyingAssets[i])
                - int256(uint256(lastExposureAssetToUnderlyingAsset[creditor][assetKey][underlyingAssetKeys[i]]));

            // Update "lastExposureAssetToUnderlyingAsset".
            lastExposureAssetToUnderlyingAsset[creditor][assetKey][underlyingAssetKeys[i]] =
                uint128(exposureAssetToUnderlyingAssets[i]); // ToDo: safecast?

            // Get the USD Value of the total exposure of "Asset" for for all of its "Underlying Assets".
            // If an "underlyingAsset" has one or more underlying assets itself, the lower level
            // Asset Modules will recursively update their respective exposures and return
            // the requested USD value to this Asset Module.
            (underlyingAsset, underlyingId) = _getAssetFromKey(underlyingAssetKeys[i]);
            usdExposureAsset += IRegistry(REGISTRY).getUsdValueExposureToUnderlyingAssetAfterWithdrawal(
                creditor,
                underlyingAsset,
                underlyingId,
                exposureAssetToUnderlyingAssets[i],
                deltaExposureAssetToUnderlyingAsset
            );

            unchecked {
                ++i;
            }
        }

        // Cache and update lastUsdExposureAsset.
        uint256 lastUsdExposureAsset = lastExposuresAsset[creditor][assetKey].lastUsdExposureAsset;
        lastExposuresAsset[creditor][assetKey].lastUsdExposureAsset = uint112(usdExposureAsset);

        // Cache lastUsdExposureProtocol.
        uint256 lastUsdExposureProtocol = riskParams[creditor].lastUsdExposureProtocol;

        // Update lastUsdExposureProtocol.
        uint256 usdExposureProtocol;
        unchecked {
            if (usdExposureAsset >= lastUsdExposureAsset) {
                usdExposureProtocol = lastUsdExposureProtocol + (usdExposureAsset - lastUsdExposureAsset);
                if (usdExposureProtocol > type(uint112).max) revert Overflow();
            } else if (lastUsdExposureProtocol > lastUsdExposureAsset - usdExposureAsset) {
                usdExposureProtocol = lastUsdExposureProtocol - (lastUsdExposureAsset - usdExposureAsset);
            }
            // For the else case: (lastUsdExposureProtocol < lastUsdExposureAsset - usdExposureAsset),
            // usdExposureProtocol is set to 0, but usdExposureProtocol is already 0.
        }
        riskParams[creditor].lastUsdExposureProtocol = uint112(usdExposureProtocol);
    }

    /**
     * @notice Updates the exposure to the asset.
     * @param creditor The contract address of the Creditor.
     * @param assetKey The unique identifier of the asset.
     * @param deltaAsset The increase or decrease in asset amount since the last interaction.
     * @return exposureAsset The updated exposure to the asset.
     * @dev The checks on exposures are only done to block deposits that would over-expose a Creditor to a certain asset or protocol.
     * Underflows will not revert, but the exposure is instead set to 0.
     */
    function _getAndUpdateExposureAsset(address creditor, bytes32 assetKey, int256 deltaAsset)
        internal
        returns (uint256 exposureAsset)
    {
        // Update exposureAssetLast.
        if (deltaAsset > 0) {
            exposureAsset = lastExposuresAsset[creditor][assetKey].lastExposureAsset + uint256(deltaAsset);
        } else {
            uint256 exposureAssetLast = lastExposuresAsset[creditor][assetKey].lastExposureAsset;
            exposureAsset = exposureAssetLast > uint256(-deltaAsset) ? exposureAssetLast - uint256(-deltaAsset) : 0;
        }
        lastExposuresAsset[creditor][assetKey].lastExposureAsset = uint112(exposureAsset); // ToDo safecast.
    }
}
