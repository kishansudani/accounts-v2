/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { IMainRegistry } from "./interfaces/IMainRegistryOptionThomas.sol";
import { IPricingModule } from "../interfaces/IPricingModuleOptionThomas.sol";
import { RiskConstants } from "../libraries/RiskConstants.sol";
import { Owned } from "../../lib/solmate/src/auth/Owned.sol";

/**
 * @title Primary Pricing Module.
 * @author Pragma Labs
 */
abstract contract PrimaryPricingModule is Owned, IPricingModule {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    bool internal constant PRIMARY_FLAG = true;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The contract address of the MainRegistry.
    address public immutable mainRegistry;
    // The contract address of the OracleHub.
    address public immutable oracleHub;
    // Identifier for the token standard of the asset.
    uint256 public immutable assetType;
    // The address of the riskManager.
    address public riskManager;

    // Array with all the contract addresses of assets added to the Pricing Module.
    address[] public assetsInPricingModule;

    // Map asset => flag.
    mapping(address => bool) public inPricingModule;
    // Map asset => exposureInformation.
    mapping(address => Exposure) public exposure;
    // Map asset => baseCurrencyIdentifier => riskVariables.
    mapping(address => mapping(uint256 => RiskVars)) public assetRiskVars;

    // Struct with information about the exposure of a specific asset.
    struct Exposure {
        uint128 maxExposure; // The maximum protocol wide exposure to an asset.
        uint128 exposure; // The actual protocol wide exposure to an asset.
    }

    // Struct with the risk variables of a specific asset for a specific baseCurrency.
    struct RiskVars {
        uint16 collateralFactor; // The collateral factor, 2 decimals precision.
        uint16 liquidationFactor; // The liquidation factor, 2 decimals precision.
    }

    // Struct with the input variables for the function setBatchRiskVariables().
    struct RiskVarInput {
        address asset; // The contract address of an asset.
        uint8 baseCurrency; // An identifier (uint256) of a BaseCurrency.
        uint16 collateralFactor; // The collateral factor, 2 decimals precision.
        uint16 liquidationFactor; // The liquidation factor, 2 decimals precision.
    }

    /* //////////////////////////////////////////////////////////////
                                EVENTS
    ////////////////////////////////////////////////////////////// */

    event RiskManagerUpdated(address riskManager);
    event RiskVariablesSet(
        address indexed asset, uint8 indexed baseCurrencyId, uint16 collateralFactor, uint16 liquidationFactor
    );
    event MaxExposureSet(address indexed asset, uint128 maxExposure);

    event AssetExposureChanged(address asset, uint128 oldExposure, uint128 newExposure);

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier onlyRiskManager() {
        require(msg.sender == riskManager, "APM: ONLY_RISK_MANAGER");
        _;
    }

    modifier onlyMainReg() {
        require(msg.sender == mainRegistry, "APM: ONLY_MAIN_REGISTRY");
        _;
    }

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param mainRegistry_ The contract address of the MainRegistry.
     * @param oracleHub_ The contract address of the OracleHub.
     * @param assetType_ Identifier for the token standard of the asset.
     * 0 = ERC20.
     * 1 = ERC721.
     * 2 = ERC1155.
     * @param riskManager_ The address of the Risk Manager.
     */
    constructor(address mainRegistry_, address oracleHub_, uint256 assetType_, address riskManager_)
        Owned(msg.sender)
    {
        mainRegistry = mainRegistry_;
        oracleHub = oracleHub_;
        assetType = assetType_;
        riskManager = riskManager_;

        emit RiskManagerUpdated(riskManager_);
    }

    /*///////////////////////////////////////////////////////////////
                    RISK MANAGER MANAGEMENT
    ///////////////////////////////////////////////////////////////*/
    /**
     * @notice Sets a new Risk Manager.
     * @param riskManager_ The address of the new Risk Manager.
     */
    function setRiskManager(address riskManager_) external onlyOwner {
        riskManager = riskManager_;

        emit RiskManagerUpdated(riskManager_);
    }

    /*///////////////////////////////////////////////////////////////
                        WHITE LIST MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks for a token address and the corresponding Id if it is white-listed.
     * @param asset The contract address of the asset.
     * param assetId The Id of the asset.
     * @return A boolean, indicating if the asset is whitelisted.
     * @dev For assets without Id (ERC20, ERC4626...), the Id should be set to 0.
     */
    function isAllowListed(address asset, uint256) public view virtual returns (bool) {
        return exposure[asset].maxExposure != 0;
    }

    /*///////////////////////////////////////////////////////////////
                          PRICING LOGIC
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the value of a certain asset, denominated in USD, 18 decimals precision.
     * @return collateralFactor The collateral factor of the asset for a given baseCurrency, 2 decimals precision.
     * @return liquidationFactor The liquidation factor of the asset for a given baseCurrency, 2 decimals precision.
     */
    function getValue(GetValueInput memory) public view virtual returns (uint256, uint256, uint256) { }

    /*///////////////////////////////////////////////////////////////
                    RISK VARIABLES MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the risk variables of an asset.
     * @param asset The contract address of the asset.
     * @param baseCurrency An identifier (uint256) of the BaseCurrency.
     * @return collateralFactor The collateral factor of the asset for a given baseCurrency, 2 decimals precision.
     * @return liquidationFactor The liquidation factor of the asset for a given baseCurrency, 2 decimals precision.
     */
    function getRiskVariables(address asset, uint256 baseCurrency) public view virtual returns (uint16, uint16) {
        return
            (assetRiskVars[asset][baseCurrency].collateralFactor, assetRiskVars[asset][baseCurrency].liquidationFactor);
    }

    /**
     * @notice Sets a batch of risk variables for a batch of assets.
     * @param riskVarInputs An array of RiskVarInput structs.
     * @dev Risk variables have 2 decimals precision.
     * @dev Can only be called by the Risk Manager, which can be different from the owner.
     */
    function setBatchRiskVariables(RiskVarInput[] memory riskVarInputs) public virtual onlyRiskManager {
        uint256 baseCurrencyCounter = IMainRegistry(mainRegistry).baseCurrencyCounter();
        uint256 riskVarInputsLength = riskVarInputs.length;

        for (uint256 i; i < riskVarInputsLength;) {
            require(riskVarInputs[i].baseCurrency < baseCurrencyCounter, "APM_SBRV: BaseCur. not in limits");

            _setRiskVariables(
                riskVarInputs[i].asset,
                riskVarInputs[i].baseCurrency,
                RiskVars({
                    collateralFactor: riskVarInputs[i].collateralFactor,
                    liquidationFactor: riskVarInputs[i].liquidationFactor
                })
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Sets a batch of risk variables for a specific asset.
     * @param asset The contract address of the asset.
     * @param riskVarInputs An array of RiskVarInput structs.
     * @dev Risk variables have 2 decimals precision.
     * @dev The asset slot in the RiskVarInput struct is ignored for this function.
     */
    function _setRiskVariablesForAsset(address asset, RiskVarInput[] memory riskVarInputs) internal virtual {
        uint256 baseCurrencyCounter = IMainRegistry(mainRegistry).baseCurrencyCounter();
        uint256 riskVarInputsLength = riskVarInputs.length;

        for (uint256 i; i < riskVarInputsLength;) {
            require(baseCurrencyCounter > riskVarInputs[i].baseCurrency, "APM_SRVFA: BaseCur not in limits");
            _setRiskVariables(
                asset,
                riskVarInputs[i].baseCurrency,
                RiskVars({
                    collateralFactor: riskVarInputs[i].collateralFactor,
                    liquidationFactor: riskVarInputs[i].liquidationFactor
                })
            );

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Sets a single pair of risk variables.
     * @param asset The contract address of the asset.
     * @param baseCurrency An identifier (uint256) of the BaseCurrency.
     * @param riskVars A struct with the risk variables.
     * @dev Risk variables have 2 decimals precision.
     */
    function _setRiskVariables(address asset, uint256 baseCurrency, RiskVars memory riskVars) internal virtual {
        require(riskVars.collateralFactor <= RiskConstants.MAX_COLLATERAL_FACTOR, "APM_SRV: Coll.Fact not in limits");
        require(riskVars.liquidationFactor <= RiskConstants.MAX_LIQUIDATION_FACTOR, "APM_SRV: Liq.Fact not in limits");

        assetRiskVars[asset][baseCurrency] = riskVars;

        emit RiskVariablesSet(asset, uint8(baseCurrency), riskVars.collateralFactor, riskVars.liquidationFactor);
    }

    /**
     * @notice Sets the maximum exposure for an asset.
     * @param asset The contract address of the asset.
     * @param maxExposure The maximum protocol wide exposure to the asset.
     * @dev Can only be called by the Risk Manager, which can be different from the owner.
     */
    function setExposureOfAsset(address asset, uint256 maxExposure) public virtual onlyRiskManager {
        require(maxExposure <= type(uint128).max, "APM_SEA: Max Exp. not in limits");
        exposure[asset].maxExposure = uint128(maxExposure);

        emit MaxExposureSet(asset, uint128(maxExposure));
    }

    /**
     * @notice Increases the exposure to an asset on deposit.
     * @param asset The contract address of the asset.
     * param id The Id of the asset.
     * @param amount The amount of tokens.
     */
    function processDirectDeposit(address asset, uint256, uint256 amount) public virtual onlyMainReg {
        // Cache exposureLast.
        uint256 exposureLast = exposure[asset].exposure;

        require(exposureLast + uint128(amount) <= exposure[asset].maxExposure, "APM_IE: Exposure not in limits");

        exposure[asset].exposure = uint128(exposureLast) + uint128(amount);
        emit AssetExposureChanged(asset, uint128(exposureLast), uint128(exposureLast) + uint128(amount));
    }

    /**
     * @notice Increases the exposure to an underlying asset on deposit.
     * @param asset The contract address of the asset.
     * param id The Id of the asset.
     * @param amount The amount of tokens.
     */
    function processIndirectDeposit(address asset, uint256, int256 amount)
        public
        virtual
        onlyMainReg
        returns (bool primaryFlag, uint256 valueInUsd)
    {
        // Cache exposureLast.
        uint256 exposureLast = exposure[asset].exposure;

        if (amount > 0) {
            require(
                exposureLast + uint128(uint256(amount)) <= exposure[asset].maxExposure, "APM_IE: Exposure not in limits"
            );

            exposure[asset].exposure = uint128(exposureLast) + uint128(uint256(amount));
            emit AssetExposureChanged(asset, uint128(exposureLast), uint128(exposureLast) + uint128(uint256(amount)));
        } else {
            uint256 amount_ = uint256(-amount);
            exposureLast >= amount_
                ? exposure[asset].exposure = uint128(exposureLast) - uint128(amount_)
                : exposure[asset].exposure = 0;
            emit AssetExposureChanged(
                asset,
                uint128(exposureLast),
                exposureLast >= amount_
                    ? exposure[asset].exposure = uint128(exposureLast) - uint128(amount_)
                    : exposure[asset].exposure = 0
            );
        }

        // Get Value in Usd
        (valueInUsd,,) = getValue(
            IPricingModule.GetValueInput({ asset: asset, assetId: 0, assetAmount: uint256(amount), baseCurrency: 0 })
        );

        return (PRIMARY_FLAG, valueInUsd);
    }

    /**
     * @notice Decreases the exposure to an asset on withdrawal.
     * @param asset The contract address of the asset.
     * param assetId The Id of the asset.
     * @param amount The amount of tokens.
     * @dev Unsafe cast to uint128, it is assumed no more than 10**(20+decimals) tokens will ever be deposited.
     */
    function processDirectWithdrawal(address asset, uint256, uint256 amount) public virtual onlyMainReg {
        // Cache exposureLast.
        uint256 exposureLast = exposure[asset].exposure;

        exposureLast >= amount
            ? exposure[asset].exposure = uint128(exposureLast) - uint128(amount)
            : exposure[asset].exposure = 0;

        emit AssetExposureChanged(
            asset,
            uint128(exposureLast),
            exposureLast >= amount
                ? exposure[asset].exposure = uint128(exposureLast) - uint128(amount)
                : exposure[asset].exposure = 0
        );
    }

    /**
     * @notice Decreases the exposure to an asset on withdrawal.
     * @param asset The contract address of the asset.
     * param id The Id of the asset.
     * @param amount The amount of tokens.
     */
    function processIndirectWithdrawal(address asset, uint256, int256 amount)
        public
        virtual
        onlyMainReg
        returns (bool primaryFlag, uint256 valueInUsd)
    {
        // Cache exposureLast.
        uint256 exposureLast = exposure[asset].exposure;

        if (amount > 0) {
            exposureLast >= uint256(amount)
                ? exposure[asset].exposure = uint128(exposureLast) - uint128(uint256(amount))
                : exposure[asset].exposure = 0;
            emit AssetExposureChanged(
                asset,
                uint128(exposureLast),
                exposureLast >= uint256(amount)
                    ? exposure[asset].exposure = uint128(exposureLast) - uint128(uint256(amount))
                    : exposure[asset].exposure = 0
            );
        } else {
            uint256 amount_ = uint256(-amount);
            require(exposureLast + amount_ <= type(uint128).max, "APM_IE: Overflow");
            exposure[asset].exposure = uint128(exposureLast) - uint128(amount_);
            emit AssetExposureChanged(asset, uint128(exposureLast), uint128(exposureLast) - uint128(amount_));
        }

        // Get Value in Usd
        (valueInUsd,,) = getValue(
            IPricingModule.GetValueInput({ asset: asset, assetId: 0, assetAmount: uint256(-amount), baseCurrency: 0 })
        );

        return (PRIMARY_FLAG, valueInUsd);
    }
}
