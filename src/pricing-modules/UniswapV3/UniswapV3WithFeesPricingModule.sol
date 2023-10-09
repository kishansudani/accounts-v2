/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity 0.8.19;

import { DerivedPricingModule, IPricingModule } from "../AbstractDerivedPricingModule.sol";
import { IMainRegistry } from "../interfaces/IMainRegistry.sol";
import { INonfungiblePositionManager } from "./interfaces/INonfungiblePositionManager.sol";
import { IUniswapV3Pool } from "./interfaces/IUniswapV3Pool.sol";
import { IERC20 } from "./interfaces/IERC20.sol";
import { TickMath } from "./libraries/TickMath.sol";
import { FullMath } from "./libraries/FullMath.sol";
import { PoolAddress } from "./libraries/PoolAddress.sol";
import { FixedPoint96 } from "./libraries/FixedPoint96.sol";
import { FixedPoint128 } from "./libraries/FixedPoint128.sol";
import { LiquidityAmounts } from "./libraries/LiquidityAmounts.sol";
import { FixedPointMathLib } from "lib/solmate/src/utils/FixedPointMathLib.sol";
import { SafeCastLib } from "lib/solmate/src/utils/SafeCastLib.sol";

/**
 * @title Pricing Module for Uniswap V3 Liquidity Positions.
 * @author Pragma Labs
 * @notice The pricing logic and basic information for Uniswap V3 Liquidity Positions.
 * @dev The UniswapV3PricingModule will not price the LP-tokens via direct price oracles,
 * it will break down liquidity positions in the underlying tokens (ERC20s).
 * Only LP tokens for which the underlying tokens are allowed as collateral can be priced.
 * @dev No end-user should directly interact with the UniswapV3PricingModule, only the Main-registry,
 * or the contract owner.
 */
