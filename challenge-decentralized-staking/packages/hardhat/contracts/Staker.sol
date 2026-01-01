// SPDX-License-Identifier: MIT
pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";

contract Staker {
    ExampleExternalContract public exampleExternalContract;

    // ====== REQUIRED STATE ======
    mapping(address => uint256) public balances;

    uint256 public constant threshold = 1 ether;
    uint256 public deadline = block.timestamp + 30 seconds;

    bool public openForWithdraw;
    bool public executed;

    event Stake(address indexed staker, uint256 amount);

    constructor(address exampleExternalContractAddress) {
        exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);
    }

    modifier notCompleted() {
        require(!exampleExternalContract.completed(), "Staking already completed");
        _;
    }

    // Collect funds in a payable `stake()` function and track individual `balances` with a mapping:
    function stake() public payable notCompleted {
        require(block.timestamp < deadline, "Deadline passed");
        require(msg.value > 0, "No ETH sent");

        balances[msg.sender] += msg.value;
        emit Stake(msg.sender, msg.value);
    }

    // After some `deadline` allow anyone to call an `execute()` function
    // If the deadline has passed and the threshold is met, it should call `exampleExternalContract.complete{value: address(this).balance}()`
    function execute() public notCompleted {
        require(block.timestamp >= deadline, "Deadline not reached");
        require(!executed, "Already executed");
        executed = true;

        if (address(this).balance >= threshold) {
            exampleExternalContract.complete{value: address(this).balance}();
        } else {
            openForWithdraw = true;
        }
    }

    // If the `threshold` was not met, allow everyone to call a `withdraw()` function to withdraw their balance
    function withdraw() public notCompleted {
        require(openForWithdraw, "Withdraw not open");

        uint256 bal = balances[msg.sender];
        require(bal > 0, "Nothing to withdraw");

        balances[msg.sender] = 0; // effects first
        (bool ok, ) = msg.sender.call{value: bal}("");
        require(ok, "Withdraw failed");
    }

    // Add a `timeLeft()` view function that returns the time left before the deadline for the frontend
    function timeLeft() public view returns (uint256) {
        if (block.timestamp >= deadline) return 0;
        return deadline - block.timestamp;
    }

    // Add the `receive()` special function that receives eth and calls stake()
    receive() external payable {
        stake();
    }
}
