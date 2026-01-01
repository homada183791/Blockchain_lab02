// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "./MyUSD.sol";
import { Oracle } from "./Oracle.sol";
import { MyUSDStaking } from "./MyUSDStaking.sol";

contract MyUSDEngine is Ownable {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error Engine__InvalidAmount();
    error Engine__UnsafePositionRatio();
    error Engine__InsufficientCollateral();
    error Engine__NotLiquidatable();
    error Engine__TransferFailed();
    error Engine__NotRateController();
    error Engine__InvalidBorrowRate(); // ✅ required by tests

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralAdded(address indexed user, uint256 amount, uint256 ethPrice);
    event CollateralWithdrawn(address indexed user, uint256 amount, uint256 ethPrice);

    event DebtSharesMinted(address indexed user, uint256 myUsdAmount, uint256 shares);
    event DebtSharesBurned(address indexed user, uint256 myUsdAmount, uint256 shares);

    event BorrowRateUpdated(uint256 newRate);

    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 collateralSeized,
        uint256 debtRepaid,
        uint256 ethPrice
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 private constant COLLATERAL_RATIO = 150; // 150%
    uint256 private constant LIQUIDATOR_REWARD = 10; // 10%
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PRECISION = 1e18;

    /*//////////////////////////////////////////////////////////////
                          IMMUTABLE REFERENCES
    //////////////////////////////////////////////////////////////*/
    MyUSD private immutable i_myUSD;
    Oracle private immutable i_oracle;
    MyUSDStaking private immutable i_staking;
    address private immutable i_rateController;

    /*//////////////////////////////////////////////////////////////
                        INTEREST / DEBT SYSTEM
    //////////////////////////////////////////////////////////////*/
    uint256 public borrowRate; // basis points (100 = 1%)
    uint256 public lastUpdateTime;
    uint256 public totalDebtShares;
    uint256 public debtExchangeRate; // shares → MyUSD

    /*//////////////////////////////////////////////////////////////
                            USER STATE
    //////////////////////////////////////////////////////////////*/
    mapping(address => uint256) public s_userCollateral; // ETH in wei
    mapping(address => uint256) public s_userDebtShares; // shares

    modifier onlyRateController() {
        if (msg.sender != i_rateController) revert Engine__NotRateController();
        _;
    }

    constructor(
        address oracle,
        address myUsd,
        address staking,
        address rateController
    ) Ownable(msg.sender) {
        i_oracle = Oracle(oracle);
        i_myUSD = MyUSD(myUsd);
        i_staking = MyUSDStaking(staking);
        i_rateController = rateController;

        lastUpdateTime = block.timestamp;
        debtExchangeRate = PRECISION; // start: 1 share = 1 MyUSD
    }

    /*//////////////////////////////////////////////////////////////
                        CHECKPOINT 2 – COLLATERAL
    //////////////////////////////////////////////////////////////*/
    function addCollateral() external payable {
        if (msg.value == 0) revert Engine__InvalidAmount();
        s_userCollateral[msg.sender] += msg.value;
        emit CollateralAdded(msg.sender, msg.value, i_oracle.getETHMyUSDPrice());
    }

    function calculateCollateralValue(address user) public view returns (uint256) {
        uint256 ethPrice = i_oracle.getETHMyUSDPrice(); // 1e18
        return (s_userCollateral[user] * ethPrice) / PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                        CHECKPOINT 3 – INTEREST
    //////////////////////////////////////////////////////////////*/
    function _getCurrentExchangeRate() internal view returns (uint256) {
        if (totalDebtShares == 0) return debtExchangeRate;

        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        if (timeElapsed == 0 || borrowRate == 0) return debtExchangeRate;

        uint256 totalDebt = (totalDebtShares * debtExchangeRate) / PRECISION;
        uint256 interest =
            (totalDebt * borrowRate * timeElapsed) / (SECONDS_PER_YEAR * 10000);

        return debtExchangeRate + (interest * PRECISION) / totalDebtShares;
    }

    function _accrueInterest() internal {
        if (totalDebtShares == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }
        debtExchangeRate = _getCurrentExchangeRate();
        lastUpdateTime = block.timestamp;
    }

    function _getMyUSDToShares(uint256 amount) internal view returns (uint256) {
        return (amount * PRECISION) / _getCurrentExchangeRate();
    }

    /*//////////////////////////////////////////////////////////////
                        CHECKPOINT 4 – MINT
    //////////////////////////////////////////////////////////////*/
    function getCurrentDebtValue(address user) public view returns (uint256) {
        if (s_userDebtShares[user] == 0) return 0;
        return (s_userDebtShares[user] * _getCurrentExchangeRate()) / PRECISION;
    }

    function calculatePositionRatio(address user) public view returns (uint256) {
        uint256 debt = getCurrentDebtValue(user);
        if (debt == 0) return type(uint256).max;
        return (calculateCollateralValue(user) * PRECISION) / debt;
    }

    function _validatePosition(address user) internal view {
        uint256 ratio = calculatePositionRatio(user);
        if ((ratio * 100) < COLLATERAL_RATIO * PRECISION) {
            revert Engine__UnsafePositionRatio();
        }
    }

    function mintMyUSD(uint256 amount) external {
        if (amount == 0) revert Engine__InvalidAmount();

        uint256 shares = _getMyUSDToShares(amount);
        s_userDebtShares[msg.sender] += shares;
        totalDebtShares += shares;

        _validatePosition(msg.sender);

        i_myUSD.mintTo(msg.sender, amount);
        emit DebtSharesMinted(msg.sender, amount, shares);
    }

    /*//////////////////////////////////////////////////////////////
                        CHECKPOINT 5 – RATE
    //////////////////////////////////////////////////////////////*/
    function setBorrowRate(uint256 newRate) external onlyRateController {
        // ✅ Tests require: borrowRate cannot be below savings rate
        // MyUSDStaking exposes savingsRate as a public uint (getter: savingsRate())
        if (newRate < i_staking.savingsRate()) revert Engine__InvalidBorrowRate();

        _accrueInterest();
        borrowRate = newRate;
        emit BorrowRateUpdated(newRate);
    }

    /*//////////////////////////////////////////////////////////////
                        CHECKPOINT 6 – REPAY / WITHDRAW
    //////////////////////////////////////////////////////////////*/
    function repayUpTo(uint256 amount) external {
        uint256 shares = _getMyUSDToShares(amount);

        if (shares > s_userDebtShares[msg.sender]) {
            shares = s_userDebtShares[msg.sender];
            amount = getCurrentDebtValue(msg.sender);
        }

        if (amount == 0 || i_myUSD.balanceOf(msg.sender) < amount) {
            revert MyUSD__InsufficientBalance();
        }
        if (i_myUSD.allowance(msg.sender, address(this)) < amount) {
            revert MyUSD__InsufficientAllowance();
        }

        s_userDebtShares[msg.sender] -= shares;
        totalDebtShares -= shares;

        i_myUSD.burnFrom(msg.sender, amount);
        emit DebtSharesBurned(msg.sender, amount, shares);
    }

    function withdrawCollateral(uint256 amount) external {
        if (amount == 0) revert Engine__InvalidAmount();
        if (s_userCollateral[msg.sender] < amount) revert Engine__InsufficientCollateral();

        s_userCollateral[msg.sender] -= amount;

        if (s_userDebtShares[msg.sender] > 0) {
            _validatePosition(msg.sender);
        }

        (bool ok,) = payable(msg.sender).call{ value: amount }("");
        if (!ok) revert Engine__TransferFailed();

        emit CollateralWithdrawn(msg.sender, amount, i_oracle.getETHMyUSDPrice());
    }

    /*//////////////////////////////////////////////////////////////
                        CHECKPOINT 7 – LIQUIDATION
    //////////////////////////////////////////////////////////////*/
    function isLiquidatable(address user) public view returns (bool) {
        return (calculatePositionRatio(user) * 100) < COLLATERAL_RATIO * PRECISION;
    }

    function liquidate(address user) external {
        if (!isLiquidatable(user)) revert Engine__NotLiquidatable();

        uint256 debt = getCurrentDebtValue(user);
        uint256 collateral = s_userCollateral[user];
        uint256 collateralValue = calculateCollateralValue(user);

        if (i_myUSD.balanceOf(msg.sender) < debt) revert MyUSD__InsufficientBalance();
        if (i_myUSD.allowance(msg.sender, address(this)) < debt) revert MyUSD__InsufficientAllowance();

        i_myUSD.burnFrom(msg.sender, debt);

        totalDebtShares -= s_userDebtShares[user];
        s_userDebtShares[user] = 0;

        uint256 collateralToCover = (debt * collateral) / collateralValue;
        uint256 reward = (collateralToCover * LIQUIDATOR_REWARD) / 100;
        uint256 seized = collateralToCover + reward;

        if (seized > collateral) seized = collateral;
        s_userCollateral[user] -= seized;

        (bool ok,) = payable(msg.sender).call{ value: seized }("");
        if (!ok) revert Engine__TransferFailed();

        emit Liquidation(user, msg.sender, seized, debt, i_oracle.getETHMyUSDPrice());
    }

    receive() external payable {}
}
