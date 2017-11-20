# Loopring Protocol Smart Contracts

## About This Branch

This branch (version2) will support ERC223 and cross trade between ERC20 and ERC223 tokens.

## Compile


If you are using Windows:
```
npm install --global --production windows-build-tools
```

Then run the following commands from project's root directory:
 
```
npm install
npm run compile
```
    
## Run Unit Tests  
* run `npm run testrpc` from project's root directory in terminal.  
* run `npm run test` from project's root directory in another terminal window.  
* run single test: `npm run test -- transpiled/test/xxx.js`

## Run Unit Tests inside Docker

If you prefer to use docker, you can install docker first, then run the following:

```
npm run docker
```

If you do not have node/npm installed but still wish to use docker, you can run the commands manually:

```
docker-compose up --build --abort-on-container-exit
docker-compose logs -f test
```

The logs command is optional but will give you an easy to read output of the tests without the output from testrpc mixed in (though the combination of both is good for debugging and is why they're not being silenced.)
