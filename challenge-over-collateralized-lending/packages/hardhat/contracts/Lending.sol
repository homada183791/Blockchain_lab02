// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICorn {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address user) external view returns (uint256);
}

interface ICornDEX {
    function currentPrice() external view returns (uint256);
}

error Lending__InvalidAmount();
error Lending__UnsafePositionRatio();
error Lending__BorrowingFailed();
error Lending__RepayingFailed();
error Lending__TransferFailed();
error Lending__NotLiquidatable();
error Lending__InsufficientLiquidatorCorn();

contract Lending {
    event CollateralAdded(address indexed user, uint256 amount, uint256 price);
    event CollateralWithdrawn(address indexed user, uint256 amount, uint256 price);
    event AssetBorrowed(address indexed user, uint256 amount, uint256 price);
    event AssetRepaid(address indexed user, uint256 amount, uint256 price);
    event Liquidation(
        address indexed borrower,
        address indexed liquidator,
        uint256 collateralTaken,
        uint256 debtRepaid,
        uint256 price
    );

    uint256 public constant COLLATERAL_RATIO = 120; // 120%
    uint256 public constant LIQUIDATOR_REWARD = 10; // 10%

    ICorn private immutable i_corn;
    ICornDEX private immutable i_cornDEX;

    // ✅ MUST be public for tests (auto-getters)
    mapping(address => uint256) public s_userCollateral; // ETH
    mapping(address => uint256) public s_userBorrowed;   // CORN

    // ✅ IMPORTANT: tests/deploy pass args as [cornDEX, corn]
    constructor(address cornDEX, address corn) {
        i_cornDEX = ICornDEX(cornDEX);
        i_corn = ICorn(corn);
    }

    function addCollateral() public payable {
        if (msg.value == 0) revert Lending__InvalidAmount();
        s_userCollateral[msg.sender] += msg.value;
        emit CollateralAdded(msg.sender, msg.value, i_cornDEX.currentPrice());
    }

    function withdrawCollateral(uint256 amount) public {
        if (amount == 0 || s_userCollateral[msg.sender] < amount) {
            revert Lending__InvalidAmount();
        }

        s_userCollateral[msg.sender] -= amount;

        // Prevent unsafe withdrawals if user has debt
        if (s_userBorrowed[msg.sender] > 0) {
            _validatePosition(msg.sender);
        }

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) revert Lending__TransferFailed();

        emit CollateralWithdrawn(msg.sender, amount, i_cornDEX.currentPrice());
    }

    function borrowCorn(uint256 borrowAmount) public {
        if (borrowAmount == 0) revert Lending__InvalidAmount();

        s_userBorrowed[msg.sender] += borrowAmount;
        _validatePosition(msg.sender);

        bool success = i_corn.transfer(msg.sender, borrowAmount);
        if (!success) revert Lending__BorrowingFailed();

        emit AssetBorrowed(msg.sender, borrowAmount, i_cornDEX.currentPrice());
    }

    function repayCorn(uint256 repayAmount) public {
        if (repayAmount == 0 || repayAmount > s_userBorrowed[msg.sender]) {
            revert Lending__InvalidAmount();
        }

        s_userBorrowed[msg.sender] -= repayAmount;

        bool success = i_corn.transferFrom(msg.sender, address(this), repayAmount);
        if (!success) revert Lending__RepayingFailed();

        emit AssetRepaid(msg.sender, repayAmount, i_cornDEX.currentPrice());
    }

    function liquidate(address user) public {
        if (!isLiquidatable(user)) revert Lending__NotLiquidatable();

        uint256 userDebt = s_userBorrowed[user];
        if (i_corn.balanceOf(msg.sender) < userDebt) {
            revert Lending__InsufficientLiquidatorCorn();
        }

        uint256 userCollateral = s_userCollateral[user];
        uint256 collateralValue = calculateCollateralValue(user);

        // Pay debt
        i_corn.transferFrom(msg.sender, address(this), userDebt);
        s_userBorrowed[user] = 0;

        // Calculate collateral payout
        uint256 collateralPurchased = (userDebt * userCollateral) / collateralValue;
        uint256 reward = (collateralPurchased * LIQUIDATOR_REWARD) / 100;
        uint256 payout = collateralPurchased + reward;

        if (payout > userCollateral) payout = userCollateral;
        s_userCollateral[user] = userCollateral - payout;

        (bool success,) = payable(msg.sender).call{value: payout}("");
        if (!success) revert Lending__TransferFailed();

        emit Liquidation(user, msg.sender, payout, userDebt, i_cornDEX.currentPrice());
    }

    function calculateCollateralValue(address user) public view returns (uint256) {
        return (s_userCollateral[user] * i_cornDEX.currentPrice()) / 1e18;
    }

    function isLiquidatable(address user) public view returns (bool) {
        uint256 ratio = _calculatePositionRatio(user);
        return (ratio * 100) < COLLATERAL_RATIO * 1e18;
    }

    function _calculatePositionRatio(address user) internal view returns (uint256) {
        uint256 borrowed = s_userBorrowed[user];
        if (borrowed == 0) return type(uint256).max;
        return (calculateCollateralValue(user) * 1e18) / borrowed;
    }

    function _validatePosition(address user) internal view {
        if (isLiquidatable(user)) revert Lending__UnsafePositionRatio();
    }

    // Optional (side quest)
    function getMaxBorrowAmount(uint256 ethCollateralAmount) public view returns (uint256) {
        if (ethCollateralAmount == 0) return 0;
        uint256 value = (ethCollateralAmount * i_cornDEX.currentPrice()) / 1e18;
        return (value * 100) / COLLATERAL_RATIO;
    }

    receive() external payable {}
}
