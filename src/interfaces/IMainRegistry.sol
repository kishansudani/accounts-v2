/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: MIT
 */
pragma solidity 0.8.19;

import { RiskModule } from "../RiskModule.sol";

interface IMainRegistry {
    /**
     * @notice Returns the number of baseCurrencies.
     * @return Counter for the number of baseCurrencies in use.
     */
    function baseCurrencyCounter() external view returns (uint256);

    /**
     * @notice Returns the Factory address.
     * @return factory The contract address of the Factory.
     */
    function factory() external view returns (address);

    /**
     * @notice Returns the contract address of a baseCurrency.
     * @param index The index of the baseCurrency in the array baseCurrencies.
     * @return baseCurrency The contract address of a baseCurrency.
     */
    function baseCurrencies(uint256 index) external view returns (address);

    /**
     * @notice Checks if a contract is a baseCurrency.
     * @param baseCurrency The contract address of the baseCurrency.
     * @return boolean.
     */
    function isBaseCurrency(address baseCurrency) external view returns (bool);

    /**
     * @notice Checks if an action is allowed.
     * @param action The contract address of the action.
     * @return boolean.
     */
    function isActionAllowed(address action) external view returns (bool);

    /**
     * @notice Batch deposit multiple assets.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param amounts Array with the amounts of the assets.
     * @return assetTypes Array with the types of the assets.
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155.
     */
    function batchProcessDeposit(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata amounts
    ) external returns (uint256[] memory);

    /**
     * @notice Batch withdraw multiple assets.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param amounts Array with the amounts of the assets.
     * @return assetTypes Array with the types of the assets.
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155.
     */
    function batchProcessWithdrawal(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata amounts
    ) external returns (uint256[] memory);

    /**
     * @notice This function is called by pricing modules of non-primary assets in order to increase the exposure of the underlying asset.
     * @param underlyingAsset The underlying asset of a non-primary asset.
     * @param underlyingAssetId The underlying asset ID.
     * @param underlyingAssetAmount The underlying asset amount.
     */
    function increaseExposureUnderlyingAsset(
        address underlyingAsset,
        uint256 underlyingAssetId,
        uint256 underlyingAssetAmount
    ) external;

    /**
     * @notice This function is called by pricing modules of non-primary assets in order to decrease the exposure of the underlying asset.
     * @param underlyingAsset The underlying asset of a non-primary asset.
     * @param underlyingAssetId The underlying asset ID.
     * @param underlyingAssetAmount The underlying asset amount.
     */
    function decreaseExposureUnderlyingAsset(
        address underlyingAsset,
        uint256 underlyingAssetId,
        uint256 underlyingAssetAmount
    ) external;

    /**
     * @notice Calculates the combined value of a combination of assets, denominated in a given BaseCurrency.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param assetAmounts Array with the amounts of the assets.
     * @param baseCurrency The contract address of the BaseCurrency.
     * @return valueInBaseCurrency The combined value of the assets, denominated in BaseCurrency.
     */
    function getTotalValue(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        address baseCurrency
    ) external view returns (uint256);

    /**
     * @notice Calculates the collateralValue of a combination of assets, denominated in a given BaseCurrency.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param assetAmounts Array with the amounts of the assets.
     * @param baseCurrency The contract address of the BaseCurrency.
     * @return collateralValue The collateral value of the assets, denominated in BaseCurrency.
     */
    function getCollateralValue(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        address baseCurrency
    ) external view returns (uint256);

    /**
     * @notice Calculates the getLiquidationValue of a combination of assets, denominated in a given BaseCurrency.
     * @param assetAddresses Array of the contract addresses of the assets.
     * @param assetIds Array of the IDs of the assets.
     * @param assetAmounts Array with the amounts of the assets.
     * @param baseCurrency The contract address of the BaseCurrency.
     * @return liquidationValue The liquidation value of the assets, denominated in BaseCurrency.
     */
    function getLiquidationValue(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        address baseCurrency
    ) external view returns (uint256);

    function getListOfValuesPerAsset(
        address[] calldata assetAddresses,
        uint256[] calldata assetIds,
        uint256[] calldata assetAmounts,
        address baseCurrency
    ) external view returns (RiskModule.AssetValueAndRiskVariables[] memory);
}
