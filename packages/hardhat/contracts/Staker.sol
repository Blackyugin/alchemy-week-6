// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";
import "solidity-interest-helper/contracts/Interest.sol";

contract Staker is DSMath {

  ExampleExternalContract public exampleExternalContract;
  address public exampleExternalContractAddress;

  mapping(address => uint256) public balances;
  mapping(address => uint256) public depositTimestamps;

  // Master
  address public master = 0xD6C501a60dF5354A312A24ef64f67008D2b4C195;

  // Variables for non-linear interest logic
  // min/max APY
  uint256 public minAPY = 0.5 ether;
  uint256 public maxAPY = 0.75 ether;

  // min/max APY by second
  uint256 public minAPYRateBySecond = 0.01 ether;
  uint256 public maxAPYRateBySecond = 0.05 ether;

  // Debug variables 
  uint256 public minPotentialAPY = 0 ether;
  uint256 public maxPotentialAPY = 0 ether;
  uint256 public nonce = 1;
  uint256 public rate = 0;
  uint256 public reward = 0 ether;
  uint256 public secondPass = 0;
  uint256 public individualBalance = 0 ether;
  uint256 public contractBalance = 0 ether;

  uint256 public withdrawalDeadline = block.timestamp + 45 seconds;
  uint256 public claimDeadline = block.timestamp + 90 seconds;
  uint256 public currentBlock = 0;

  // Events
  event Stake(address indexed sender, uint256 amount);
  event Received(address, uint);
  event Execute(address indexed sender, uint256 amount);

  // Modifiers
  /*
  Checks if the withdrawal period has been reached or not
  */
  modifier withdrawalDeadlineReached( bool requireReached ) {
    uint256 timeRemaining = withdrawalTimeLeft();
    if( requireReached ) {
      require(timeRemaining == 0, "Withdrawal period is not reached yet");
    } else {
      require(timeRemaining > 0, "Withdrawal period has been reached");
    }
    _;
  }

  /*
  Checks if the claim period has ended or not
  */
  modifier claimDeadlineReached( bool requireReached ) {
    uint256 timeRemaining = claimPeriodLeft();
    if( requireReached ) {
      require(timeRemaining == 0, "Claim deadline is not reached yet");
    } else {
      require(timeRemaining > 0, "Claim deadline has been reached");
    }
    _;
  }

  /*
  Requires that the contract only be completed once!
  */
  modifier notCompleted() {
    bool completed = exampleExternalContract.completed();
    require(!completed, "Stake already completed!");
    _;
  }

  // Requires to be THE Master
  modifier onlyTHEMaster() {
    require(msg.sender == master, "You are NOT THE Master");
    _;
  }

  constructor(address _exampleExternalContractAddress){
    exampleExternalContractAddress = _exampleExternalContractAddress;
    exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);

    // Make THE Master to control to lock/unlock funds
    exampleExternalContract.setStakingContractAddress(address(this));
    exampleExternalContract.setTHEMaster(master);
  }

  // Stake function for a user to stake ETH in our contract
  function stake() public payable withdrawalDeadlineReached(false) claimDeadlineReached(false){
    balances[msg.sender] = balances[msg.sender] + msg.value;
    individualBalance = balances[msg.sender];
    depositTimestamps[msg.sender] = block.timestamp;
    emit Stake(msg.sender, msg.value);
  }

  /*
  Use a random-ish keccak256 to take a value between a min/max
  We add an 'upside' depending of second pass
  More second pass = better chance to be in the 'top' max range
  */
  function randomAPY(uint256 _maxAPY, uint256 _minAPY) internal returns (uint) {
      // More you wait, better the APY
      nonce += mul(secondPass, 5);
      uint randomnumber = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))) % _maxAPY;
      randomnumber = randomnumber + _minAPY;
      return randomnumber;
  }

  /*
  Return the total rewards with interest included
  Interest are calculate randomly-'ish' using min / max range
  and depending of the time since first deposit
  */
  function rewardsAvailableForWithdraw(address _address) public returns (uint interest) {
    individualBalance = balances[_address];
    secondPass = (block.timestamp-depositTimestamps[_address]);

    Interest interestCalculator = new Interest();

    // Retrieve the min/max range adding to the initial min apy the rate by second
    minPotentialAPY = add(minAPY, mul(minAPYRateBySecond, secondPass));
    maxPotentialAPY = add(maxAPY, mul(maxAPYRateBySecond, secondPass));

    // Ramdomly-'ish' select a value in the range using an 'upside'
    rate = randomAPY(minPotentialAPY, maxPotentialAPY);
    uint rateByYear = interestCalculator.yearlyRateToRay(rate);

    interest = interestCalculator.accrueInterest(individualBalance, rateByYear, secondPass);
  }

  // Simulate withdraw to check debug variable in front
  function simulateWithdraw() public {
    individualBalance = rewardsAvailableForWithdraw(msg.sender);
  }

  /*
  Withdraw function for a user to remove their staked ETH inclusive
  of both principal and any accrued interest
  */
  function withdraw() public withdrawalDeadlineReached(true) claimDeadlineReached(false) notCompleted(){
    require(balances[msg.sender] > 0, "You have no balance to withdraw!");
    uint256 indBalanceRewards = uint256(rewardsAvailableForWithdraw(msg.sender));
    balances[msg.sender] = 0;

    // Transfer all ETH via call! (not transfer) cc: https://solidity-by-example.org/sending-ether
    (bool sent, bytes memory data) = msg.sender.call{value: indBalanceRewards}("");
    require(sent, "RIP; withdrawal failed :( ");
  }

  /*
  Allows only THE Master to lock funds into the external contract
  past the defined withdrawal period
  */
  function lockFunds() public onlyTHEMaster claimDeadlineReached(true){
    uint256 contractBalance = address(this).balance;
    exampleExternalContract.lockFunds{value: address(this).balance}();
  }

  /*
  READ-ONLY function to calculate the time remaining before the minimum staking period has passed
  */
  function withdrawalTimeLeft() public view returns (uint256 withdrawalTimeLeft) {
    if( block.timestamp >= withdrawalDeadline) {
      return (0);
    } else {
      return (withdrawalDeadline - block.timestamp);
    }
  }

  /*
  READ-ONLY function to calculate the time remaining before the minimum staking period has passed
  */
  function claimPeriodLeft() public view returns (uint256 claimPeriodLeft) {
    if( block.timestamp >= claimDeadline) {
      return (0);
    } else {
      return (claimDeadline - block.timestamp);
    }
  }

  /*
  Time to "kill-time" on our local testnet
  */
  function killTime() public {
    currentBlock = block.timestamp;
  }

  /*
  \Function for our smart contract to receive ETH
  cc: https://docs.soliditylang.org/en/latest/contracts.html#receive-ether-function
  */
  receive() external payable {
      emit Received(msg.sender, msg.value);
  }

}