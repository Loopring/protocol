var TokenRegistry           = artifacts.require("./TokenRegistry");
var RinghashRegistry        = artifacts.require("./RinghashRegistry");
var ERC20TransferDelegate   = artifacts.require("./ERC20TransferDelegate");

module.exports = function(deployer, network, accounts) {
  deployer.deploy(TokenRegistry);
  deployer.deploy(RinghashRegistry, 100);
  deployer.deploy(ERC20TransferDelegate);
};
