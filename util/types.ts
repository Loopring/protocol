import { BigNumber } from "bignumber.js";

export interface OrderParams {
  loopringProtocol: string;
  tokenS: string;
  tokenB: string;
  amountS: BigNumber;
  amountB: BigNumber;
  validSince: BigNumber;
  validUntil: BigNumber;
  lrcFee: BigNumber;
  buyNoMoreThanAmountB: boolean;
  marginSplitPercentage: number;
  authAddr: string;
  walletId: number;
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
  uint8ArgsList: number[][];
  buyNoMoreThanAmountBList: boolean[];
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

export interface SignResult {
  v: number;
  r: string;
  s: string;
}
