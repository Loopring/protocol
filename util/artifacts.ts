
export class Artifacts {
  public TokenRegistry: any;
  public LoopringProtocolImpl: any;
  public TokenTransferDelegate: any;
  public NameRegistry: any;
  public TokenFactory: any;
  public DummyToken: any;
  constructor(artifacts: any) {
    this.TokenRegistry = artifacts.require("TokenRegistry");
    this.LoopringProtocolImpl = artifacts.require("LoopringProtocolImpl");
    this.TokenTransferDelegate = artifacts.require("TokenTransferDelegate");
    this.TokenFactory = artifacts.require("TokenFactory");
    this.NameRegistry = artifacts.require("NameRegistry");
    this.DummyToken = artifacts.require("test/DummyToken");
  }
}
