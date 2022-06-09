### Requirements
* NodeJS 16.10.0 or later
* npm 8.1.0 or later 
* hardhat 2.8.3 or later
### Installation
* npm i
### Run tests
* npx hardhat test
### Run tests with coverage report
* npx hardhat coverage
### Deploy and verification 

You need to create an .env file and enter your data into it, as indicated in .env.example

* npx hardhat run scripts/deploy.js --network "your-network"

## Description of how limit orders work

To setup limit orders such as stop-loss and take-profit we created the next functionality:
1. Added events in the Trading.sol smart contract:

    - NewStopOrder
    - NewTakeOrder
    - PositionStopUpdated
    - PositionTakeUpdated

2. Added functions in the Trading.sol smart contract:

    - submitStopOrder
    - submitTakeOrder
    - settleStopOrder
    - settleTakeOrder

#### submitStopOrder

To set up stop-loss a user needs to call the submitStopOrder function with next parameters:

- bytes32 productId
- address currency
- bool isLong
- uint64 stop

This function takes a position (calculates from transfered data) and checks if this position exists. Also checks if the stop argument is in the correct range. If everything is ended correctly, this function returns NewStopOrder event.
Event NewStopOrder notifies the backend. Backend using darkOracle to call the function settleStopOrder Oracle.sol, that will end setting up the order. Final event PositionStopUpdated message backend that stop-loss has set up.

#### submitTakeOrder 

To set up stop-loss a user needs to call the submitStopOrder function with next parameters:

- bytes32 productId
- address currency
- bool isLong
- uint64 take

This function takes a position (calculates from transfered data) and checks if this position exists. Also checks if the take argument is in the correct range. If everything is ended correctly, this function returns NewTakeOrder event.
Event NewTakeOrder notifies the backend. Backend using darkOracle to call the function settleTakeOrder Oracle.sol, that will end setting up the order. Final event PositionTakeUpdated message backend that take-profit has set up.

#### settleStopOrder

This function is used for the final setup of the stop-loss order, this function can be called only by oracle. Emits the PositionStopUpdated event at the end.
settleTakeOrder
This function is used for the final setup of the take-profit order, this function can be called only by oracle. Emits the PositionTakeUpdated event at the end.

##### These functions were added in the Oracle.sol smart contract:

- settleStopOrders
- settleTakeOrders

These functions can be called only by darkOracle, they use interface of the Trading.sol smart contract to set up the stop-loss and take-profit orders through the settleStopOrder and settleTakeOrder functions of the Trading.sol smart contract.


## Adding new currency

Also the possibility to add new currency for trading was added. The Factory.sol smart contract was developed for this purpose. At the very beginning you need to set router address using the setRouter function. The addToken function needs to be used to add new currency.

#### addToken:

- address currency
- uint256 decimals
- uint256 share

This function adds address of the new token, checks if this address is valid. Also checks that pool hasn't been created yet. After it the router smart contract creates the pool for the new token, poolRewards, ParifiReward, configures setPoolShare and setParfiShare. Emits the TokenAdded event at the end.

#### Addresses of deployed contracts can be seen in /scripts/deployedContractsOutput.json

