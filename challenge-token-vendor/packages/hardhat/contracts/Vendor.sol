// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Vendor is Ownable {
    IERC20 public immutable yourToken;
    uint256 public constant tokensPerEth = 100;

    event BuyTokens(address indexed buyer, uint256 amountOfETH, uint256 amountOfTokens);
    event SellTokens(address indexed seller, uint256 amountOfTokens, uint256 amountOfETH);
    event Withdraw(address indexed owner, uint256 amountOfETH);

    constructor(address tokenAddress) Ownable(msg.sender) {
        require(tokenAddress != address(0), "tokenAddress=0");
        yourToken = IERC20(tokenAddress);
    }

    // Mua token bằng ETH
    function buyTokens() external payable {
        require(msg.value > 0, "Send ETH");

        // 1 ETH -> 100 tokens
        // msg.value đang là wei ETH, tokens có 18 decimals
        // amountTokens sẽ ra đúng wei-token (ví dụ 0.1 ETH => 10e18 token)
        uint256 amountTokens = msg.value * tokensPerEth;

        bool ok = yourToken.transfer(msg.sender, amountTokens);
        require(ok, "Token transfer failed");

        emit BuyTokens(msg.sender, msg.value, amountTokens);
    }

    // Bán token lại cho Vendor để nhận ETH
    // Lưu ý: user phải approve trước
    function sellTokens(uint256 amountTokens) external {
        require(amountTokens > 0, "Amount=0");

        // 100 tokens -> 1 ETH
        // amountTokens là wei-token, chia cho 100 sẽ ra wei-ETH
        uint256 amountETH = amountTokens / tokensPerEth;
        require(amountETH > 0, "Too few tokens");
        require(address(this).balance >= amountETH, "Vendor out of ETH");

        bool ok = yourToken.transferFrom(msg.sender, address(this), amountTokens);
        require(ok, "transferFrom failed");

        (bool sent, ) = payable(msg.sender).call{value: amountETH}("");
        require(sent, "ETH transfer failed");

        emit SellTokens(msg.sender, amountTokens, amountETH);
    }

    // Owner rút toàn bộ ETH
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        require(bal > 0, "No ETH");

        (bool ok, ) = payable(owner()).call{value: bal}("");
        require(ok, "Withdraw failed");

        emit Withdraw(owner(), bal);
    }

    receive() external payable {}
}
