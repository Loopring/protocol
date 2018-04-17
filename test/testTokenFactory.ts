import { Artifacts } from "../util/artifacts";

const {
  TokenFactory,
  TokenRegistry,
} = new Artifacts(artifacts);

contract("TokenFactory", (accounts: string[]) => {
  const owner = accounts[0];
  const user = accounts[1];
  const user2 = accounts[2];

  let tokenFactory: any;
  let tokenRegistry: any;

  before(async () => {
    tokenFactory = await TokenFactory.deployed();
    tokenRegistry = await TokenRegistry.deployed();

    await tokenFactory.initialize(tokenRegistry.address, {from: owner});
  });

  describe("user", () => {
    it("is able to create a erc20 token", async () => {
      const tx = await tokenFactory.createToken("FooToken",
                                                  "FOO",
                                                  8,
                                                  1e18);
      // console.log("addr:", addr);

    });

  });

});
