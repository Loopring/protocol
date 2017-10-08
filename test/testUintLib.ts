import { BigNumber } from 'bignumber.js';
var UintLib = artifacts.require('./lib/UintLib');


contract('UintLib', (accounts: string[])=>{

  let uintLib: any;

  before(async () => {
    uintLib = await UintLib.deployed();
  });


  describe('pow function', () => {

    it('works', async () => {
	    assert.equal(
	    	(await uintLib.pow(
	    		new BigNumber(2),
	    		new BigNumber(3)))
	    	.equals(new BigNumber(8)),
	    	true, "2^3 == 8 failed");

	    assert.equal(
	    	(await uintLib.pow(
	    		new BigNumber(0),
	    		new BigNumber(2)))
	    	.equals(new BigNumber(0)),
	    	true, "0^2 == 0 failed");

		assert.equal(
	    	(await uintLib.pow(
	    		new BigNumber(1),
	    		new BigNumber(100)))
	    	.equals(new BigNumber(1)),
	    	true, "1^100 == 1 failed");
		assert.equal(
	    	(await uintLib.pow(
	    		new BigNumber(3),
	    		new BigNumber(16)))
	    	.equals(new BigNumber(43046721)),
	    	true, "3^16 == 43046721 failed");

		assert.equal(
	    	(await uintLib.pow(
	    		new BigNumber('9223372036854775807'),
	    		new BigNumber(3)))
	    	.equals(new BigNumber('784637716923335095224261902710254454442933591094742482943')),
	    	true, "3^16 == 43046721 failed");
    });
  });


  describe('nthRoot function', () => {

    it('works', async () => {
    	assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber(1),
	    		new BigNumber(10)))
	    	.equals(new BigNumber(1)),
	    	true, "1^1/10 == 1 failed");

     	assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber(0),
	    		new BigNumber(10)))
	    	.equals(new BigNumber(0)),
	    	true, "0^1/10 == 0 failed");

	    assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber(8),
	    		new BigNumber(3)))
	    	.equals(new BigNumber(2)),
	    	true, "8^1/3 == 2 failed");

		assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber(2),
	    		new BigNumber(3)))
	    	.equals(new BigNumber(1)),
	    	true, "2^1/3 == 1 failed");

		assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber(7),
	    		new BigNumber(3)))
	    	.equals(new BigNumber(1)),
	    	true, "7^1/3 == 1 failed");

		assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber(228886641),
	    		new BigNumber(4)))
	    	.equals(new BigNumber(123)),
	    	true, "228886641^1/4 == 123 failed");

		assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber(228886641 - 1),
	    		new BigNumber(4)))
	    	.equals(new BigNumber(122)),
	    	true, "228886640^1/4 == 122 failed");

		assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber('784637716923335095224261902710254454442933591094742482943'),
	    		new BigNumber(3)))
	    	.equals(new BigNumber('9223372036854775807')),
	    	true, "784637716923335095224261902710254454442933591094742482943^1/3 == 9223372036854775807 failed");

		assert.equal(
	    	(await uintLib.nthRoot(
	    		new BigNumber('784637716923335095224261902710254454442933591094742482942'),
	    		new BigNumber(3)))
	    	.equals(new BigNumber('9223372036854775806')),
	    	true, "784637716923335095224261902710254454442933591094742482942^1/3 == 9223372036854775806 failed");
    });
  });
})