contract UniswapV3WithFeesPricingModule is DerivedPricingModule {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                STORAGE
    ////////////////////////////////////////////////////////////// */

    // The maximum difference between the upper or lower tick and the current tick (from 0.2x to 5x the current price).
    // Calculated as: (sqrt(1.0001))log(sqrt(5)) = 16095.2
    int24 public constant MAX_TICK_DIFFERENCE = 16_095;

    // Map asset => uniswapV3Factory.
    mapping(address => address) public assetToV3Factory;

    mapping(bytes32 assetKey => bytes32[] underlyingAssetKeys) internal assetToUnderlyingAssets;

    // Map asset => id => positionInformation.
    mapping(address => mapping(uint256 => Position)) internal positions;

    // Struct with information of a specific Liquidity Position.
    struct Position {
        address token0; // Token0 of the Liquidity Pool.
        address token1; // Token1 of the Liquidity Pool.
        int24 tickLower; // The lower tick of the liquidity position.
        int24 tickUpper; // The upper tick of the liquidity position.
        uint128 liquidity; // The liquidity per tick of the liquidity position.
    }

    /* //////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    /**
     * @param mainRegistry_ The contract address of the MainRegistry.
     * @param oracleHub_ The contract address of the OracleHub.
     * @param riskManager_ The address of the Risk Manager.
     * @dev AssetType for Uniswap V3 Liquidity Positions (ERC721) is 1.
     */
    constructor(address mainRegistry_, address oracleHub_, address riskManager_)
        DerivedPricingModule(mainRegistry_, oracleHub_, 1, riskManager_)
    { }

    /*///////////////////////////////////////////////////////////////
                        ASSET MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new asset to the UniswapV3PricingModule.
     * @param asset The contract address of the asset (also known as the NonfungiblePositionManager).
     * @dev Per protocol (eg. Uniswap V3 and its forks) there is a single asset,
     * and each liquidity position will have a different id.
     */
    function addAsset(address asset) external onlyOwner {
        require(!inPricingModule[asset], "PMUV3_AA: already added");

        inPricingModule[asset] = true;
        assetsInPricingModule.push(asset);

        assetToV3Factory[asset] = INonfungiblePositionManager(asset).factory();

        // Will revert in MainRegistry if asset can't be added.
        IMainRegistry(mainRegistry).addAsset(asset, assetType);
    }

    function _getUnderlyingAssets(bytes32 assetKey)
        internal
        view
        override
        returns (bytes32[] memory underlyingAssets)
    {
        underlyingAssets = assetToUnderlyingAssets[assetKey];
    }

    /*///////////////////////////////////////////////////////////////
                            ALLOW LIST
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks for a token address and the corresponding Id if it is allow-listed.
     * @param asset The contract address of the asset.
     * @param assetId The Id of the asset.
     * @return A boolean, indicating if the asset is whitelisted.
     */
    function isAllowListed(address asset, uint256 assetId) public view override returns (bool) {
        if (!inPricingModule[asset]) return false;

        try INonfungiblePositionManager(asset).positions(assetId) returns (
            uint96,
            address,
            address token0,
            address token1,
            uint24,
            int24,
            int24,
            uint128,
            uint256,
            uint256,
            uint128,
            uint128
        ) {
            address token0PricingModule = IMainRegistry(mainRegistry).getPricingModuleOfAsset(token0);
            address token1PricingModule = IMainRegistry(mainRegistry).getPricingModuleOfAsset(token1);
            if (token0PricingModule == address(0) || token1PricingModule == address(0)) {
                return false;
            } else {
                return IPricingModule(token0PricingModule).isAllowListed(token0, 0)
                    && IPricingModule(token0PricingModule).isAllowListed(token1, 0);
            }
        } catch {
            return false;
        }
    }

    /*///////////////////////////////////////////////////////////////
                          PRICING LOGIC
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the conversion rate of an asset to its underlying asset.
     * @param assetKey The unique identifier of the asset.
     * param underlyingAssetKeys The assets to which we have to get the conversion rate.
     * @return conversionRates The conversion rate of the asset to its underlying assets.
     */
    function _getConversionRates(bytes32 assetKey, bytes32[] memory)
        internal
        view
        override
        returns (uint256[] memory conversionRates)
    {
        (address asset, uint256 assetId) = _getAssetFromKey(assetKey);
        address factory = assetToV3Factory[asset];

        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            , // gas: cheaper to use uint256 instead of uint128.
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint256 tokensOwed0, // gas: cheaper to use uint256 instead of uint128.
            uint256 tokensOwed1 // gas: cheaper to use uint256 instead of uint128.
        ) = INonfungiblePositionManager(asset).positions(assetId);

        {
            (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
                _getFeeGrowthInside(factory, token0, token1, fee, tickLower, tickUpper);

            // Calculate the total amount of fees by adding the already realized fees (tokensOwed),
            // to the accumulated fees since the last time the position was updated:
            // (feeGrowthInsideCurrentX128 - feeGrowthInsideLastX128).
            // Fee calculations in NonfungiblePositionManager.sol overflow (without reverting) when
            // one or both terms, or their sum, is bigger than a uint128.
            // This is however much bigger than any realistic situation.

            // Add fees accumulated for each token per LP token.
            unchecked {
                tokensOwed0 +=
                    FullMath.mulDiv(feeGrowthInside0CurrentX128 - feeGrowthInside0LastX128, 1e18, FixedPoint128.Q128);
                tokensOwed1 +=
                    FullMath.mulDiv(feeGrowthInside1CurrentX128 - feeGrowthInside1LastX128, 1e18, FixedPoint128.Q128);
            }
        }

        uint256 principalAmountToken0;
        uint256 principalAmountToken1;
        {
            uint256 trustedPriceToken0 = IMainRegistry(mainRegistry).getUsdValue(
                GetValueInput({ asset: token0, assetId: 0, assetAmount: 1e18, baseCurrency: 0 })
            );

            uint256 trustedPriceToken1 = IMainRegistry(mainRegistry).getUsdValue(
                GetValueInput({ asset: token1, assetId: 0, assetAmount: 1e18, baseCurrency: 0 })
            );

            (principalAmountToken0, principalAmountToken1) =
                _getPrincipalAmounts(tickLower, tickUpper, 1e18, trustedPriceToken0, trustedPriceToken1);
        }

        // Add principal amount to fees
        tokensOwed0 += principalAmountToken0;
        tokensOwed1 += principalAmountToken1;

        conversionRates = new uint256[](2);
        conversionRates[0] = tokensOwed0;
        conversionRates[1] = tokensOwed1;
    }

    /**
     * @notice Returns the value of a Uniswap V3 Liquidity Range.
     * @param getValueInput A Struct with the input variables (avoid stack too deep).
     * - asset: The contract address of the asset.
     * - assetId: The Id of the range.
     * - assetAmount: The amount of assets.
     * - baseCurrency: The BaseCurrency in which the value is ideally denominated.
     * @return valueInUsd The value of the asset denominated in USD, with 18 Decimals precision.
     * @return collateralFactor The collateral factor of the asset for a given baseCurrency, with 2 decimals precision.
     * @return liquidationFactor The liquidation factor of the asset for a given baseCurrency, with 2 decimals precision.
     * @dev The UniswapV3PricingModule will always return the value denominated in USD.
     * @dev Uniswap Pools can be manipulated, we can't rely on the current price (or tick).
     * We use Chainlink oracles of the underlying assets to calculate the flashloan resistant price.
     */
    function getValue(IPricingModule.GetValueInput memory getValueInput)
        public
        view
        override
        returns (uint256 valueInUsd, uint256 collateralFactor, uint256 liquidationFactor)
    {
        // Use variables as much as possible in local context, to avoid stack too deep errors.
        address asset = getValueInput.asset;
        uint256 id = getValueInput.assetId;
        uint256 baseCurrency = getValueInput.baseCurrency;
        address token0;
        address token1;
        uint256 usdPriceToken0;
        uint256 usdPriceToken1;
        uint256 principal0;
        uint256 principal1;

        {
            int24 tickLower;
            int24 tickUpper;
            uint128 liquidity;
            (token0, token1, tickLower, tickUpper, liquidity) = _getPosition(asset, id);

            // We use the USD price per 10^18 tokens instead of the USD price per token to guarantee
            // sufficient precision.
            usdPriceToken0 = IMainRegistry(mainRegistry).getUsdValue(
                GetValueInput({ asset: token0, assetId: 0, assetAmount: 1e18, baseCurrency: 0 })
            );
            usdPriceToken1 = IMainRegistry(mainRegistry).getUsdValue(
                GetValueInput({ asset: token1, assetId: 0, assetAmount: 1e18, baseCurrency: 0 })
            );

            // If the Usd price of one of the tokens is 0, the LP-token will also have a value of 0.
            if (usdPriceToken0 == 0 || usdPriceToken1 == 0) return (0, 0, 0);

            // Calculate amount0 and amount1 of the principal (the actual liquidity position).
            (principal0, principal1) =
                _getPrincipalAmounts(tickLower, tickUpper, liquidity, usdPriceToken0, usdPriceToken1);
        }

        {
            // Calculate amount0 and amount1 of the accumulated fees.
            (uint256 fee0, uint256 fee1) = _getFeeAmounts(asset, id);

            // ToDo: fee should be capped to a max compared to principal to avoid circumventing caps via fees on new pools.

            // Calculate the total value in USD, since the USD price is per 10^18 tokens we have to divide by 10^18.
            unchecked {
                valueInUsd = usdPriceToken0.mulDivDown(principal0 + fee0, 1e18)
                    + usdPriceToken1.mulDivDown(principal1 + fee1, 1e18);
            }
        }

        {
            // Fetch the risk variables of the underlying tokens for the given baseCurrency.
            (uint256 collateralFactor0, uint256 liquidationFactor0) = IPricingModule(
                IMainRegistry(mainRegistry).getPricingModuleOfAsset(token0)
            ).getRiskVariables(token0, baseCurrency);
            (uint256 collateralFactor1, uint256 liquidationFactor1) = IPricingModule(
                IMainRegistry(mainRegistry).getPricingModuleOfAsset(token1)
            ).getRiskVariables(token1, baseCurrency);

            // We take the most conservative (lowest) factor of both underlying assets.
            // If one token loses in value compared to the other token, Liquidity Providers will be relatively more exposed
            // to the asset that loses value. This is especially true for Uniswap V3: when the current tick is outside of the
            // liquidity range the LP is fully exposed to a single asset.
            collateralFactor = collateralFactor0 < collateralFactor1 ? collateralFactor0 : collateralFactor1;
            liquidationFactor = liquidationFactor0 < liquidationFactor1 ? liquidationFactor0 : liquidationFactor1;
        }

        return (valueInUsd, collateralFactor, liquidationFactor);
    }

    /**
     * @notice Returns the position information.
     * @param asset The contract address of the asset.
     * @param id The Id of the asset.
     * @return token0 Token0 of the Liquidity Pool.
     * @return token1 Token1 of the Liquidity Pool.
     * @return tickLower The lower tick of the liquidity position.
     * @return tickUpper The upper tick of the liquidity position.
     * @return liquidity The liquidity per tick of the liquidity position.
     */
    function _getPosition(address asset, uint256 id)
        internal
        view
        returns (address token0, address token1, int24 tickLower, int24 tickUpper, uint128 liquidity)
    {
        liquidity = positions[asset][id].liquidity;

        if (liquidity > 0) {
            // For deposited assets, the information of the Liquidity Position is stored in the Pricing Module,
            // not fetched from the NonfungiblePositionManager.
            // Since liquidity of a position can be increased by a non-owner, the max exposure checks could otherwise be circumvented.
            token0 = positions[asset][id].token0;
            token1 = positions[asset][id].token1;
            tickLower = positions[asset][id].tickLower;
            tickUpper = positions[asset][id].tickUpper;
        } else {
            // Only used as an off-chain view function to return the value of a non deposited Liquidity Position.
            (,, token0, token1,, tickLower, tickUpper, liquidity,,,,) = INonfungiblePositionManager(asset).positions(id);
        }
    }

    /**
     * @notice Calculates the underlying token amounts of a liquidity position, given external trusted prices.
     * @param tickLower The lower tick of the liquidity position.
     * @param tickUpper The upper tick of the liquidity position.
     * @param priceToken0 The price of 10^18 tokens of token0 in USD, with 18 decimals precision.
     * @param priceToken1 The price of 10^18 tokens of token1 in USD, with 18 decimals precision.
     * @return amount0 The amount of underlying token0 tokens.
     * @return amount1 The amount of underlying token1 tokens.
     */
    function _getPrincipalAmounts(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 priceToken0,
        uint256 priceToken1
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        // Calculate the square root of the relative rate sqrt(token1/token0) from the trusted USD-price of both tokens.
        // sqrtPriceX96 is a binary fixed point number with 96 digits precision.
        uint160 sqrtPriceX96 = _getSqrtPriceX96(priceToken0, priceToken1);

        // Calculate amount0 and amount1 of the principal (the liquidity position without accumulated fees).
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity
        );
    }

    /**
     * @notice Calculates the sqrtPriceX96 (token1/token0) from trusted USD prices of both tokens.
     * @param priceToken0 The price of 10^18 tokens of token0 in USD, with 18 decimals precision.
     * @param priceToken1 The price of 10^18 tokens of token1 in USD, with 18 decimals precision.
     * @return sqrtPriceX96 The square root of the price (token1/token0), with 96 binary precision.
     * @dev The price in Uniswap V3 is defined as:
     * price = amountToken1/amountToken0.
     * The usdPriceToken is defined as: usdPriceToken = amountUsd/amountToken.
     * => amountToken = amountUsd/usdPriceToken.
     * Hence we can derive the Uniswap V3 price as:
     * price = (amountUsd/usdPriceToken1)/(amountUsd/usdPriceToken0) = usdPriceToken0/usdPriceToken1.
     */
    function _getSqrtPriceX96(uint256 priceToken0, uint256 priceToken1) internal pure returns (uint160 sqrtPriceX96) {
        // Both priceTokens have 18 decimals precision and result of division should also have 18 decimals precision.
        // -> multiply by 10**18
        uint256 priceXd18 = priceToken0.mulDivDown(1e18, priceToken1);
        // Square root of a number with 18 decimals precision has 9 decimals precision.
        uint256 sqrtPriceXd9 = FixedPointMathLib.sqrt(priceXd18);

        // Change sqrtPrice from a decimal fixed point number with 9 digits to a binary fixed point number with 96 digits.
        // Unsafe cast: Cast will only overflow when priceToken0/priceToken1 >= 2^128.
        sqrtPriceX96 = uint160((sqrtPriceXd9 << FixedPoint96.RESOLUTION) / 1e9);
    }

    /**
     * @notice Calculates the underlying token amounts of accrued fees, both collected as uncollected.
     * @param asset The contract address of the asset.
     * @param id The Id of the Liquidity Position.
     * @return amount0 The amount fees of underlying token0 tokens.
     * @return amount1 The amount of fees underlying token1 tokens.
     */
    function _getFeeAmounts(address asset, uint256 id) internal view returns (uint256 amount0, uint256 amount1) {
        address factory = assetToV3Factory[asset];
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint256 liquidity, // gas: cheaper to use uint256 instead of uint128.
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint256 tokensOwed0, // gas: cheaper to use uint256 instead of uint128.
            uint256 tokensOwed1 // gas: cheaper to use uint256 instead of uint128.
        ) = INonfungiblePositionManager(asset).positions(id);

        (uint256 feeGrowthInside0CurrentX128, uint256 feeGrowthInside1CurrentX128) =
            _getFeeGrowthInside(factory, token0, token1, fee, tickLower, tickUpper);

        // Calculate the total amount of fees by adding the already realized fees (tokensOwed),
        // to the accumulated fees since the last time the position was updated:
        // (feeGrowthInsideCurrentX128 - feeGrowthInsideLastX128) * liquidity.
        // Fee calculations in NonfungiblePositionManager.sol overflow (without reverting) when
        // one or both terms, or their sum, is bigger than a uint128.
        // This is however much bigger than any realistic situation.
        unchecked {
            amount0 = FullMath.mulDiv(
                feeGrowthInside0CurrentX128 - feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128
            ) + tokensOwed0;
            amount1 = FullMath.mulDiv(
                feeGrowthInside1CurrentX128 - feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128
            ) + tokensOwed1;
        }
    }

    /**
     * @notice Calculates the current fee growth inside the Liquidity Range.
     * @param factory The contract address of the pool factory.
     * @param token0 Token0 of the Liquidity Pool.
     * @param token1 Token1 of the Liquidity Pool.
     * @param fee The fee of the Liquidity Pool.
     * @param tickLower The lower tick of the liquidity position.
     * @param tickUpper The upper tick of the liquidity position.
     * @return feeGrowthInside0X128 The amount fees of underlying token0 tokens.
     * @return feeGrowthInside1X128 The amount of fees underlying token1 tokens.
     */
    function _getFeeGrowthInside(
        address factory,
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, token0, token1, fee));

        // To calculate the pending fees, the current tick has to be used, even if the pool would be unbalanced.
        (, int24 tickCurrent,,,,,) = pool.slot0();
        (,, uint256 lowerFeeGrowthOutside0X128, uint256 lowerFeeGrowthOutside1X128,,,,) = pool.ticks(tickLower);
        (,, uint256 upperFeeGrowthOutside0X128, uint256 upperFeeGrowthOutside1X128,,,,) = pool.ticks(tickUpper);

        // Calculate the fee growth inside of the Liquidity Range since the last time the position was updated.
        // feeGrowthInside can overflow (without reverting), as is the case in the Uniswap fee calculations.
        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 = lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else if (tickCurrent < tickUpper) {
                feeGrowthInside0X128 =
                    pool.feeGrowthGlobal0X128() - lowerFeeGrowthOutside0X128 - upperFeeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    pool.feeGrowthGlobal1X128() - lowerFeeGrowthOutside1X128 - upperFeeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 = upperFeeGrowthOutside0X128 - lowerFeeGrowthOutside0X128;
                feeGrowthInside1X128 = upperFeeGrowthOutside1X128 - lowerFeeGrowthOutside1X128;
            }
        }
    }

    /*///////////////////////////////////////////////////////////////
                    RISK VARIABLES MANAGEMENT
    ///////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the current tick from trusted USD prices of both tokens.
     * @param token0 The contract address of token0.
     * @param token1 The contract address of token1.
     * @return tickCurrent The current tick.
     */
    function _getTrustedTickCurrent(address token0, address token1) internal view returns (int256 tickCurrent) {
        // Get the pricing modules of the underlying assets
        address token0PricingModule = IMainRegistry(mainRegistry).getPricingModuleOfAsset(token0);
        address token1PricingModule = IMainRegistry(mainRegistry).getPricingModuleOfAsset(token1);

        // We use the USD price per 10^18 tokens instead of the USD price per token to guarantee
        // sufficient precision.
        (uint256 priceToken0,,) = IPricingModule(token0PricingModule).getValue(
            GetValueInput({ asset: token0, assetId: 0, assetAmount: 1e18, baseCurrency: 0 })
        );
        (uint256 priceToken1,,) = IPricingModule(token1PricingModule).getValue(
            GetValueInput({ asset: token1, assetId: 0, assetAmount: 1e18, baseCurrency: 0 })
        );

        uint160 sqrtPriceX96 = _getSqrtPriceX96(priceToken0, priceToken1);

        tickCurrent = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }

    /**
     * @notice Increases the exposure to an asset on deposit.
     * @param asset The contract address of the asset.
     * @param assetId The Id of the asset.
     * @param amount The amount of tokens.
     */
    function processDirectDeposit(address asset, uint256 assetId, uint256 amount) public override onlyMainReg {
        (,, address token0, address token1,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            INonfungiblePositionManager(asset).positions(assetId);

        require(liquidity > 0, "PMUV3_IE: 0 liquidity");

        // Since liquidity of a position can be increased by a non-owner, we have to store the liquidity during deposit.
        // Otherwise the max exposure checks can be circumvented.
        // TODO: gas optimization => more efficient to only store liquidity and get other info from nftPositionManager on _getPosition() ?
        positions[asset][assetId] = Position({
            token0: token0,
            token1: token1,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity
        });
        bytes32[] memory underlyingAssetKeys = new bytes32[](2);
        underlyingAssetKeys[0] = _getKeyFromAsset(token0, 0);
        underlyingAssetKeys[1] = _getKeyFromAsset(token1, 0);
        assetToUnderlyingAssets[_getKeyFromAsset(asset, assetId)] = underlyingAssetKeys;

        super.processDirectDeposit(asset, assetId, amount);
    }

    /**
     * @notice Increases the exposure to an underlying asset on deposit.
     * @param asset The contract address of the asset.
     * @param assetId The Id of the asset.
     * @param exposureUpperAssetToAsset The amount of exposure of the upper asset (asset in previous pricing module called) to the underlying asset.
     * @param deltaExposureUpperAssetToAsset The increase or decrease in exposure of the upper asset to the underlying asset since last update.
     */
    function processIndirectDeposit(
        address asset,
        uint256 assetId,
        uint256 exposureUpperAssetToAsset,
        int256 deltaExposureUpperAssetToAsset
    ) public override onlyMainReg returns (bool primaryFlag, uint256 usdValueExposureUpperAssetToAsset) {
        (,, address token0, address token1,, int24 tickLower, int24 tickUpper, uint128 liquidity,,,,) =
            INonfungiblePositionManager(asset).positions(assetId);

        require(liquidity > 0, "PMUV3_IE: 0 liquidity");

        // Since liquidity of a position can be increased by a non-owner, we have to store the liquidity during deposit.
        // Otherwise the max exposure checks can be circumvented.
        // TODO: gas optimization => more efficient to only store liquidity and get other info from nftPositionManager on _getPosition() ?
        positions[asset][assetId] = Position({
            token0: token0,
            token1: token1,
            tickLower: tickLower,
            tickUpper: tickUpper,
            liquidity: liquidity
        });
        bytes32[] memory underlyingAssetKeys = new bytes32[](2);
        underlyingAssetKeys[0] = _getKeyFromAsset(token0, 0);
        underlyingAssetKeys[1] = _getKeyFromAsset(token1, 0);
        assetToUnderlyingAssets[_getKeyFromAsset(asset, assetId)] = underlyingAssetKeys;

        (primaryFlag, usdValueExposureUpperAssetToAsset) =
            super.processIndirectDeposit(asset, assetId, exposureUpperAssetToAsset, deltaExposureUpperAssetToAsset);
    }
}
