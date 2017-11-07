
export class Artifacts {
  public TokenRegistry: any;
  public RinghashRegistry: any;
  public LoopringProtocolImpl: any;
  public ERC20TransferDelegate: any;
  public DummyToken: any;
  constructor(artifacts: any) {
    this.TokenRegistry = artifacts.require('TokenRegistry');
    this.RinghashRegistry = artifacts.require('RinghashRegistry');
    this.LoopringProtocolImpl = artifacts.require('LoopringProtocolImpl');
    this.ERC20TransferDelegate = artifacts.require('ERC20TransferDelegate');
    this.DummyToken = artifacts.require('test/DummyToken');
  }
}
