pragma solidity 0.4.11;

import './StandardToken.sol';

contract C20 is StandardToken {

    // FIELDS

    string public name = "Crypto20";
    string public symbol = "C20";
    uint256 public decimals = 18;
    string public version = "8.0";

    uint256 public tokenCap = 86206896 * 10**18; // possibly have tokenIssuanceCap and set to 75 mil

    // crowdsale parameters
    uint256 public fundingStartBlock;
    uint256 public fundingEndBlock;

    // vesting fields
    address public vestingContract;
    bool private vestingSet = false;

    // root control
    address public fundWallet;
    // control of liquidity and limited control of updatePrice
    address public controlWallet;
    // time to wait between controlWallet price updates
    uint256 public waitTime = 5 hours;

    // fundWallet controlled state variables
    // halted: halt investing due to emergency, tradeable: signal that assets have been acquired
    bool public halted = false;
    bool public tradeable = false;

    // -- totalSupply defined in StandardToken
    // -- mapping to token balances done in StandardToken

    uint256 public previousUpdateTime = 0;
    Price public currentPrice;
    uint256 public minInvestment = 0.04 ether;

    // map investor address to a withdrawal request
    mapping (address => Withdrawal) public withdrawals;
    // maps previousUpdateTime to the next price
    mapping (uint256 => Price) public prices;
    // maps addresses
    mapping (address => bool ) public whitelist;

    // TYPES

    struct Price { // tokensPerEth
        uint256 numerator;
        uint256 denominator;
    }

    struct Withdrawal {
        uint256 tokens;
        uint256 time; // time for each withdrawal is set to the previousUpdateTime
    }

    // EVENTS

    event Invest(address indexed investor, address indexed beneficiary, uint256 ethValue, uint256 amountTokens);
    event AllocatePresale(address indexed investor, uint256 amountTokens);
    event Whitelist(address indexed investor);
    event PriceUpdate(uint256 numerator, uint256 denominator);
    event AddLiquidity(uint256 ethAmount);
    event RemoveLiquidity(uint256 ethAmount);
    event WithdrawRequest(address indexed investor, uint256 amountTokens);
    event Withdraw(address indexed investor, uint256 amountTokens, uint256 etherAmount);

    // MODIFIERS

    modifier isTradeable { // exempt vestingContract and fundWallet to allow dev allocations
        require(tradeable || msg.sender == fundWallet || msg.sender == vestingContract);
        _;
    }

    modifier onlyWhitelist {
        require(whitelist[msg.sender]);
        _;
    }

    modifier onlyFundWallet {
        require(msg.sender == fundWallet);
        _;
    }

    modifier onlyManagingWallets {
        require(msg.sender == controlWallet || msg.sender == fundWallet);
        _;
    }

    modifier only_if_controlWallet {
        if (msg.sender == controlWallet) _;
    }
    modifier require_waited {
        require(safeSub(now, waitTime) >= previousUpdateTime);
        _;
    }
    modifier only_if_increase (uint256 newNumerator) {
        if (newNumerator > currentPrice.numerator) _;
    }

    modifier only_if_bal_greater_equal (uint256 withdrawValue) {
        if (this.balance >= withdrawValue) _;
    }
    modifier only_if_bal_less (uint256 withdrawValue) {
        if (this.balance < withdrawValue) _;
    }

    // CONSTRUCTOR

    function C20(address controlWalletInput, uint256 priceNumeratorInput, uint256 startBlockInput, uint256 endBlockInput) {
        require(controlWalletInput != address(0));
        require(priceNumeratorInput > 0);
        /*require(block.number <= startBlockInput);*/
        require(endBlockInput > startBlockInput);
        fundWallet = msg.sender;
        controlWallet = controlWalletInput;
        whitelist[fundWallet] = true;
        whitelist[controlWallet] = true;
        currentPrice = Price(priceNumeratorInput, 1000); // 1 token = 1 usd at ICO start
        fundingStartBlock = startBlockInput;
        fundingEndBlock = endBlockInput;
        previousUpdateTime = now;
    }

    // METHODS

    function setVestingContract(address vestingContractInput) external onlyFundWallet {
        require(vestingContractInput != address(0));
        vestingContract = vestingContractInput;
        whitelist[vestingContract] = true;
        vestingSet = true;
    }

    // allows controlWallet to update the price within a time contstraint, allows fundWallet complete control
    function updatePrice(uint256 newNumerator) external onlyManagingWallets {
        require(block.number > fundingEndBlock);
        require(newNumerator > 0);
        require_limited_change(newNumerator);
        // either controlWallet command is compliant or transaction came from fundWallet
        currentPrice.numerator = newNumerator;
        // maps time to new Price
        prices[previousUpdateTime] = currentPrice;
        previousUpdateTime = now;
        PriceUpdate(newNumerator, currentPrice.denominator);
    }

    function require_limited_change (uint256 newNumerator)
        private
        only_if_controlWallet
        require_waited
        only_if_increase(newNumerator)
    {
        uint256 percentage_diff = 0;
        percentage_diff = safeMul(newNumerator, 100) / currentPrice.numerator;
        percentage_diff = safeSub(percentage_diff, 100);
        // controlWallet can only increase price by max 20% and only every waitTime
        require(percentage_diff <= 20);
    }

    function updatePriceDenominator(uint256 newDenominator) external onlyFundWallet {
        require(block.number > fundingEndBlock);
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
        uint256 developmentAllocation = safeMul(amountTokens, 14942528735632185) / 100000000000000000;
        // check that token cap is not exceeded
        uint256 newTokens = safeAdd(amountTokens, developmentAllocation);
        require(safeAdd(totalSupply, newTokens) <= tokenCap);
        // increase token supply, assign tokens to investor
        totalSupply = safeAdd(totalSupply, newTokens);
        balances[investor] = safeAdd(balances[investor], amountTokens);
        balances[vestingContract] = safeAdd(balances[vestingContract], developmentAllocation);
    }

    function allocatePresaleTokens(address investor, uint amountTokens) external onlyFundWallet {
        require(block.number < fundingEndBlock);
        require(investor != address(0));
        whitelist[investor] = true; // automatically whitelist accepted presale
        allocateTokens(investor, amountTokens);
        Whitelist(investor);
        AllocatePresale(investor, amountTokens);
    }

    function verifyInvestor(address investor) external onlyManagingWallets {
        whitelist[investor] = true;
        Whitelist(investor);
    }

    function invest() external payable {
        investTo(msg.sender);
    }

    function investTo(address investor) public payable onlyWhitelist {
        require(!halted);
        require(investor != address(0));
        require(msg.value >= minInvestment);
        require(block.number >= fundingStartBlock && block.number < fundingEndBlock);
        uint256 icoDenominator = icoDenominatorPrice();
        uint256 tokensToBuy = safeMul(msg.value, currentPrice.numerator) / icoDenominator;
        allocateTokens(investor, tokensToBuy);
        // send ether to fundWallet
        fundWallet.transfer(msg.value);
        Invest(msg.sender, investor, msg.value, tokensToBuy);
    }

    function icoDenominatorPrice() public constant returns (uint256) {
        uint256 icoDuration = safeSub(now, previousUpdateTime);
        uint256 denominator;
        if (icoDuration < 24 hours) {
            return currentPrice.denominator;
        } else if (icoDuration < 4 weeks ) {
            denominator = safeMul(currentPrice.denominator, 105) / 100;
            return denominator;
        } else {
            denominator = safeMul(currentPrice.denominator, 110) / 100;
            return denominator;
        }
    }

    function requestWithdrawal(uint256 amountTokensToWithdraw) external isTradeable onlyWhitelist {
        require(block.number > fundingEndBlock);
        require(amountTokensToWithdraw > 0);
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
        enact_withdrawal_less(investor, withdrawValue, tokens); // order is very important here
        enact_withdrawal_greater_equal(investor, withdrawValue, tokens);
    }

    function enact_withdrawal_less(address investor, uint256 withdrawValue, uint256 tokens)
        private
        only_if_bal_less(withdrawValue)
    {
        assert(this.balance < withdrawValue);
        balances[investor] = safeAdd(balances[investor], tokens);
        Withdraw(investor, tokens, 0); // indicate a failed withdrawal
    }
    function enact_withdrawal_greater_equal(address investor, uint256 withdrawValue, uint256 tokens)
        private
        only_if_bal_greater_equal(withdrawValue)
    {
        assert(this.balance >= withdrawValue);
        balances[fundWallet] = safeAdd(balances[fundWallet], tokens);
        investor.transfer(withdrawValue);
        Withdraw(investor, tokens, withdrawValue);
    }

    function checkWithdrawValue(uint256 amountTokensToWithdraw) constant returns (uint256 etherValue) {
        require(amountTokensToWithdraw > 0);
        require(balanceOf(msg.sender) >= amountTokensToWithdraw);
        uint256 withdrawValue = safeMul(amountTokensToWithdraw, currentPrice.denominator) / currentPrice.numerator;
        require(this.balance >= withdrawValue);
        return withdrawValue;
    }

    // allow fundWallet or controlWallet to add ether to contract
    function addLiquidity() external onlyManagingWallets payable {
        require(msg.value > 0);
        AddLiquidity(msg.value);
    }

    // allow fundWallet to remove ether from contract
    function removeLiquidity(uint256 amount) external onlyManagingWallets {
        require(amount <= this.balance);
        fundWallet.transfer(amount);
        RemoveLiquidity(amount);
    }

    function changeFundWallet(address newFundWallet) external onlyFundWallet {
        require(newFundWallet != address(0));
        fundWallet = newFundWallet;
    }

    function changeControlWallet(address newControlWallet) external onlyFundWallet {
        require(newControlWallet != address(0));
        controlWallet = newControlWallet;
    }

    function changeWaitTime(uint256 newWaitTime) external onlyFundWallet {
        waitTime = newWaitTime;
    }

    // TODO: possibly remove
    function updateFundingStartBlock(uint256 newFundingStartBlock) external onlyFundWallet {
        require(block.number < fundingStartBlock);
        require(block.number < newFundingStartBlock);
        fundingStartBlock = newFundingStartBlock;
    }
    // TODO: possibly remove
    function updateFundingEndBlock(uint256 newFundingEndBlock) external onlyFundWallet {
        require(block.number < fundingEndBlock);
        require(block.number < newFundingEndBlock);
        fundingEndBlock = newFundingEndBlock;
    }

    function halt() external onlyFundWallet {
        halted = true;
    }
    function unhalt() external onlyFundWallet {
        halted = false;
    }

    function enableTrading() external onlyFundWallet {
        require(block.number > fundingEndBlock);
        tradeable = true;
    }

    //fallback function
    function() {
        require(false); // do nothing
    }

    function claimTokens(address _token) external onlyFundWallet {
        require(_token != address(0));
        Token token = Token(_token);
        uint256 balance = token.balanceOf(this);
        token.transfer(fundWallet, balance);
     }

    // prevent transfers until trading allowed
    function transfer(address _to, uint256 _value) isTradeable returns (bool success) {
        return super.transfer(_to, _value);
    }
    function transferFrom(address _from, address _to, uint256 _value) isTradeable returns (bool success) {
        return super.transferFrom(_from, _to, _value);
    }

}
