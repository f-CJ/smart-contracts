pragma solidity 0.5.7;

import "../Plotus.sol";

contract MockPlotus is Plotus {

	mapping(address => bytes32) marketId;
	/**
    * @dev Creates the new market.
    * @param _marketType The type of the market.
    * @param _marketCurrencyIndex the index of market currency.
    */
    function _createMarket(uint256 _marketType, uint _marketCurrencyIndex) internal {
      require(!marketCreationPaused);
      MarketTypeData storage _marketTypeData = marketTypes[_marketType];
      MarketCurrency memory _marketCurrencyData = marketCurrencies[_marketCurrencyIndex];
      address payable _market = _generateProxy(marketImplementation);
      isMarket[_market] = true;
      markets.push(_market);
      currentMarketTypeCurrency[_marketType][_marketCurrencyIndex] = _market;
      (uint256 _minValue, uint256 _maxValue) = _calculateOptionRange();
      IMarket(_market).initiate(_marketTypeData.startTime, _marketTypeData.predictionTime, _marketTypeData.settleTime, _minValue, _maxValue, _marketCurrencyData.currencyName, _marketCurrencyData.currencyAddress, _marketCurrencyData.oraclizeType, _marketCurrencyData.oraclizeSource, _marketCurrencyData.isERCToken);
      emit MarketQuestion(_market, _marketCurrencyData.currencyName, _marketType, _marketTypeData.startTime);
      _marketTypeData.startTime =_marketTypeData.startTime.add(_marketTypeData.predictionTime);
      bytes32 _oraclizeId = keccak256(abi.encodePacked(_marketType, _marketCurrencyIndex));
      marketOracleId[_oraclizeId] = MarketOraclize(_market, _marketType, _marketCurrencyIndex);
      marketId[_market] = _oraclizeId;
    }

    /**
    * @dev callback for result declaration of market.
    * @param myid The orcalize market result id.
    * @param result The current price of market currency.
    */
    function __callback(bytes32 myid, string memory result) public {
      //Check oraclise address
      strings.slice memory s = result.toSlice();
      strings.slice memory delim = "-".toSlice();
      uint[] memory parts = new uint[](s.count(delim) + 1);
      for (uint i = 0; i < parts.length; i++) {
          parts[i] = parseInt(s.split(delim).toString());
      }
      _createMarket(marketOracleId[myid].marketType, marketOracleId[myid].marketCurrencyIndex);
      delete marketOracleId[myid];
    }

    function getMarketOraclizeId(address _marketAddress) public view returns(bytes32){
    	return marketId[_marketAddress];
    }
}