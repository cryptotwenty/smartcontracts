import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

pragma solidity ^0.5.0;

contract FundMe {

    mapping (address => uint256) public investorAddress;
    
    uint256 public totalAmountFunded;

    //The investmentValue is supposed to be provided in wei
    function buyToken() public payable {
        investorAddress[msg.sender] += msg.value;
        totalAmountFunded += msg.value;
    }
    
    function getETHUSDRate public view returns(uint256) {
        AggregatorV3Interface feed = AggregatorV3Interface(0x01BE23585060835E02B77ef475b0Cc51aA1e0709)
        return feed
    }
    
}