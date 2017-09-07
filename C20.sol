pragma solidity 0.4.11;

import './StandardToken.sol';

contract C20 is StandardToken {

    // metadata
    string public name = "Crypto20";
    string public symbol = "C20";
    uint256 public decimals = 18;
    string public version = "7.0";

    uint256 public tokenCap = 86206896 * 10**18; // todo: test

    // crowdsale parameters
    uint256 public fundingStartBlock;
    uint256 public fundingEndBlock;

    address public vestingContract;
    bool private vestingSet = false;

    // root control
    address public fundWallet;
    // control of liquidity and limited control of updatePrice
    address public controlWallet;
    // time to wait between controlWallet price updates
    uint256 public waitTime = 5 hours;

    // Fundwallet address can set to true to halt investing due to emergency
    bool public halted = false;
    uint256 public previousUpdateTime = 0;
    // -- totalSupply defined in StandardToken
    // -- mapping to token balances done in StandardToken

    Price public currentPrice;

    struct Price { // tokensPerEth
      uint256 numerator;
      uint256 denominator;
    }

    struct Withdrawal {
      uint256 tokens;
      uint256 time; // time is the last price updated time (previousUpdateTime)
    }

    // map investor address to a withdrawal request
    mapping (address => Withdrawal) public withdrawals;
    // maps previousUpdateTime to the next price
    mapping (uint256 => Price) public prices;

    event Invest(address indexed investor, address indexed beneficiary, uint256 ethValue, uint256 amountTokens);
    event AllocatePresale(address indexed investor, uint256 amountTokens);
    event PriceUpdate(uint256 numerator, uint256 denominator);
    event AddLiquidity(uint256 ethAmount);
    event RemoveLiquidity(uint256 ethAmount);

    event WithdrawRequest(address indexed investor, uint256 amountTokens);
    event Withdraw(address indexed investor, uint256 amountTokens, uint256 etherAmount);

    function C20(address controlWalletInput, uint256 priceNumeratorInput, uint256 startBlockInput, uint256 endBlockInput) {
        require(priceNumeratorInput > 0);
        require(endBlockInput > startBlockInput);
        fundWallet = msg.sender;
        controlWallet = controlWalletInput;
        currentPrice = Price(priceNumeratorInput, 1000); // 1 token = 1 usd at ICO start
        fundingStartBlock = startBlockInput;
        fundingEndBlock = endBlockInput;
    }

    function setVestingContract(address vestingContractInput) {
      require(msg.sender == fundWallet);
      vestingContract = vestingContractInput;
      vestingSet = true;
    }

    // allows controlWallet to update the price within a time contstraint, allows fundWallet complete control
    function updatePrice(uint256 newNumerator) external {
        require(msg.sender == controlWallet || msg.sender == fundWallet);
        require(newNumerator > 0);
        if(msg.sender == controlWallet) {
            require(safeSub(now, waitTime) >= previousUpdateTime); // ensure enough time has passed
            uint256 percentage_diff = 0;
            if(newNumerator > currentPrice.numerator) {
              percentage_diff = safeMul(newNumerator, 100) / currentPrice.numerator;
              percentage_diff = safeSub(percentage_diff, 100);
              // controlWallet can only increase price by max 20% and only every waitTime
              require(percentage_diff <= 20);
            }
        }
        // either controlWallet command is compliant or transaction came from fundWallet
        currentPrice.numerator = newNumerator;
        // maps time to new Price
        prices[previousUpdateTime] = currentPrice;
        previousUpdateTime = now;
        PriceUpdate(newNumerator, currentPrice.denominator);
    }

    function updatePriceDenominator(uint256 newDenominator) {
        require(msg.sender==fundWallet);
        require(newDenominator > 0);
        currentPrice.denominator = newDenominator;
        // maps time to new Price
        prices[previousUpdateTime] = currentPrice;
        previousUpdateTime = now;
        PriceUpdate(currentPrice.numerator, newDenominator);
    }

    function allocateTokens(address investor, uint256 amountTokens) private {
        require(vestingSet);
        // 13% of total allocated for PR, Marketing, Team, Advisors
        uint256 developmentAllocation = safeMul(amountTokens, 149425287) / 1000000000; // todo: test new %
        // check that token cap is not exceeded
        uint256 newTokens = safeAdd(amountTokens, developmentAllocation);
        require(safeAdd(totalSupply, newTokens) <= tokenCap);
        // increase token supply, assign tokens to investor
        totalSupply = safeAdd(totalSupply, newTokens);
        balances[investor] = safeAdd(balances[investor], amountTokens);
        balances[vestingContract] = safeAdd(balances[vestingContract], developmentAllocation);
    }

    function invest() external payable {
        investTo(msg.sender);
    }

    function investTo(address investor) public payable {
        require(!halted);
        require(msg.value > 0);
        require(block.number >= fundingStartBlock && block.number < fundingEndBlock);
        uint256 tokensToBuy = safeMul(msg.value, currentPrice.numerator) / currentPrice.denominator;
        allocateTokens(investor, tokensToBuy);
        // send ether to fundWallet
        fundWallet.transfer(msg.value);
        Invest(msg.sender, investor, msg.value, tokensToBuy);
    }

    function allocatePresale(address investor, uint amountTokens) external {
        require(msg.sender == fundWallet);
        allocateTokens(investor, amountTokens);
        AllocatePresale(investor, amountTokens);
    }

    function requestWithdrawal(uint256 amountTokensToWithdraw) external {
        require (block.number > fundingEndBlock && amountTokensToWithdraw > 0);
        address investor = msg.sender;
        require(balanceOf(investor) >= amountTokensToWithdraw);
        require(withdrawals[investor].tokens == 0); // investor cannot have outstanding withdrawals
        balances[investor] = safeSub(balances[investor], amountTokensToWithdraw);
        withdrawals[investor] = Withdrawal({tokens: amountTokensToWithdraw, time: previousUpdateTime});
        WithdrawRequest(investor, amountTokensToWithdraw);
    }

    function withdraw() external {
      address investor = msg.sender;
      uint256 tokens = withdrawals[investor].tokens;
      require(tokens > 0); // investor must have requested a withdrawal
      uint256 requestTime = withdrawals[investor].time;
      // obtain the next price that was set after the request
      Price price = prices[requestTime];
      require(price.numerator > 0); // price must have been set
      uint256 withdrawValue = safeMul(tokens, price.denominator) / price.numerator;
      // if contract ethbal > then send + transfer tokens to fundWallet, otherwise give tokens back
      withdrawals[investor].tokens = 0;
      if(this.balance >= withdrawValue) {
        balances[fundWallet] = safeAdd(balances[fundWallet], tokens);
        investor.transfer(withdrawValue);
        Withdraw(investor, tokens, withdrawValue);
      } else {
        balances[investor] = safeAdd(balances[investor], tokens);
        Withdraw(investor, tokens, 0); // TODO: indicate a failed withdrawal
      }
    }

    function checkWithdrawValue(uint256 amountTokensToWithdraw) constant returns (uint256 etherValue) {
        require(amountTokensToWithdraw > 0);
        require(balanceOf(msg.sender) >= amountTokensToWithdraw);
        uint256 withdrawValue = safeMul(amountTokensToWithdraw, currentPrice.denominator) / currentPrice.numerator;
        require(this.balance >= withdrawValue); // todo: possibly return zero
        return withdrawValue;
    }

    // allow fundWallet or controlWallet to add ether to contract
    function addLiquidity() external payable {
        require(msg.sender == fundWallet || msg.sender == controlWallet);
        require(msg.value > 0);
        AddLiquidity(msg.value);
    }

    // allow fundWallet to remove ether from contract
    function removeLiquidity(uint256 amount) external {
        require(msg.sender == fundWallet || msg.sender == controlWallet);
        require(amount <= this.balance);
        fundWallet.transfer(amount);
        RemoveLiquidity(amount);
    }

    function changeFundWallet(address newFundWallet) external {
        require(msg.sender==fundWallet && newFundWallet != address(0));
        fundWallet = newFundWallet;
    }

    function changeControlWallet(address newControlWallet) external {
        require(msg.sender==fundWallet && newControlWallet != address(0));
        controlWallet = newControlWallet;
    }

    function changeWaitTime(uint256 newWaitTime) external {
        require(msg.sender==fundWallet);
        waitTime = newWaitTime;
    }

    // TODO: possibly remove
    function updateFundingStartBlock(uint256 newFundingStartBlock) {
        require(msg.sender==fundWallet);
        require(block.number < fundingStartBlock);
        fundingStartBlock = newFundingStartBlock;
    }
    // TODO: possibly remove
    function updateFundingEndBlock(uint256 newFundingEndBlock){
        require(msg.sender==fundWallet);
        require(block.number < fundingEndBlock);
        fundingEndBlock = newFundingEndBlock;
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
        require(false); // do nothing
    }

    function claimTokens(address _token) {
        require(msg.sender == fundWallet);
        Token token = Token(_token);
        uint256 balance = token.balanceOf(this);
        token.transfer(fundWallet, balance);
     }

    // prevent transfers until ICO end
    function transfer(address _to, uint256 _value) returns (bool success) {
        require (block.number > fundingEndBlock);
        return super.transfer(_to, _value);
    }
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        require (block.number > fundingEndBlock);
        return super.transferFrom(_from, _to, _value);
    }

}
