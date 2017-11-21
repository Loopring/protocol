import { BigNumber } from "bignumber.js";

export interface OrderParams {
  loopringProtocol: string;
  tokenS: string;
  tokenB: string;
  amountS: BigNumber;
  amountB: BigNumber;
  timestamp: BigNumber;
  ttl: BigNumber;
  salt: BigNumber;
  lrcFee: BigNumber;
  marginSplitAndNoMoreB: number;
  scaledAmountS?: number;
  scaledAmountB?: number;
  rateAmountS?: number;
  rateAmountB?: number;
  fillAmountS?: number;
  orderHashHex?: string;
  v?: number;
  r?: string;
  s?: string;
}

export interface LoopringSubmitParams {
  addressList: string[][];
  uintArgsList: BigNumber[][];
  uint8ArgsListAndNoMoreBList: number[][];
  vList: number[];
  rList: string[];
  sList: string[];
  ringOwner: string;
  feeRecepient: string;
}

export interface FeeItem {
  fillAmountS: number;
  feeLrc: number;
  feeS: number;
  feeB: number;
  lrcReward: number;
}

export interface BalanceItem {
  balanceS: number;
  balanceB: number;
}
