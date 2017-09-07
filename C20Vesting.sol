pragma solidity 0.4.11;

import './Token.sol';
import './SafeMath.sol';

/**
 * @title C20Vesting
 * @dev C20Vesting is a token holder contract that allows the specified beneficiary
 * to claim stored tokens after 6 month intervals
*/
 contract C20Vesting is SafeMath {

   address public beneficiary;

   uint256 public fundingEndBlock;

   bool private initClaim = false; // state tracking variables

   uint256 public firstRelease; // vesting times
   bool private firstDone = false;
   uint256 public secondRelease;
   bool private secondDone = false;
   uint256 public thirdRelease;
   bool private thirdDone = false;
   uint256 public fourthRelease;

   Token public ERC20Token; // ERC20 basic token contract to hold

   function C20Vesting(address _token, uint256 fundingEndBlockInput) {
     beneficiary = msg.sender;
     fundingEndBlock = fundingEndBlockInput;
     ERC20Token = Token(_token);
   }

    function updateToken(address tokenAddressInput) external {
       require(msg.sender == beneficiary);
       ERC20Token = Token(tokenAddressInput);
    }

   function changeBeneficiary(address newBeneficiary) external {
     require(msg.sender == beneficiary);
     beneficiary = newBeneficiary;
   }

   function checkBalance() constant returns (uint256 tokenBalance){
     return ERC20Token.balanceOf(this);
   }

   // in total 15% of C20 tokens will be sent to this contract

   // EXPENSE ALLOCATION: 7.5%                      | TEAM ALLOCATION: 7.5% (vest over 2 years)
   //   1% - ICO bonus                              | initalPayment: 1.5%
   //   3% - Marketing (2.5% 8760, 0.5% BLOCK512)   | firstRelease: 1.5%
   //   1% - Security (BLOCK512)                    | secondRelease: 1.5%
   //   2% - legal                                  | thirdRelease: 1.5%
   //   0.5% - Advisors                             | fourthRelease: 1.5%
   // initial claim is tot expenses + initial team payment
   // initial claim is thus (7.5 + 1.5)/15 = 60% of C20 tokens sent here
   // each other release (for team) is 10% of tokens sent here

   function claim() external {
     require(msg.sender == beneficiary);
     require(block.number > fundingEndBlock);

     uint256 balance = ERC20Token.balanceOf(this);
     uint256 amountToTransfer;

     if(!initClaim){
        firstRelease = now + 26 weeks; // assign 4 claiming times
        secondRelease = firstRelease + 26 weeks;
        thirdRelease = secondRelease + 26 weeks;
        fourthRelease = thirdRelease + 26 weeks;

        amountToTransfer = safeMul(balance, 60) / 100;
        ERC20Token.transfer(beneficiary, amountToTransfer); // 40% tokens left
        initClaim = true;
     } else if(now > firstRelease && !firstDone){
       amountToTransfer = balance / 4;
       ERC20Token.transfer(beneficiary, amountToTransfer); // 30% tokens left
       firstDone = true;
     } else if(now > secondRelease && !secondDone){
       amountToTransfer = balance / 3;
       ERC20Token.transfer(beneficiary, amountToTransfer); // 20% tokens left
       secondDone = true;
     } else if(now > thirdRelease && !thirdDone){
       amountToTransfer = balance / 2;
       ERC20Token.transfer(beneficiary, amountToTransfer); // 10% tokens left
       thirdDone = true;
     } else if(now > fourthRelease){ // allow transfer of all remaining
       ERC20Token.transfer(beneficiary, balance);
     } else {
       require(false); //todo: is this preferable to throw?
     }

   }

 }
