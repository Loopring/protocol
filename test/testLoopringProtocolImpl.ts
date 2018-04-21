import { BigNumber } from "bignumber.js";
import xor = require("bitwise-xor");
import promisify = require("es6-promisify");
import * as _ from "lodash";
import { Artifacts } from "../util/artifacts";
import { Order } from "../util/order";
import { ProtocolSimulator } from "../util/protocol_simulator";
import { Ring } from "../util/ring";
import { RingFactory } from "../util/ring_factory";
import { OrderParams } from "../util/types";

const {
  LoopringProtocolImpl,
  TokenRegistry,
  TokenTransferDelegate,
  DummyToken,
} = new Artifacts(artifacts);

contract("LoopringProtocolImpl", (accounts: string[]) => {
  const owner = accounts[0];
  const order1Owner = accounts[1];
  const order2Owner = accounts[2];
  const order3Owner = accounts[3];
  const order4Owner = accounts[4];
  const order5Owner = accounts[5];
  const orderAuthAddr = accounts[7]; // should generate each time in front-end. we just mock it here.
  const ringOwner = accounts[6];
  const feeRecepient = ringOwner;
  const walletAddr = accounts[8];

  let loopringProtocolImpl: any;
  let tokenRegistry: any;
  let tokenTransferDelegate: any;

  let lrcAddress: string;
  let eosAddress: string;
  let neoAddress: string;
  let qtumAddress: string;
  let delegateAddr: string;

  let lrc: any;
  let eos: any;
  let neo: any;
  let qtum: any;

  let currBlockTimeStamp: number;
  let walletSplitPercentage: number;

  let ringFactory: RingFactory;

  const getTokenBalanceAsync = async (token: any, addr: string) => {
    const tokenBalanceStr = await token.balanceOf(addr);
    const balance = new BigNumber(tokenBalanceStr);
    return balance;
  };

  const getEthBalanceAsync = async (addr: string) => {
    const balanceStr = await promisify(web3.eth.getBalance)(addr);
    const balance = new BigNumber(balanceStr);
    return balance;
  };

  const assertNumberEqualsWithPrecision = (n1: number, n2: number, precision: number = 8) => {
    const numStr1 = (n1 / 1e18).toFixed(precision);
    const numStr2 = (n2 / 1e18).toFixed(precision);

    return assert.equal(Number(numStr1), Number(numStr2));
  };

  const clear = async (tokens: any[], addresses: string[]) => {
    for (const token of tokens) {
      for (const address of addresses) {
        await token.setBalance(address, 0, {from: owner});
      }
    }
  };

  const approve = async (tokens: any[], addresses: string[], amounts: number[]) => {
    for (let i = 0; i < tokens.length; i++) {
      await tokens[i].approve(delegateAddr, 0, {from: addresses[i]});
      await tokens[i].approve(delegateAddr, amounts[i], {from: addresses[i]});
    }
  };

  before( async () => {
    [loopringProtocolImpl, tokenRegistry, tokenTransferDelegate] = await Promise.all([
      LoopringProtocolImpl.deployed(),
      TokenRegistry.deployed(),
      TokenTransferDelegate.deployed(),
    ]);

    lrcAddress = await tokenRegistry.getAddressBySymbol("LRC");
    eosAddress = await tokenRegistry.getAddressBySymbol("EOS");
    neoAddress = await tokenRegistry.getAddressBySymbol("NEO");
    qtumAddress = await tokenRegistry.getAddressBySymbol("QTUM");
    delegateAddr = TokenTransferDelegate.address;

    const walletSplitPercentageBN = await loopringProtocolImpl.walletSplitPercentage();
    walletSplitPercentage = walletSplitPercentageBN.toNumber();
    // console.log("walletSplitPercentage:", walletSplitPercentage);

    tokenTransferDelegate.authorizeAddress(LoopringProtocolImpl.address);

    [lrc, eos, neo, qtum] = await Promise.all([
      DummyToken.at(lrcAddress),
      DummyToken.at(eosAddress),
      DummyToken.at(neoAddress),
      DummyToken.at(qtumAddress),
    ]);

    const currBlockNumber = web3.eth.blockNumber;
    currBlockTimeStamp = web3.eth.getBlock(currBlockNumber).timestamp;

    ringFactory = new RingFactory(TokenTransferDelegate.address,
                                  eosAddress,
                                  neoAddress,
                                  lrcAddress,
                                  qtumAddress,
                                  orderAuthAddr,
                                  currBlockTimeStamp);
    ringFactory.walletAddr = walletAddr;

    // approve only once for all test cases.
    const allTokens = [lrc, eos, neo, qtum];
    const allAddresses = [order1Owner, order2Owner, order3Owner, feeRecepient];
    for (const token of allTokens) {
      for (const address of allAddresses) {
        await token.approve(delegateAddr, web3.toWei(10000000000), {from: address});
      }
    }
  });

  describe("submitRing", () => {
    it("should be able to fill ring with 2 orders", async () => {
      const feeSelections: number[] = [0, 0];
      const ring = await ringFactory.generateSize2Ring01(order1Owner,
                                                         order2Owner,
                                                         ringOwner,
                                                         feeSelections);

      await lrc.setBalance(order1Owner, web3.toWei(100),   {from: owner});
      await eos.setBalance(order1Owner, web3.toWei(10000), {from: owner});
      await lrc.setBalance(order2Owner, web3.toWei(100),   {from: owner});
      await neo.setBalance(order2Owner, web3.toWei(1000),  {from: owner});
      await lrc.setBalance(feeRecepient, 0, {from: owner});

      const p = ringFactory.ringToSubmitableParams(ring, feeSelections, feeRecepient);

      const ethOfOwnerBefore = await getEthBalanceAsync(owner);
      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});

      // console.log("tx.receipt.logs: ", tx.receipt.logs);

      const ethOfOwnerAfter = await getEthBalanceAsync(owner);
      const allGas = (ethOfOwnerBefore.toNumber() - ethOfOwnerAfter.toNumber()) / 1e18;
      // console.log("all gas cost for 2 orders 01(ether):", allGas);

      const lrcBalance21 = await getTokenBalanceAsync(lrc, order1Owner);
      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const neoBalance21 = await getTokenBalanceAsync(neo, order1Owner);

      const lrcBalance22 = await getTokenBalanceAsync(lrc, order2Owner);
      const eosBalance22 = await getTokenBalanceAsync(eos, order2Owner);
      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);

      const lrcBalance23 = await getTokenBalanceAsync(lrc, feeRecepient);

      assert.equal(lrcBalance21.toNumber(), 90e18, "lrc balance not match for order1Owner");
      assert.equal(eosBalance21.toNumber(), 9000e18, "eos balance not match for order1Owner");
      assert.equal(neoBalance21.toNumber(), 100e18, "neo balance not match for order1Owner");

      assert.equal(lrcBalance22.toNumber(), 95e18, "lrc balance not match for order2Owner");
      assert.equal(eosBalance22.toNumber(), 1000e18, "eos balance not match for order2Owner");
      assert.equal(neoBalance22.toNumber(), 900e18, "neo balance not match for order2Owner");

      assert.equal(lrcBalance23.toNumber(), 12e18, "lrc balance not match for feeRecepient");

      await clear([eos, neo, lrc], [order1Owner, order2Owner, feeRecepient]);
    });

    it("should be able to fill ring with 2 orders where fee selection type is margin split", async () => {
      const feeSelectionList: number[] = [1, 1];
      const ring = await ringFactory.generateSize2Ring02(order1Owner,
                                                         order2Owner,
                                                         ringOwner,
                                                         feeSelectionList);

      await eos.setBalance(order1Owner, web3.toWei(1000), {from: owner});
      await neo.setBalance(order2Owner, web3.toWei(50),  {from: owner});

      const spendableLrcFeeList = [0, 0, 0];
      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});
      // console.log("tx.receipt.logs: ", tx.receipt.logs);

      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const neoBalance21 = await getTokenBalanceAsync(neo, order1Owner);

      const eosBalance22 = await getTokenBalanceAsync(eos, order2Owner);
      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);

      const eosBalance23 = await getTokenBalanceAsync(eos, feeRecepient);
      const neoBalance23 = await getTokenBalanceAsync(neo, feeRecepient);

      const simulator = new ProtocolSimulator(ring, lrcAddress, feeSelectionList, walletSplitPercentage);
      simulator.spendableLrcFeeList = spendableLrcFeeList;
      const feeAndBalanceExpected = simulator.caculateRingFeesAndBalances();

      assertNumberEqualsWithPrecision(eosBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceS);
      assertNumberEqualsWithPrecision(neoBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceB);
      assertNumberEqualsWithPrecision(neoBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceS);
      assertNumberEqualsWithPrecision(eosBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceB);

      assertNumberEqualsWithPrecision(eosBalance23.toNumber(), feeAndBalanceExpected.totalFees[eosAddress]);
      assertNumberEqualsWithPrecision(neoBalance23.toNumber(), feeAndBalanceExpected.totalFees[neoAddress]);

      await clear([eos, neo], [order1Owner, order2Owner, feeRecepient]);
    });

    it("should be able to fill orders where fee selection type is margin split and lrc", async () => {
      const feeSelectionList = [1, 0];
      const ring = await ringFactory.generateSize2Ring03(order1Owner,
                                                         order2Owner,
                                                         ringOwner,
                                                         feeSelectionList);

      await eos.setBalance(order1Owner, web3.toWei(1000), {from: owner});
      await neo.setBalance(order2Owner, web3.toWei(50),  {from: owner});
      await lrc.setBalance(order2Owner, web3.toWei(20),  {from: owner});

      const spendableLrcFeeList = [0, 5e17, 0];
      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});

      console.log("cumulativeGasUsed for a ring of 2 orders: " + tx.receipt.gasUsed);

      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const neoBalance21 = await getTokenBalanceAsync(neo, order1Owner);

      const eosBalance22 = await getTokenBalanceAsync(eos, order2Owner);
      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);

      const eosBalance23 = await getTokenBalanceAsync(eos, feeRecepient);
      const neoBalance23 = await getTokenBalanceAsync(neo, feeRecepient);
      const lrcBalance23 = await getTokenBalanceAsync(lrc, feeRecepient);

      const simulator = new ProtocolSimulator(ring, lrcAddress, feeSelectionList, walletSplitPercentage);
      simulator.spendableLrcFeeList = spendableLrcFeeList;
      const feeAndBalanceExpected = simulator.caculateRingFeesAndBalances();

      assertNumberEqualsWithPrecision(eosBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceS);
      assertNumberEqualsWithPrecision(neoBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceB);
      assertNumberEqualsWithPrecision(neoBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceS);
      assertNumberEqualsWithPrecision(eosBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceB);
      assertNumberEqualsWithPrecision(eosBalance23.toNumber(), feeAndBalanceExpected.totalFees[eosAddress]);
      assertNumberEqualsWithPrecision(neoBalance23.toNumber(), feeAndBalanceExpected.totalFees[neoAddress]);
      assertNumberEqualsWithPrecision(lrcBalance23.toNumber(), feeAndBalanceExpected.totalFees[lrcAddress]);

      await clear([eos, neo, lrc], [order1Owner, order2Owner, feeRecepient]);
    });

    it("should be able to fill ring with 3 orders", async () => {
      const feeSelectionList = [1, 0, 1];

      const ring = await ringFactory.generateSize3Ring01(order1Owner,
                                                         order2Owner,
                                                         order3Owner,
                                                         ringOwner,
                                                         feeSelectionList);

      assert(ring.orders[0].isValidSignature(), "invalid signature");
      assert(ring.orders[1].isValidSignature(), "invalid signature");
      assert(ring.orders[2].isValidSignature(), "invalid signature");

      await eos.setBalance(order1Owner, web3.toWei(80000), {from: owner});
      await neo.setBalance(order2Owner, web3.toWei(234),  {from: owner});
      await lrc.setBalance(order2Owner, web3.toWei(5),  {from: owner}); // insuffcient lrc balance.
      await qtum.setBalance(order3Owner, web3.toWei(6780),  {from: owner});

      const spendableLrcFeeList = [0, 5e18, 0, 0];

      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});

      console.log("cumulativeGasUsed for a ring of 3 orders: " + tx.receipt.gasUsed);

      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const neoBalance21 = await getTokenBalanceAsync(neo, order1Owner);

      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);
      const qtumBalance22 = await getTokenBalanceAsync(qtum, order2Owner);

      const qtumBalance23 = await getTokenBalanceAsync(qtum, order3Owner);
      const eosBalance23 = await getTokenBalanceAsync(eos, order3Owner);

      const eosBalance24 = await getTokenBalanceAsync(eos, feeRecepient);
      const neoBalance24 = await getTokenBalanceAsync(neo, feeRecepient);
      const qtumBalance24 = await getTokenBalanceAsync(qtum, feeRecepient);
      const lrcBalance24 = await getTokenBalanceAsync(lrc, feeRecepient);

      const simulator = new ProtocolSimulator(ring, lrcAddress, feeSelectionList, walletSplitPercentage);
      simulator.spendableLrcFeeList = spendableLrcFeeList;
      const feeAndBalanceExpected = simulator.caculateRingFeesAndBalances();

      assertNumberEqualsWithPrecision(eosBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceS);
      assertNumberEqualsWithPrecision(neoBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceB);
      assertNumberEqualsWithPrecision(neoBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceS);
      assertNumberEqualsWithPrecision(qtumBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceB);

      assertNumberEqualsWithPrecision(qtumBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceS);
      assertNumberEqualsWithPrecision(eosBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceB);

      assertNumberEqualsWithPrecision(eosBalance24.toNumber(), feeAndBalanceExpected.totalFees[eosAddress]);
      assertNumberEqualsWithPrecision(neoBalance24.toNumber(), feeAndBalanceExpected.totalFees[neoAddress]);
      assertNumberEqualsWithPrecision(qtumBalance24.toNumber(), feeAndBalanceExpected.totalFees[qtumAddress]);
      assertNumberEqualsWithPrecision(lrcBalance24.toNumber(), 4e18);

      await clear([eos, neo, lrc, qtum], [order1Owner, order2Owner, order3Owner, feeRecepient]);
    });

    it("should be able to partial fill ring with 3 orders", async () => {
      const feeSelectionList = [1, 0, 1];
      const ring = await ringFactory.generateSize3Ring02(order1Owner,
                                                         order2Owner,
                                                         order3Owner,
                                                         ringOwner,
                                                         100,
                                                         feeSelectionList);

      assert(ring.orders[0].isValidSignature(), "invalid signature");
      assert(ring.orders[1].isValidSignature(), "invalid signature");
      assert(ring.orders[2].isValidSignature(), "invalid signature");

      const availableAmountSList = [10000e18, 100e18, 10000e18];
      const spendableLrcFeeList = [0, 6e18, 0, 0];

      await eos.setBalance(order1Owner, availableAmountSList[0], {from: owner});
      await neo.setBalance(order2Owner, availableAmountSList[1],  {from: owner});
      await lrc.setBalance(order2Owner, web3.toWei(15),  {from: owner});
      await qtum.setBalance(order3Owner, availableAmountSList[2],  {from: owner});

      // await approve([eos, neo, qtum], [order1Owner, order2Owner, order3Owner], availableAmountSList);
      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});

      // console.log("tx.receipt.logs: ", tx.receipt.logs);

      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const neoBalance21 = await getTokenBalanceAsync(neo, order1Owner);

      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);
      const qtumBalance22 = await getTokenBalanceAsync(qtum, order2Owner);

      const qtumBalance23 = await getTokenBalanceAsync(qtum, order3Owner);
      const eosBalance23 = await getTokenBalanceAsync(eos, order3Owner);

      const eosBalance24 = await getTokenBalanceAsync(eos, feeRecepient);
      const neoBalance24 = await getTokenBalanceAsync(neo, feeRecepient);
      const qtumBalance24 = await getTokenBalanceAsync(qtum, feeRecepient);
      const lrcBalance24 = await getTokenBalanceAsync(lrc, feeRecepient);

      const simulator = new ProtocolSimulator(ring, lrcAddress, feeSelectionList, walletSplitPercentage);
      simulator.availableAmountSList = availableAmountSList;
      simulator.spendableLrcFeeList = spendableLrcFeeList;
      const feeAndBalanceExpected = simulator.caculateRingFeesAndBalances();

      assertNumberEqualsWithPrecision(eosBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceS, 6);
      assertNumberEqualsWithPrecision(neoBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceB);
      assertNumberEqualsWithPrecision(neoBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceS);
      assertNumberEqualsWithPrecision(qtumBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceB);

      assertNumberEqualsWithPrecision(qtumBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceS);
      assertNumberEqualsWithPrecision(eosBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceB);

      assertNumberEqualsWithPrecision(eosBalance24.toNumber(), feeAndBalanceExpected.totalFees[eosAddress]);
      assertNumberEqualsWithPrecision(neoBalance24.toNumber(), feeAndBalanceExpected.totalFees[neoAddress]);
      assertNumberEqualsWithPrecision(qtumBalance24.toNumber(), feeAndBalanceExpected.totalFees[qtumAddress]);
      assertNumberEqualsWithPrecision(lrcBalance24.toNumber(), feeAndBalanceExpected.totalFees[lrcAddress]);

      await clear([eos, neo, lrc, qtum], [order1Owner, order2Owner, order3Owner, feeRecepient]);
    });

    it("should be able to switch fee selection to margin-split(100%) when lrcFee is 0", async () => {
      const feeSelectionList = [0, 1, 0];
      const ring = await ringFactory.generateSize3Ring02(order1Owner,
                                                         order2Owner,
                                                         order3Owner,
                                                         ringOwner,
                                                         200,
                                                         feeSelectionList);

      assert(ring.orders[0].isValidSignature(), "invalid signature");
      assert(ring.orders[1].isValidSignature(), "invalid signature");
      assert(ring.orders[2].isValidSignature(), "invalid signature");

      const availableAmountSList = [10000e18, 100e18, 10000e18];
      const spendableLrcFeeList = [0, 6e18, 0, 0];

      await eos.setBalance(order1Owner, availableAmountSList[0], {from: owner});
      await neo.setBalance(order2Owner, availableAmountSList[1],  {from: owner});
      await lrc.setBalance(order2Owner, web3.toWei(15),  {from: owner});
      await qtum.setBalance(order3Owner, availableAmountSList[2],  {from: owner});
      await lrc.setBalance(feeRecepient, web3.toWei(15),  {from: owner});

      // await approve([eos, neo, qtum], [order1Owner, order2Owner, order3Owner], availableAmountSList);
      // await approve([lrc, lrc], [order2Owner, feeRecepient], [15e18, 15e18]);

      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});

      // console.log("tx.receipt.logs: ", tx.receipt.logs);

      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const neoBalance21 = await getTokenBalanceAsync(neo, order1Owner);

      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);
      const qtumBalance22 = await getTokenBalanceAsync(qtum, order2Owner);

      const qtumBalance23 = await getTokenBalanceAsync(qtum, order3Owner);
      const eosBalance23 = await getTokenBalanceAsync(eos, order3Owner);

      const eosBalance24 = await getTokenBalanceAsync(eos, feeRecepient);
      const neoBalance24 = await getTokenBalanceAsync(neo, feeRecepient);
      const qtumBalance24 = await getTokenBalanceAsync(qtum, feeRecepient);
      const lrcBalance24 = await getTokenBalanceAsync(lrc, feeRecepient);

      const simulator = new ProtocolSimulator(ring, lrcAddress, feeSelectionList, walletSplitPercentage);
      simulator.availableAmountSList = availableAmountSList;
      simulator.spendableLrcFeeList = spendableLrcFeeList;
      const feeAndBalanceExpected = simulator.caculateRingFeesAndBalances();

      assertNumberEqualsWithPrecision(eosBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceS, 6);
      assertNumberEqualsWithPrecision(neoBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceB);
      assertNumberEqualsWithPrecision(neoBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceS);
      assertNumberEqualsWithPrecision(qtumBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceB);

      assertNumberEqualsWithPrecision(qtumBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceS);
      assertNumberEqualsWithPrecision(eosBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceB);

      assertNumberEqualsWithPrecision(eosBalance24.toNumber(), feeAndBalanceExpected.totalFees[eosAddress]);
      assertNumberEqualsWithPrecision(neoBalance24.toNumber(), feeAndBalanceExpected.totalFees[neoAddress]);
      assertNumberEqualsWithPrecision(qtumBalance24.toNumber(), feeAndBalanceExpected.totalFees[qtumAddress]);
      assertNumberEqualsWithPrecision(lrcBalance24.toNumber(), feeAndBalanceExpected.totalFees[lrcAddress] + 15e18);

      await clear([eos, neo, lrc, qtum], [order1Owner, order2Owner, order3Owner, feeRecepient]);
    });

    it("should be able to pay lrc fee when receiving lrc as result of trading.", async () => {
      const feeSelectionList = [0, 0, 1];
      const ring = await ringFactory.generateSize3Ring03(order1Owner,
                                                         order2Owner,
                                                         order3Owner,
                                                         ringOwner,
                                                         100,
                                                         feeSelectionList);

      const availableAmountSList = [1000e18, 2006e18, 20e18];
      const spendableLrcFeeList = [0, 6e18, 1e18, 20e18];

      await eos.setBalance(order1Owner, availableAmountSList[0], {from: owner});
      await lrc.setBalance(order2Owner, availableAmountSList[1],  {from: owner});
      await neo.setBalance(order3Owner, availableAmountSList[2],  {from: owner});
      await lrc.setBalance(order3Owner, web3.toWei(1),  {from: owner});
      await lrc.setBalance(feeRecepient, web3.toWei(20),  {from: owner});

      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});

      // console.log("tx.receipt.logs: ", tx.receipt.logs);

      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const lrcBalance21 = await getTokenBalanceAsync(lrc, order1Owner);

      const lrcBalance22 = await getTokenBalanceAsync(lrc, order2Owner);
      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);

      const neoBalance23 = await getTokenBalanceAsync(neo, order3Owner);
      const eosBalance23 = await getTokenBalanceAsync(eos, order3Owner);

      const eosBalance24 = await getTokenBalanceAsync(eos, feeRecepient);
      const neoBalance24 = await getTokenBalanceAsync(neo, feeRecepient);
      const lrcBalance24 = await getTokenBalanceAsync(lrc, feeRecepient);

      const simulator = new ProtocolSimulator(ring, lrcAddress, feeSelectionList, walletSplitPercentage);
      simulator.availableAmountSList = availableAmountSList;
      simulator.spendableLrcFeeList = spendableLrcFeeList;
      const feeAndBalanceExpected = simulator.caculateRingFeesAndBalances();

      // console.log("feeAndBalanceExpected", feeAndBalanceExpected);

      // console.log("eosBalance21:", eosBalance21);
      // console.log("lrcBalance21:", lrcBalance21);
      // console.log("lrcBalance22:", lrcBalance22);
      // console.log("neoBalance22:", neoBalance22);
      // console.log("neoBalance23:", neoBalance23);
      // console.log("eosBalance23:", eosBalance23);
      // console.log("eosBalance24:", eosBalance24);
      // console.log("neoBalance24:", neoBalance24);
      // console.log("lrcBalance24:", lrcBalance24);

      assertNumberEqualsWithPrecision(eosBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceS, 6);
      assertNumberEqualsWithPrecision(lrcBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceB);
      assertNumberEqualsWithPrecision(lrcBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceS);
      assertNumberEqualsWithPrecision(neoBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceB);

      assertNumberEqualsWithPrecision(neoBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceS);
      assertNumberEqualsWithPrecision(eosBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceB);

      assertNumberEqualsWithPrecision(eosBalance24.toNumber(), feeAndBalanceExpected.totalFees[eosAddress]);
      assertNumberEqualsWithPrecision(neoBalance24.toNumber(), feeAndBalanceExpected.totalFees[neoAddress]);
      assertNumberEqualsWithPrecision(lrcBalance24.toNumber(), feeAndBalanceExpected.totalFees[lrcAddress]);

      await clear([eos, neo, lrc, qtum], [order1Owner, order2Owner, order3Owner, feeRecepient]);
    });

    it("should be able to choose margin split(100%) for fee when order owner's spendable lrc is 0.", async () => {
      const feeSelectionList = [0, 0, 0];
      const ring = await ringFactory.generateSize3Ring03(order1Owner,
                                                         order2Owner,
                                                         order3Owner,
                                                         ringOwner,
                                                         200,
                                                         feeSelectionList);

      const availableAmountSList = [1000e18, 2006e18, 20e18];
      const spendableLrcFeeList = [0, 6e18, 0, 20e18];

      await eos.setBalance(order1Owner, availableAmountSList[0], {from: owner});
      await lrc.setBalance(order2Owner, availableAmountSList[1],  {from: owner});
      await neo.setBalance(order3Owner, availableAmountSList[2],  {from: owner});
      await lrc.setBalance(order3Owner, spendableLrcFeeList[2],  {from: owner});
      await lrc.setBalance(feeRecepient, spendableLrcFeeList[3],  {from: owner});

      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});

      // console.log("tx.receipt.logs: ", tx.receipt.logs);

      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const lrcBalance21 = await getTokenBalanceAsync(lrc, order1Owner);

      const lrcBalance22 = await getTokenBalanceAsync(lrc, order2Owner);
      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);

      const neoBalance23 = await getTokenBalanceAsync(neo, order3Owner);
      const eosBalance23 = await getTokenBalanceAsync(eos, order3Owner);

      const eosBalance24 = await getTokenBalanceAsync(eos, feeRecepient);
      const neoBalance24 = await getTokenBalanceAsync(neo, feeRecepient);
      const lrcBalance24 = await getTokenBalanceAsync(lrc, feeRecepient);

      const simulator = new ProtocolSimulator(ring, lrcAddress, feeSelectionList, walletSplitPercentage);
      simulator.availableAmountSList = availableAmountSList;
      simulator.spendableLrcFeeList = spendableLrcFeeList;
      const feeAndBalanceExpected = simulator.caculateRingFeesAndBalances();

      assertNumberEqualsWithPrecision(eosBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceS, 6);
      assertNumberEqualsWithPrecision(lrcBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceB);
      assertNumberEqualsWithPrecision(lrcBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceS);
      assertNumberEqualsWithPrecision(neoBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceB);

      assertNumberEqualsWithPrecision(neoBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceS);
      assertNumberEqualsWithPrecision(eosBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceB);

      assertNumberEqualsWithPrecision(eosBalance24.toNumber(), feeAndBalanceExpected.totalFees[eosAddress]);
      assertNumberEqualsWithPrecision(neoBalance24.toNumber(), feeAndBalanceExpected.totalFees[neoAddress]);
      assertNumberEqualsWithPrecision(lrcBalance24.toNumber(), feeAndBalanceExpected.totalFees[lrcAddress]);

      await clear([eos, neo, lrc], [order1Owner, order2Owner, order3Owner, feeRecepient]);
    });

    it("should not be able to get margin split fee if miner's spendable lrc is less than order's lrcFee.",
    async () => {
      const feeSelectionList = [1, 1, 1];
      const ring = await ringFactory.generateSize3Ring03(order1Owner,
                                                         order2Owner,
                                                         order3Owner,
                                                         ringOwner,
                                                         300,
                                                         feeSelectionList);

      const availableAmountSList = [1000e18, 2006e18, 20e18];
      const spendableLrcFeeList = [0, 6e18, 1e18, 0];

      await eos.setBalance(order1Owner, availableAmountSList[0], {from: owner});
      await lrc.setBalance(order2Owner, availableAmountSList[1],  {from: owner});
      await neo.setBalance(order3Owner, availableAmountSList[2],  {from: owner});
      await lrc.setBalance(order3Owner, spendableLrcFeeList[2],  {from: owner});
      await lrc.setBalance(feeRecepient, spendableLrcFeeList[3],  {from: owner});

      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      const tx = await loopringProtocolImpl.submitRing(p.addressList,
                                                       p.uintArgsList,
                                                       p.uint8ArgsList,
                                                       p.vList,
                                                       p.rList,
                                                       p.sList,
                                                       p.feeRecepient,
                                                       {from: owner});

      // console.log("tx.receipt.logs: ", tx.receipt.logs);

      const eosBalance21 = await getTokenBalanceAsync(eos, order1Owner);
      const lrcBalance21 = await getTokenBalanceAsync(lrc, order1Owner);

      const lrcBalance22 = await getTokenBalanceAsync(lrc, order2Owner);
      const neoBalance22 = await getTokenBalanceAsync(neo, order2Owner);

      const neoBalance23 = await getTokenBalanceAsync(neo, order3Owner);
      const eosBalance23 = await getTokenBalanceAsync(eos, order3Owner);

      const eosBalance24 = await getTokenBalanceAsync(eos, feeRecepient);
      const neoBalance24 = await getTokenBalanceAsync(neo, feeRecepient);
      const lrcBalance24 = await getTokenBalanceAsync(lrc, feeRecepient);

      const simulator = new ProtocolSimulator(ring, lrcAddress, feeSelectionList, walletSplitPercentage);
      simulator.availableAmountSList = availableAmountSList;
      simulator.spendableLrcFeeList = spendableLrcFeeList;
      const feeAndBalanceExpected = simulator.caculateRingFeesAndBalances();
      // console.log("feeAndBalanceExpected", feeAndBalanceExpected);

      // console.log("eosBalance21:", eosBalance21);
      // console.log("lrcBalance21:", lrcBalance21);
      // console.log("lrcBalance22:", lrcBalance22);
      // console.log("neoBalance22:", neoBalance22);
      // console.log("neoBalance23:", neoBalance23);
      // console.log("eosBalance23:", eosBalance23);
      // console.log("eosBalance24:", eosBalance24);
      // console.log("neoBalance24:", neoBalance24);
      // console.log("lrcBalance24:", lrcBalance24);

      assertNumberEqualsWithPrecision(eosBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceS, 6);
      assertNumberEqualsWithPrecision(lrcBalance21.toNumber(), feeAndBalanceExpected.balances[0].balanceB);
      assertNumberEqualsWithPrecision(lrcBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceS);
      assertNumberEqualsWithPrecision(neoBalance22.toNumber(), feeAndBalanceExpected.balances[1].balanceB);

      assertNumberEqualsWithPrecision(neoBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceS);
      assertNumberEqualsWithPrecision(eosBalance23.toNumber(), feeAndBalanceExpected.balances[2].balanceB);

      assertNumberEqualsWithPrecision(eosBalance24.toNumber(), feeAndBalanceExpected.totalFees[eosAddress]);
      assertNumberEqualsWithPrecision(neoBalance24.toNumber(), feeAndBalanceExpected.totalFees[neoAddress]);
      assertNumberEqualsWithPrecision(lrcBalance24.toNumber(), feeAndBalanceExpected.totalFees[lrcAddress]);

      await clear([eos, neo, lrc], [order1Owner, order2Owner, order3Owner, feeRecepient]);
    });

    it("should not fill orders which are fully cancelled.", async () => {
      const feeSelectionList = [1, 1, 1];
      const ring = await ringFactory.generateSize3Ring03(order1Owner,
                                                         order2Owner,
                                                         order3Owner,
                                                         ringOwner,
                                                         400,
                                                         feeSelectionList);

      const availableAmountSList = [1000e18, 2006e18, 20e18];
      const spendableLrcFeeList = [0, 6e18, 1e18, 0];

      await eos.setBalance(order1Owner, availableAmountSList[0], {from: owner});
      await lrc.setBalance(order2Owner, availableAmountSList[1],  {from: owner});
      await neo.setBalance(order3Owner, availableAmountSList[2],  {from: owner});
      await lrc.setBalance(order3Owner, spendableLrcFeeList[2],  {from: owner});
      await lrc.setBalance(feeRecepient, spendableLrcFeeList[3],  {from: owner});

      const order = ring.orders[0];
      const cancelAmount = new BigNumber(1000e18);
      const addresses = [order.owner,
                         order.params.tokenS,
                         order.params.tokenB,
                         order.params.walletAddr,
                         order.params.authAddr,
                        ];

      const orderValues = [order.params.amountS,
                           order.params.amountB,
                           order.params.validSince,
                           order.params.validUntil,
                           order.params.lrcFee,
                           cancelAmount];

      await loopringProtocolImpl.cancelOrder(addresses,
                                             orderValues,
                                             order.params.buyNoMoreThanAmountB,
                                             order.params.marginSplitPercentage,
                                             order.params.v,
                                             order.params.r,
                                             order.params.s,
                                             {from: order.owner});

      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);

      try {
        await loopringProtocolImpl.submitRing(p.addressList,
                                              p.uintArgsList,
                                              p.uint8ArgsList,
                                              p.vList,
                                              p.rList,
                                              p.sList,
                                              p.feeRecepient,
                                              {from: owner});
      } catch (err) {
        const errMsg = `${err}`;
        assert(_.includes(errMsg, "Error: VM Exception while processing transaction: revert"),
               `Expected contract to throw, got: ${err}`);
      }

      await clear([eos, neo, lrc], [order1Owner, order2Owner, order3Owner, feeRecepient]);
    });

    it("should not fill orders which are cancelled by cancelAllOrders.", async () => {
      const feeSelectionList = [1, 1, 1];
      const ring = await ringFactory.generateSize3Ring03(order1Owner,
                                                         order2Owner,
                                                         order3Owner,
                                                         ringOwner,
                                                         500,
                                                         feeSelectionList);

      const availableAmountSList = [1000e18, 2006e18, 20e18];
      const spendableLrcFeeList = [0, 6e18, 1e18, 0];

      await eos.setBalance(order1Owner, availableAmountSList[0], {from: owner});
      await lrc.setBalance(order2Owner, availableAmountSList[1],  {from: owner});
      await neo.setBalance(order3Owner, availableAmountSList[2],  {from: owner});
      await lrc.setBalance(order3Owner, spendableLrcFeeList[2],  {from: owner});
      await lrc.setBalance(feeRecepient, spendableLrcFeeList[3],  {from: owner});

      const p = ringFactory.ringToSubmitableParams(ring, feeSelectionList, feeRecepient);
      await loopringProtocolImpl.cancelAllOrders(new BigNumber(currBlockTimeStamp), {from: order1Owner});
      try {
        await loopringProtocolImpl.submitRing(p.addressList,
                                              p.uintArgsList,
                                              p.uint8ArgsList,
                                              p.vList,
                                              p.rList,
                                              p.sList,
                                              p.feeRecepient,
                                              {from: owner});
      } catch (err) {
        const errMsg = `${err}`;
        assert(_.includes(errMsg, "Error: VM Exception while processing transaction: revert"),
               `Expected contract to throw, got: ${err}`);
      }

      await clear([eos, neo, lrc], [order1Owner, order2Owner, order3Owner, feeRecepient]);
    });
  });

  describe("cancelOrder", () => {
    it("should be able to set order cancelled amount by order owner", async () => {
      const feeSelectionList = [0, 0];
      const ring = await ringFactory.generateSize2Ring01(order1Owner,
                                                         order2Owner,
                                                         ringOwner,
                                                         feeSelectionList);

      const order = ring.orders[0];
      const cancelAmount = new BigNumber(100e18);

      const addresses = [order.owner,
                         order.params.tokenS,
                         order.params.tokenB,
                         order.params.walletAddr,
                         order.params.authAddr];

      const orderValues = [order.params.amountS,
                           order.params.amountB,
                           order.params.validSince,
                           order.params.validUntil,
                           order.params.lrcFee,
                           cancelAmount];

      const cancelledOrFilledAmount0 = await tokenTransferDelegate.cancelledOrFilled(order.params.orderHashHex);
      const tx = await loopringProtocolImpl.cancelOrder(addresses,
                                                        orderValues,
                                                        order.params.buyNoMoreThanAmountB,
                                                        order.params.marginSplitPercentage,
                                                        order.params.v,
                                                        order.params.r,
                                                        order.params.s,
                                                        {from: order.owner});

      const cancelledOrFilledAmount1 = await tokenTransferDelegate.cancelledOrFilled(order.params.orderHashHex);
      assert.equal(cancelledOrFilledAmount1.minus(cancelledOrFilledAmount0).toNumber(),
        cancelAmount.toNumber(), "cancelled amount not match");
    });

    it("should not be able to cancell order by other address", async () => {
      const feeSelectionList = [0, 0];
      const ring = await ringFactory.generateSize2Ring01(order1Owner,
                                                         order2Owner,
                                                         ringOwner,
                                                         feeSelectionList);

      const order = ring.orders[0];
      const cancelAmount = new BigNumber(100e18);

      const addresses = [order.owner,
                         order.params.tokenS,
                         order.params.tokenB,
                         order.params.walletAddr,
                         order.params.authAddr];

      const orderValues = [order.params.amountS,
                           order.params.amountB,
                           order.params.validSince,
                           order.params.validUntil,
                           order.params.lrcFee,
                           cancelAmount];
      try {
        const tx = await loopringProtocolImpl.cancelOrder(addresses,
                                                          orderValues,
                                                          order.params.buyNoMoreThanAmountB,
                                                          order.params.marginSplitPercentage,
                                                          order.params.v,
                                                          order.params.r,
                                                          order.params.s,
                                                          {from: order2Owner});
      } catch (err) {
        const errMsg = `${err}`;
        assert(_.includes(errMsg, "Error: VM Exception while processing transaction: revert"),
               `Expected contract to throw, got: ${err}`);
      }
    });
  });

  describe("cancelAllOrders", () => {
    it("should be able to set cutoffs", async () => {
      await loopringProtocolImpl.cancelAllOrders(new BigNumber(1508566125), {from: order2Owner});
      const cutoff = await tokenTransferDelegate.cutoffs(order2Owner);
      assert.equal(cutoff.toNumber(), 1508566125, "cutoff not set correctly");
    });

    it("should be able to prevent orders from being traded by cutoffs.", async () => {
      await loopringProtocolImpl.cancelAllOrders(new BigNumber(currBlockTimeStamp),
                                                 {from: order2Owner});

      const ring = await ringFactory.generateRingForCancel(order1Owner,
                                                           order2Owner,
                                                           ringOwner,
                                                           [0, 0]);

      await lrc.setBalance(order1Owner, web3.toWei(100),   {from: owner});
      await eos.setBalance(order1Owner, web3.toWei(10000), {from: owner});
      await lrc.setBalance(order2Owner, web3.toWei(100),   {from: owner});
      await neo.setBalance(order2Owner, web3.toWei(1000),  {from: owner});
      await lrc.setBalance(feeRecepient, 0, {from: owner});

      const p = ringFactory.ringToSubmitableParams(ring, [0, 0], feeRecepient);

      const ethOfOwnerBefore = await getEthBalanceAsync(owner);

      try {
        await loopringProtocolImpl.submitRing(p.addressList,
                                              p.uintArgsList,
                                              p.uint8ArgsList,
                                              p.vList,
                                              p.rList,
                                              p.sList,
                                              p.feeRecepient,
                                              {from: owner});
      } catch (err) {
        const errMsg = `${err}`;
        assert(_.includes(errMsg, "Error: VM Exception while processing transaction: revert"),
               `Expected contract to throw, got: ${err}`);
      }

    });

  });

  describe("cancelAllOrdersByTradingPair", () => {
    it("should be able to set trading pair cutoffs", async () => {
      await loopringProtocolImpl.cancelAllOrdersByTradingPair(eosAddress,
                                                              neoAddress,
                                                              new BigNumber(1508566125),
                                                              {from: order2Owner});

      const cutoff = await loopringProtocolImpl.getTradingPairCutoffs(order2Owner,
                                                                      eosAddress,
                                                                      neoAddress);

      assert.equal(cutoff.toNumber(), 1508566125, "trading pair cutoff not set correctly");
    });

    it("should be able to prevent orders from being traded by tradingPairCutoffs", async () => {
      await loopringProtocolImpl.cancelAllOrdersByTradingPair(neoAddress,
                                                              eosAddress,
                                                              new BigNumber(currBlockTimeStamp),
                                                              {from: order2Owner});
      const ring = await ringFactory.generateRingForCancel(order1Owner,
                                                           order2Owner,
                                                           ringOwner,
                                                           [1, 1]);

      await lrc.setBalance(order1Owner, web3.toWei(100),   {from: owner});
      await eos.setBalance(order1Owner, web3.toWei(10000), {from: owner});
      await lrc.setBalance(order2Owner, web3.toWei(100),   {from: owner});
      await neo.setBalance(order2Owner, web3.toWei(1000),  {from: owner});
      await lrc.setBalance(feeRecepient, 0, {from: owner});

      const p = ringFactory.ringToSubmitableParams(ring, [0, 0], feeRecepient);

      const ethOfOwnerBefore = await getEthBalanceAsync(owner);

      try {
        await loopringProtocolImpl.submitRing(p.addressList,
                                              p.uintArgsList,
                                              p.uint8ArgsList,
                                              p.vList,
                                              p.rList,
                                              p.sList,
                                              p.feeRecepient,
                                              {from: owner});
      } catch (err) {
        const errMsg = `${err}`;
        assert(_.includes(errMsg, "Error: VM Exception while processing transaction: revert"),
               `Expected contract to throw, got: ${err}`);
      }

    });

  });

});
