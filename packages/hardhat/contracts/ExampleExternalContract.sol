// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;  //Do not change the solidity version as it negativly impacts submission grading

contract ExampleExternalContract{

  bool public completed;
  address public master;
  address public stakingContractAddress;

  // Requires to be THE Master
  modifier onlyTHEMaster() {
    require(msg.sender == master, "You are NOT THE Master");
    _;
  }

  // Requires to be the staking contract address
  modifier onlyStakingContractAddress() {
    require(msg.sender == stakingContractAddress, "Not the staking contract address");
    _;
  }

  // Setter for the staking contract address
  function setStakingContractAddress(address _stakingContractAddress) public {
      stakingContractAddress = _stakingContractAddress;
  }

  // Setter for THE Master only possible by the staking contract address
  function setTHEMaster(address _master) public onlyStakingContractAddress{
      master = _master;
  }

  // To lock funds into this contract
  function lockFunds() public payable {

  }

  /*
  Allows THE Master to unlock funds and send it back to the staking contract address
  */
  function retrieveLockUpFunds() public onlyTHEMaster{
    uint256 contractBalance = address(this).balance;
    // Transfer all ETH via call! (not transfer) cc: https://solidity-by-example.org/sending-ether
    (bool sent, bytes memory data) = stakingContractAddress.call{value: contractBalance}("");
    require(sent, "RIP; withdrawal failed :( ");
  }

}
