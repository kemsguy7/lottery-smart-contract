// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title  A model Raffle Contract
 * @author  Matthew Idungafa
 * @notice  This contract is for creating a sample raffle contract
 * @dev Implemnts Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();

    /* Type declarations */
    enum RaffleState {
        OPEN, // 0
        CALCULATING //1
        //
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval; // This is the time that will elapse before a winner is automatically picked
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    address payable[] private s_players; // s_ for storage variables
    bytes32 private immutable i_gasLane;
    uint256 private s_lastTimeStamp; // s_ for storage(state)
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callBackGasLimit;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner); //indexed is used to make the event searchable

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        // This is the constructor of the VRFConsumerBaseV2 contract that we are inheriting from
        //gaslane is the keyhash
        i_entranceFee = entranceFee;
        i_interval = interval; // This is the time that will elapse before a winner is automatically picked
        i_gasLane = gasLane;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator); //typecasting this address to the interface
        s_lastTimeStamp = block.timestamp;
        i_callBackGasLimit = callbackGasLimit;

        i_subscriptionId = subscriptionId;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() public payable {
        // require(msg.value > i_entranceFee, "Not enough ETH to enter raffle"); //not gas efficient
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender)); //making this payable so players can recieve eth

        /* 
            Events:
            1. Makes migration easier
            2. Makes Front end "indexing easier"
        */
        emit EnteredRaffle(msg.sender);
    }

    // When is the winner suppoed to be picked?
    /**
     * 
     * @dev This is the function that the Chainlink automation nodes call to 
     * see if it's time to perform and upkeep
     * The following should be true for this to return true:
     * 1. The time interval has passed between raffle runs
     * 2. The raffle is in the OPEN state
     * 3. The contract has ETH (aka, players)
     * 4. (Implicit) The subscription is funded with LINK 

     */

    function checkUpkeep(
        bytes memory /* checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // 1. Get a random number
    // 2. Use the random number to pick a player
    // 3. Be automatically called
    // 4. When we're picking a winner , users are not allowed to enter a raffle
    function pickWinner() external {
        //the system is to pick a winner automatically after a lot of time has passed
        // check to see if enough time has passed

        if ((block.timestamp - s_lastTimeStamp) < i_interval) {
            // check if enough time has passed
            revert();
        }
        // 1. Reques the RNG
        // 2. Get the random number
        s_raffleState = RaffleState.CALCULATING; // We are now calculating the winner so people cannot place their bets
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callBackGasLimit,
            NUM_WORDS
        );
    }

    // CEI: Check-Effects-Interactions
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        // s_players =  10
        // rng = 12
        // 12 % 10 = 2

        //Do your checks first
        // Effects (Our own contracts)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner; //store the winner
        s_raffleState = RaffleState.OPEN; //open the raffle again

        // we don't want new players to get into a new game for free, so we empty the players array
        s_players = new address payable[](0); //reset the players array to 0
        s_lastTimeStamp = block.timestamp; //restart the clock over

        // Interactions (Other contracts)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed(); //revert if the transfer fails
        }

        emit PickedWinner(winner); //emit the winner picked log with the most recent winner
    }

    /** Getter Function **/
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
