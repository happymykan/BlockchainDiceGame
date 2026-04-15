const Token = artifacts.require("Token");
const Game = artifacts.require("Game");
const crypto = require("crypto");

const { soliditySha3, toWei, fromWei } = web3.utils;

module.exports = async function (callback) {
  try {
    const accounts = await web3.eth.getAccounts();
    const playerA = accounts[1];
    const playerB = accounts[2];
    const token = await Token.deployed();
    const game = await Game.deployed();

    console.log("======================================");
    console.log("Sepolia Full Game Demo");
    console.log("Token Address:", token.address);
    console.log("Game  Address:", game.address);
    console.log("--------------------------------------");

    console.log("Prefunding Evidence");
    const tokenEthBalance = await web3.eth.getBalance(token.address);
    const gameTokenBalance = await token.balanceOf(game.address);

    console.log("Token Contract ETH Balance (Liquidity Pool):",
      fromWei(tokenEthBalance, "ether"), "ETH");
    console.log("Game Contract Token Balance (Prefunded Tokens):",
      gameTokenBalance.toString(), "tokens");
    console.log("--------------------------------------");

    const betEth = "0.001";
    const betWei = toWei(betEth, "ether");
    console.log("Bet Details:");
    console.log("Bet per Player (ETH):", betEth, "ETH");

    const secretA = BigInt("0x" + crypto.randomBytes(32).toString("hex"));
    const secretB = BigInt("0x" + crypto.randomBytes(32).toString("hex"));
    const hashA = soliditySha3(secretA.toString(), playerA);
    const hashB = soliditySha3(secretB.toString(), playerB);

    const gameTokenBeforeA = await token.balanceOf(game.address);

    console.log("1. Creating Game...");
    const tx1 = await game.createGame(hashA, {
      from: playerA,
      value: betWei
    });
    console.log("createGame tx hash:", tx1.tx);

    const gameTokenAfterA = await token.balanceOf(game.address);
    const tokensFromA = gameTokenAfterA - gameTokenBeforeA;
    console.log("Tokens received from PlayerA bet:", tokensFromA.toString());

    const gameTokenBeforeB = await token.balanceOf(game.address);

    console.log("2. Joining Game...");
    const tx2 = await game.joinGame(hashB, {
      from: playerB,
      value: betWei
    });
    console.log("joinGame tx hash:", tx2.tx);

    const gameTokenAfterB = await token.balanceOf(game.address);
    const tokensFromB = gameTokenAfterB - gameTokenBeforeB;
    console.log("Tokens received from PlayerB bet:", tokensFromB.toString());

    const totalPot = tokensFromA + tokensFromB;
    console.log("Total Pot (Tokens):", totalPot.toString());

    console.log("3. Revealing Secret A...");
    const tx3 = await game.revealSecret(secretA.toString(), {
      from: playerA
    });
    console.log("reveal A tx hash:", tx3.tx);

    console.log("4. Revealing Secret B...");
    const tx4 = await game.revealSecret(secretB.toString(), {
      from: playerB
    });
    console.log("reveal B tx hash:", tx4.tx);

    console.log("--------------------------------------");

    const resultEvent = tx4.logs.find(log => log.event === "GameResult");
    const settledEvent = tx4.logs.find(log => log.event === "GameSettled");

    if (resultEvent) {
      console.log("GameResult Event:");
      console.log("Dice  :", resultEvent.args.dice.toString());
      console.log("Winner:", resultEvent.args.winner);
    }

    if (settledEvent) {
      console.log("GameSettled Event:");
      console.log("Winner:", settledEvent.args.winner);
      console.log("Prize (+ Bonus & -Transaction Fee):", settledEvent.args.prize.toString(), "tokens");
    }
    console.log("--------------------------------------");

    const finalA = await token.balanceOf(playerA);
    const finalB = await token.balanceOf(playerB);
    const finalGame = await token.balanceOf(game.address);

    console.log("Final Token Balances:");
    console.log("PlayerA:", finalA.toString());
    console.log("PlayerB:", finalB.toString());
    console.log("Game   :", finalGame.toString());

    console.log("Full Game Execution Completed");
    console.log("--------------------------------------");

    console.log("Winner Tries to Sell All Tokens:");
    let winnerAddress = null;
    if (settledEvent) {
      winnerAddress = settledEvent.args.winner;
    }
    if (!winnerAddress) {
      console.log("Could not determine winner.");
      callback();
      return;
    }

    let winnerLabel = "Unknown";
    if (winnerAddress.toLowerCase() === playerA.toLowerCase()) {
      winnerLabel = "PlayerA";
    } else if (winnerAddress.toLowerCase() === playerB.toLowerCase()) {
      winnerLabel = "PlayerB";
    }

    const winnerTokenBefore = await token.balanceOf(winnerAddress);
    const winnerEthBefore = await web3.eth.getBalance(winnerAddress);
    console.log(`${winnerLabel} ETH Before:`,
      fromWei(winnerEthBefore, "ether"), "ETH");

    const tokensToSell = winnerTokenBefore;
    const sellTx = await token.sell(tokensToSell, {
      from: winnerAddress
    });
    console.log("Sell tx hash:", sellTx.tx);

    const winnerTokenAfter = await token.balanceOf(winnerAddress);
    const winnerEthAfter = await web3.eth.getBalance(winnerAddress);
    const tokenEthAfter = await web3.eth.getBalance(token.address);
    console.log(`${winnerLabel} Token Balance After Sell:`,
      winnerTokenAfter.toString());
    console.log(`${winnerLabel} ETH After:`,
      fromWei(winnerEthAfter, "ether"), "ETH");
    console.log("Token Contract ETH Balance:",
      fromWei(tokenEthAfter, "ether"), "ETH");
    
    callback();
  } catch (err) {
    console.error("Execution failed:", err);
    callback(err);
  }
};