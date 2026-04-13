pragma solidity ^0.8.20;

import "./Token.sol";

interface TokenInterface {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract Game {

    TokenInterface public token;
    enum GameState { 
        Idle, 
        WaitingForOpponent, 
        WaitingForReveal, 
        WaitingForSettlement
        }
    struct GameRound {
        address payable PlayerA;
        address payable PlayerB;
        uint256 BetInEther;
        uint256 StakeInToken;
        bytes32 HashOfSecretA;
        bytes32 HashOfSecretB;
        uint256 SecretA;
        uint256 SecretB;
        bool RevealedA;
        bool RevealedB;
        uint256 Deadline;
        GameState State;
    }

    GameRound public game;
    uint256 public constant minBet = 0.0001 ether;
    uint256 public constant maxBet = 0.01 ether;
    uint256 public constant revealTimeout = 1 minutes;
    uint256 public constant joinTimeout = 1 minutes;
    uint256 public constant transactionFee = 8;      // 8%
    uint256 public constant bonusFrequency = 1;    // 1% chance
    uint256 public constant bonusPercentage = 300;   // 300% of bet as bonus

    event GameCreated(address indexed playerA, uint256 bet);
    event GameJoined(address indexed playerB);
    event SecretRevealed(address indexed player);
    event GameResult (address indexed winner, uint128 dice);
    event GameSettled(address indexed winner, uint256 prize);
    event BetsRefunded (address player, uint256 bet);
    event BetsConfiscated (address playerA, address playerB, uint256 bet, string reason);

    bool private locked;
    modifier nonReentrant() {
        require(!locked, "ReentrancyGuard");
        locked = true;
        _;
        locked = false;
    }
    
    constructor(address tokenAddress) payable {
        token = TokenInterface(tokenAddress);
        require(msg.value > 1 ether, "Must Prefund to Obtain Sufficient Tokens");
        (bool success, ) = tokenAddress.call{value: msg.value}("");
        require(success, "Token Prefunding Failed");
    }

    function createGame(bytes32 hashCommit) external payable nonReentrant{
        uint256 placedBet = msg.value;
        require(game.State == GameState.Idle, "Game is Currently Running");
        require(placedBet >= minBet && placedBet <= maxBet, "Bet should be between 0.0001 and 0.01 Ether");
        
        uint256 contractTokenBalance = token.balanceOf(address(this));
        (bool success, ) = address(token).call{value: placedBet}("");
        require(success, "Failed to Convert Ether Bet to Tokens");
        uint256 newTokenBalance = token.balanceOf(address(this));
        uint256 tokenBet = newTokenBalance - contractTokenBalance;

        game = GameRound({
            PlayerA: payable(msg.sender),
            PlayerB: payable(address(0)),
            BetInEther: placedBet,
            StakeInToken: tokenBet,
            HashOfSecretA: hashCommit,
            HashOfSecretB: 0,
            SecretA: 0,
            SecretB: 0,
            RevealedA: false,
            RevealedB: false,
            Deadline: block.timestamp + joinTimeout,
            State: GameState.WaitingForOpponent
        });
        emit GameCreated(msg.sender, placedBet);
    }

    function joinGame(bytes32 hashCommit) external payable nonReentrant{
        require(game.State == GameState.WaitingForOpponent, "Game is not Joinnable");
        require(msg.sender != game.PlayerA);
        require(block.timestamp <= game.Deadline, "Game Joinning has Timed Out");
        uint256 followedBet = msg.value;
        require(followedBet == game.BetInEther);
        (bool success, ) = address(token).call{value: msg.value}("");
        require(success, "Failed to Convert Ether Bet to Tokens");

        game.PlayerB = payable(msg.sender);
        game.HashOfSecretB = hashCommit;
        game.StakeInToken *=2;
        game.State = GameState.WaitingForReveal;
        game.Deadline = block.timestamp + revealTimeout;
        emit GameJoined(msg.sender);
    }

    function revealSecret(uint256 secret) external {
        require(game.State == GameState.WaitingForReveal, "Game has not reached Secret Reveal Phase");
        require(block.timestamp <= game.Deadline, "Secret Reveal has Timmed Out");
        bytes32 hash = keccak256(
            abi.encodePacked(secret, msg.sender)
        );

        if (msg.sender == game.PlayerA) {
            require(!game.RevealedA, "Player A Already revealed");
            require(hash == game.HashOfSecretA, "Player A's Reveal is Invalid");
            game.SecretA = secret;
            game.RevealedA = true;
        } 
        else if (msg.sender == game.PlayerB) {
            require(!game.RevealedB, "Player B Already revealed");
            require(hash == game.HashOfSecretB, "Player B's Reveal is Invalid");
            game.SecretB = secret;
            game.RevealedB = true;
        } 
        else {
            revert("You are Not A Valid Player");
        }
        emit SecretRevealed(msg.sender);

        if (game.RevealedA && game.RevealedB) {
            game.State = GameState.WaitingForSettlement;
            settlement();
        }
    }

    function settlement() internal {
        uint256 randomNumber = computeRandom();
        uint128 dice = uint128((randomNumber % 6) + 1);
        address winner = (dice <= 3) ? game.PlayerA : game.PlayerB;
        emit GameResult (winner, dice);
        payout(winner);
    }

    function computeRandom() internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encode(game.SecretA, game.SecretB)
            )
        );
    }

    function payout(address winner) internal {
        uint256 totalPot = game.StakeInToken;
        uint256 fee = (totalPot * transactionFee) / 100;
    
        uint256 bonus = 0;
        uint256 bonusRandomSeed = computeRandom() >> 128;
        if (bonusRandomSeed % 100 < bonusFrequency) {
            bonus = (totalPot * bonusPercentage) / 100;
        }
        uint256 prize = totalPot - fee + bonus;
        uint256 reserve = token.balanceOf(address(this));
        prize = prize > reserve ? reserve : prize;
        reset();
        require(token.transfer(winner, prize), "Contract Failed to Transfer Token Prize to Winner");
        emit GameSettled(winner, prize);
    }

    function refund(address player) internal {
        uint256 amount = game.StakeInToken;
        uint256 bet = game.BetInEther;
        reset();
        require(token.transfer(player, amount), "Contract Failed to Refund Token to Player");
        emit BetsRefunded(player, bet);
    }

    function reset() internal {
        delete game;
    }

    function claimTimeout() external nonReentrant{
        require(block.timestamp > game.Deadline, "The Game has Not Yet TimedOut");

        if (game.State == GameState.WaitingForOpponent) {
            require(msg.sender == game.PlayerA, "Only Game Creator can refund");
            refund(game.PlayerA);
        }
        else if (game.State == GameState.WaitingForReveal) {
            if (game.RevealedA && !game.RevealedB) {
                payout(game.PlayerA);
            } 
            else if (!game.RevealedA && game.RevealedB) {
                payout(game.PlayerB);
            } 
            else {
                emit BetsConfiscated(game.PlayerA, game.PlayerB, game.BetInEther, 
                "Neither Players Revealed Before TimeOut");
                reset();
            }
        }
        else {
            revert("No TimeOut Condition");
        }
    }
}
