pragma solidity 0.4.11;

import './StandardToken.sol';

contract C20 is StandardToken{

    // metadata
    string public name = "Crypto20";
    string public symbol = "C20";
    uint public decimals = 18;
    string public version = "4.0";
    // token price
    uint public tokensPerEth_N = 220000; // 1 token ~ 1 usd
    uint public tokensPerEth_D = 1000; // defines price tracking resolution (currently 0.1%)

    // crowdsale parameters
    uint public fundingStartBlock;
    uint public fundingEndBlock;

    // root control
    address public fundWallet;
    // control of updatePrice and increaseLiquidity
    address public controlWallet;
    // blocks to wait between controlWallet price updates
    uint public waitBlocks = 1000;

    // Fundwallet address can set to true to halt investing due to emergency
    bool public halted = false;
    uint public previousUpdatePriceBlock = 0;
    // -- totalSupply defined in StandardToken
    // -- mapping to token balances done in StandardToken

    event Invest(address indexed investor, address indexed beneficiary, uint ethValue, uint amountTokens);
    event Withdraw(address indexed investor, uint ethValue, uint amountTokens);
    event PriceUpdated(uint tokensPerEth_N);
    event AddedLiquidity(uint ethAmount);
    event RemovedLiquidity(uint ethAmount);

    function C20(address controlWalletInput, uint tokensPerEth_N_input, uint startBlockInput, uint endBlockInput){
        fundWallet = msg.sender;
        controlWallet = controlWalletInput;
        tokensPerEth_N = tokensPerEth_N_input;
        fundingStartBlock = startBlockInput;
        fundingEndBlock = endBlockInput;
    }

    // post ICO, allows controlWallet to update the price within a time contstraint, allows fundWallet complete control
    function updatePrice(uint tokensPerEth_N_input) external {
        require(msg.sender == controlWallet || msg.sender == fundWallet);
        require(tokensPerEth_N_input > 0);
        // locks price during ICO
        require(block.number >= fundingEndBlock);
        // controlWallet can only update price 1000 blocks after previous update, and constrained by max 20% increase
        if(msg.sender == controlWallet){
            require((block.number - waitBlocks) >= previousUpdatePriceBlock);
            uint percentage_diff = 0;
            if(tokensPerEth_N_input > tokensPerEth_N){
              percentage_diff = (tokensPerEth_N_input*100) / tokensPerEth_N;
              percentage_diff = safeSub(percentage_diff, 100);
            }
            // controlWallet can only increase price by max 20% and only every waitBlocks blocks
            require(percentage_diff <= 20);
            tokensPerEth_N = tokensPerEth_N_input;
        }
        // fundWallet is unconstrained
        if(msg.sender == fundWallet){
            tokensPerEth_N = tokensPerEth_N_input;
        }
        previousUpdatePriceBlock = block.number;
        PriceUpdated(tokensPerEth_N_input);
    }

    function invest() external payable{
        investTo(msg.sender);
    }

    function investTo(address investor) public payable {
        require(!halted);
        require(msg.value > 0);
        require(block.number >= fundingStartBlock && block.number <= fundingEndBlock);
        uint tokensToBuy = safeMul(msg.value, tokensPerEth_N) / tokensPerEth_D;
        // 12.5% allocated for PR and Dev
        uint developmentAllocation = tokensToBuy / 8;
        uint investerAllocation = safeSub(tokensToBuy, developmentAllocation);
        assert (safeAdd(developmentAllocation, investerAllocation) == tokensToBuy);
        // increase token supply, assign tokens to investor
        totalSupply = safeAdd(totalSupply, tokensToBuy);
        balances[investor] = safeAdd(balances[investor], investerAllocation);
        balances[fundWallet] = safeAdd(balances[fundWallet], developmentAllocation);
        // send ether to fundWallet
        fundWallet.transfer(msg.value);
        Invest(msg.sender, investor, msg.value, investerAllocation);
    }

    // allows investors to withdraw ether based on current token to ether rate
    function withdraw(uint amountTokensToWithdraw) external {
        // amountTokensToWithdraw is specified in smallest units
        // prevent withdrawal before ICO end
        require (block.number >= fundingEndBlock || msg.sender == fundWallet);
        require(balanceOf(msg.sender) >= amountTokensToWithdraw);
        // obtain ether value
        uint withdrawValue = safeMul(amountTokensToWithdraw, tokensPerEth_D) / tokensPerEth_N;
        require (this.balance >= withdrawValue);
        address investor = msg.sender;
        // transfer investor tokens to fundWallet
        balances[investor] = safeSub(balances[investor], amountTokensToWithdraw);
        balances[fundWallet] = safeAdd(balances[fundWallet], amountTokensToWithdraw);
        // send ether to investor
        investor.transfer(withdrawValue);
        Withdraw(investor, withdrawValue, amountTokensToWithdraw);
    }

    function checkWithdrawValue(uint amountTokensToWithdraw) external constant returns (uint etherValue){
        require(balanceOf(msg.sender) >= amountTokensToWithdraw);
        uint withdrawValue = safeMul(amountTokensToWithdraw, tokensPerEth_D) / tokensPerEth_N;
        if (this.balance < withdrawValue) return 0;
        return withdrawValue;
    }

    // allow fundWallet or controlWallet to add ether to contract
    function addLiquidity() external payable{
        require(msg.sender == fundWallet || msg.sender == controlWallet);
        require(msg.value > 0);
        AddedLiquidity(msg.value);
    }

    // allow fundWallet to remove ether from contract
    function removeLiquidity(uint amount) external {
        require(msg.sender == fundWallet);
        require(amount <= this.balance);
        fundWallet.transfer(amount);
        RemovedLiquidity(amount);
    }

    function changeFundWallet(address newFundWallet) external {
        require(msg.sender==fundWallet);
        fundWallet = newFundWallet;
    }
    function changeControlWallet(address newControlWallet) external{
        require(msg.sender==fundWallet);
        controlWallet = newControlWallet;
    }

    function changeWaitBlocks(uint newWaitBlocks) external{
        require(msg.sender==fundWallet);
        waitBlocks = newWaitBlocks;
    }

    function updateFundingStartBlock(uint newFundingStartBlock){
        require(msg.sender==fundWallet);
        require(block.number < fundingStartBlock);
        fundingStartBlock = newFundingStartBlock;
    }
    function updateFundingEndBlock(uint newFundingEndBlock){
        require(msg.sender==fundWallet);
        require(block.number < fundingEndBlock);
        fundingEndBlock = newFundingEndBlock;
    }

    function changeTokensPerEthDenominator(uint newTokensPerEth_D){
        require(msg.sender==fundWallet);
        require(newTokensPerEth_D > 0);
        // locks price during ICO
        require(block.number >= fundingEndBlock);
        tokensPerEth_D = newTokensPerEth_D;
    }

    function halt() external {
        require(msg.sender==fundWallet);
        halted = true;
    }
    function unhalt() external {
        require(msg.sender==fundWallet);
        halted = false;
    }

    //fallback function
    function(){
        // do nothing
        require(false);
    }

    // prevent transfers until ICO end
    function transfer(address _to, uint256 _value) returns (bool success) {
        require (block.number >= fundingEndBlock || msg.sender==fundWallet);
        return super.transfer(_to, _value);
    }
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        require (block.number >= fundingEndBlock || msg.sender==fundWallet);
        return super.transferFrom(_from, _to, _value);
    }
}
