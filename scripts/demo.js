const Token = artifacts.require("Token");
const Game = artifacts.require("Game");

const { keccak256, soliditySha3 } = web3.utils;

module.exports = async function (callback) {
  try {
    const accounts = await web3.eth.getAccounts();
    const owner = accounts[0];
    const playerA = accounts[1];
    const playerB = accounts[2];

    console.log("Owner:", owner);
    console.log("PlayerA:", playerA);
    console.log("PlayerB:", playerB);

    // =========================
    // 1️⃣ DEPLOY TOKEN
    // =========================

    const token = await Token.new("StageToken", "STK", { from: owner });
    console.log("✅ Token deployed at:", token.address);

    // =========================
    // 2️⃣ TOKEN ACQUISITION (BUY)
    // =========================

    console.log("\nPlayerA buying tokens...");
    await web3.eth.sendTransaction({
      from: playerA,
      to: token.address,
      value: web3.utils.toWei("0.01", "ether")
    });

    let balanceA = await token.balanceOf(playerA);
    console.log("PlayerA token balance after buy:", balanceA.toString());

    // =========================
    // 3️⃣ TOKEN TRANSFER
    // =========================

    console.log("\nTransferring tokens from A to B...");
    await token.transfer(playerB, balanceA.divn(2), { from: playerA });

    console.log("PlayerB balance:",
      (await token.balanceOf(playerB)).toString()
    );

    // =========================
    // 4️⃣ TOKEN SELL
    // =========================

    console.log("\nPlayerB selling tokens...");
    const sellAmount = await token.balanceOf(playerB);
    await token.sell(sellAmount, { from: playerB });

    console.log("PlayerB balance after sell:",
      (await token.balanceOf(playerB)).toString()
    );

    // =========================
    // 5️⃣ DEPLOY GAME (WITH PREFUND)
    // =========================

    console.log("\nDeploying Game...");
    const game = await Game.new(token.address, {
      from: owner,
      value: web3.utils.toWei("2", "ether") // required prefunding
    });

    console.log("✅ Game deployed at:", game.address);

    // =========================
    // 6️⃣ COMPLETE DICE GAME
    // =========================

    const betAmount = web3.utils.toWei("0.001", "ether");

    const secretA = 123;
    const secretB = 777;

    const hashA = soliditySha3(secretA, playerA);
    const hashB = soliditySha3(secretB, playerB);

    console.log("\nCreating game...");
    await game.createGame(hashA, {
      from: playerA,
      value: betAmount
    });

    console.log("Joining game...");
    await game.joinGame(hashB, {
      from: playerB,
      value: betAmount
    });

    console.log("Revealing secrets...");
    await game.revealSecret(secretA, { from: playerA });
    await game.revealSecret(secretB, { from: playerB });

    // =========================
    // 7️⃣ VERIFY WINNER + BONUS
    // =========================

    const winnerAddress = (await game.game()).PlayerA; // dice logic determines event
    console.log("\nCheck GameResult event on Etherscan for winner.");

    console.log("Token balance of PlayerA:",
      (await token.balanceOf(playerA)).toString()
    );

    console.log("Token balance of PlayerB:",
      (await token.balanceOf(playerB)).toString()
    );

    console.log("✅ Full Dice Game Executed");

    callback();
  } catch (err) {
    console.error(err);
    callback(err);
  }
};