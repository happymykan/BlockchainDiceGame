pragma solidity ^0.8.20;

contract Token {

    address payable public owner;
    bool public contractClosed;

    mapping(address => uint256) internal balanceDict;
    uint256 internal tokenTotal;

    string internal tokenName;
    string internal tokenSymbol;
    uint128 internal tokenPrice;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed to, uint256 value);
    event Sell(address indexed from, uint256 value);

    constructor(string memory inputTokenName, string memory inputTokenSymbol) {
        owner = payable(msg.sender);
        tokenName = inputTokenName;
        tokenSymbol = inputTokenSymbol;
        tokenPrice = 600; // 600 wei per token
    }

    function totalSupply() public view returns (uint256) {
        return tokenTotal;
    }
    function balanceOf(address account) public view returns (uint256) {
        return balanceDict[account];
    }
    function getName() public view returns (string memory) {
        return tokenName;
    }
    function getSymbol() public view returns (string memory) {
        return tokenSymbol;
    }
    function getPrice() public view returns (uint128) {
        return tokenPrice;
    }

    modifier onlyOwner() {
    require(msg.sender == owner, "Only Contract Owner Can Call");
    _;
    }
    modifier hasEnoughTokens(uint256 value) {
    require(balanceDict[msg.sender] >= value, "User Out of Tokens");
    _;
    }
    modifier notClosed() {
        require(!contractClosed, "Contract closed");
        _;
    }
    
    function transfer(address to, uint256 value) 
    public hasEnoughTokens(value) returns (bool) {
        address sender = msg.sender; // saves gas
        balanceDict[sender] -= value;
        balanceDict[to] += value;
        emit Transfer(sender, to, value);
        return true;
    }

    function mint_internal (address to, uint256 value) 
    internal {
        balanceDict[to] += value;
        tokenTotal += value;
        emit Mint(to, value);
    }
    
    function mint(address to, uint256 value) 
    external onlyOwner notClosed returns (bool) {
        mint_internal(to, value);
        return true;
    }

    function sell(uint256 value) 
    public hasEnoughTokens(value) notClosed returns (bool) {
        uint256 weiToPay = value * tokenPrice;
        require(address(this).balance >= weiToPay, "Contract Out of Ether");
        address sender = msg.sender;
        balanceDict[sender] -= value;
        tokenTotal -= value;
        (bool success, ) = payable(sender).call{value: weiToPay}("");
        require(success, "Transfer Failed");
        emit Sell(sender, value);
        return true;
    }

    function buy_internal (address buyer, uint256 weiAmount) 
    internal {
        uint256 unitPrice = (tokenPrice*105)/100;
        require(weiAmount >= unitPrice, "Not enough Ether");   
        uint256 tokensToMint = weiAmount / unitPrice;
        uint256 refund = weiAmount % unitPrice;
        mint_internal(buyer, tokensToMint);
        if (refund != 0) {
            (bool success, ) = payable(buyer).call{value: refund}("");
            require(success, "Refund failed");
        }
    }

    function close() external onlyOwner {
        contractClosed = true;
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = owner.call{value: balance}("");
            require(success, "Withdrawal failed");
        }
    }

    receive() external payable notClosed {
        require(msg.value > 0, "No Ether sent");
        buy_internal(msg.sender, msg.value);
    }
    
    fallback() external payable notClosed {
        require(msg.value > 0, "No Ether sent");
        buy_internal(msg.sender, msg.value);
    }
}