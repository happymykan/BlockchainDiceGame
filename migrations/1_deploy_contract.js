const Token = artifacts.require("Token");
const Game = artifacts.require("Game");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(Token, "PseudoToken", "PseudoTK");
  const tokenInstance = await Token.deployed();
  await deployer.deploy(Game, tokenInstance.address,
    {value: web3.utils.toWei("2", "ether")});
};

