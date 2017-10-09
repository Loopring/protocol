import * as BigNumber from 'bignumber.js';

export interface OrderParams {
  loopringProtocol: string;
  tokenS: string;
  tokenB: string;
  amountS: BigNumber.BigNumber;
  amountB: BigNumber.BigNumber;
  timestamp: number;
  ttl: number;
  salt: number;
  lrcFee: BigNumber.BigNumber;
  buyNoMoreThanAmountB: boolean;
  marginSplitPercentage: number;
  orderHashHex?: string;
  v?: number;
  r?: string;
  s?: string;
}
