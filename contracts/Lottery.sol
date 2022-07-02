// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

contract Lottery is VRFConsumerBase, Ownable {
    address payable[] public players;
    address payable public recentWinner;
    uint256 public randomness;
    uint256 public usdEntryFee;
    AggregatorV3Interface internal ethUsdPriceFeed;
    enum LOTTERY_STATE {
        OPEN, //1
        CLOSED, //2
        CALCULATING_WINNER //3
    }
    LOTTERY_STATE public lottery_state;
    uint256 public fee;
    bytes32 public keyhash;
    event RequestedRandomness(bytes32 requestId);

    constructor(
        address _priceFeedAddress, 
        address _vrfCoordinator, 
        address _link,
        uint256 _fee,
        bytes32 _keyhash
    ) 
        public 
        VRFConsumerBase(_vrfCoordinator, _link) 
    {
        usdEntryFee = 50 * (10**18);
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);
        lottery_state = LOTTERY_STATE.CLOSED;
        fee = _fee;
        keyhash = _keyhash;
    }

    function enter() public payable {
        require(lottery_state == LOTTERY_STATE.OPEN);
        // $50 minimum
        require(msg.value >= getEntranceFee(), "Not enough ETH!");
        players.push(msg.sender);
    }

    function getEntranceFee() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        uint256 adjustedPrice = uint256(price) * 10**10; // 18 decimals, like documentation shows
        // $50, $2,000 / ETH
        // 50 / 2,000
        // 50 * 100000 / 2000
        uint256 costToEnter = (usdEntryFee * 10**18) / adjustedPrice;
        return costToEnter;
    }

    function startLottery() public onlyOwner {
        require(
            lottery_state == LOTTERY_STATE.CLOSED, 
            "Can't start a new lottery yet!"
        );
        lottery_state = LOTTERY_STATE.OPEN;
    }

    // Request and Receive
    // 1st transaction requests the data
    // 2nd Callback transaction, the chainlink node returns the data to this contract with fulfillRandomness()
    function endLottery() public onlyOwner {
        // uint256(
        //     keccack256(
        //         abi.encodePacked(
        //             nonce, // transaction number, nonce, is very predictable
        //             msg.sender,  // predictable
        //             block.difficulty, // can actually be manipulated by miners!
        //             block.timestamp // highly predictable
        //         )
        //     )
        // ) % players.length;
        lottery_state = LOTTERY_STATE.CALCULATING_WINNER;
        // this returns a bytes32 called requestId
        bytes32 requestId = requestRandomness(keyhash, fee);
        emit RequestedRandomness(requestId);
    }

    // Internal because chainlink node calls the VRF coordinator and then the VRF coordinator calls fulfill randomness
    function fulfillRandomness(bytes32 _requestId, uint256 _randomness) internal override {
        require(lottery_state == LOTTERY_STATE.CALCULATING_WINNER, "You are't there yet!");
        require(_randomness > 0, "random-not-found");
        uint256 indexOfWinner = _randomness % players.length;
        // 7 players
        // 22 
        // 22 % 7 
        // 7 * 3 = 21
        // number never goes higher than the number of players
        recentWinner = players[indexOfWinner];
        recentWinner.transfer(address(this).balance);
        // Reset!

        players = new address payable[](0);
        lottery_state = LOTTERY_STATE.CLOSED;
        randomness = _randomness;
    }
}