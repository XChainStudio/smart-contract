pragma solidity ^0.4.19;

/* taking ideas from OpenZeppelin, thanks*/
contract SafeMath {
    function safeAdd(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 z = x + y;
        assert((z >= x) && (z >= y));
        return z;
    }

    function safeSub(uint256 x, uint256 y) internal pure returns (uint256) {
        assert(x >= y);
        return x - y;
    }

    function safeMulti(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 z = x * y;
        assert((x == 0) || (z / x == y));
        return z;
    }

    function safeDiv(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 z = x / y;
        return z;
    }

    function safeMin256(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }
}

contract Token {
    uint256 public totalSupply;

    function balanceOf(address _owner) public view returns (uint256 balance);

    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    function transfer(address _to, uint256 _value) public returns (bool success);

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    function approve(address _spender, uint256 _value) public returns (bool success);

    event LogTransfer(address indexed _from, address indexed _to, uint256 _value);
    event LogApproval(address indexed _owner, address indexed _spender, uint256 _value);
}

/* ERC 20 token */
contract StandardToken is Token, SafeMath {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) allowed;

    // prvent from the ERC20 short address attack
    modifier onlyPayloadSize(uint size) {
        require(msg.data.length >= size + 4);
        _;
    }

    function transfer(address _to, uint256 _value) public onlyPayloadSize(2 * 32) returns (bool success) {
        require(_to != 0x0);
        balances[msg.sender] = safeSub(balances[msg.sender], _value);
        balances[_to] = safeAdd(balances[_to], _value);
        LogTransfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public onlyPayloadSize(3 * 32) returns (bool success) {
        balances[_from] = safeSub(balances[_from], _value);
        allowed[_from][msg.sender] = safeSub(allowed[_from][msg.sender], _value);
        balances[_to] = safeAdd(balances[_to], _value);
        LogTransfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        LogApproval(msg.sender, _spender, _value);
        return true;
    }

    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }
}

contract XCToken is StandardToken {
    //meta data
    string public constant name = "XChain Token";
    string public constant symbol = "XCT";
    uint256 public constant decimals = 18;

    //address of xchain studio
    address public ethFundDeposit; //deposit address for ETH raised by xchain studio
    address public xctFundDeposit; //deposit address for XCT token hold by xchain studio

    //crowdsale parameters
    uint256 public fundStartBlock;
    uint256 public fundEndBlock;
    uint256 public amountRaised;
    bool public operational; // switched to true in operational state

    // TODO: goals and rate will change to real values in token sale
    uint256 public constant rate = 100000; // 2000 XCT tokens per ETH
    uint256 public constant fundGoal = 20000 * 1 ether; // fund goal is 20000 ether
    uint256 public constant hardCap = 26000 * 1 ether; // hardCap is 50000 ether

    event LogRefund(address indexed _to, uint256 _value);

    function XCToken(
        address _ethFundDeposit,
        address _xctFundDeposit,
        uint256 _fundStartBlock,
        uint256 _fundEndBlock) public {
        ethFundDeposit = _ethFundDeposit;
        xctFundDeposit = _xctFundDeposit;
        fundStartBlock = _fundStartBlock;
        fundEndBlock = _fundEndBlock;
        // 3.2b XCTokens in total
        totalSupply = 32 * 10**26;
        // 1.6b XCTokens reserved for XChain
        balances[xctFundDeposit] = 16 * 10 ** 26;
        amountRaised = 0;
        operational = false;
    }

    modifier inProgress() {
        require(amountRaised < hardCap);
        require(block.number >= fundStartBlock && block.number <= fundEndBlock);
        _;
    }
    modifier fundFailed() {
        require(block.number > fundEndBlock && amountRaised < fundGoal);
        _;
    }
    modifier goalReached() {
        require(amountRaised >= fundGoal);
        if ((amountRaised >= hardCap) || (block.number > fundEndBlock)) _;
    }

    //token exchange
    function() public payable {
        issueToken();
    }

    /* issue token based on ether received
    * @param newly created token will be send to recipient address
    */
    function issueToken() public payable inProgress {
        // accept minimum purchase of 5 ether
        require(msg.value >= 5 ether);
        uint256 contribution = safeMin256(msg.value, safeSub(hardCap, amountRaised));
        amountRaised = safeAdd(amountRaised, contribution);
        //
        uint256 tokens = safeMulti(contribution, rate);
        balances[msg.sender] += tokens;

        // Refund the msg.sender, in the case that not all of its ETH was used.
        if (contribution != msg.value) {
            uint256 overpay = safeSub(msg.value, contribution);
            msg.sender.transfer(overpay);
        }
    }

    function withdraw() external goalReached {
        require(!operational);
        require(msg.sender == ethFundDeposit);
        operational = true;
        // send the ether to xchain studio
        msg.sender.transfer(this.balance);
    }

    function refund() external fundFailed {
        require(!operational);
        //xchain studio not entitled to a refund
        require(msg.sender != xctFundDeposit);
        require(balances[msg.sender] > 0);
        uint256 amount = balances[msg.sender];
        uint256 ethValue = safeDiv(amount, rate);
        balances[msg.sender] = 0;
        // make sure it works with .send gas limits
        if (msg.sender.send(ethValue)) {
            LogRefund(msg.sender, amount);
        } else {
            balances[msg.sender] = amount;
        }
    }
}
