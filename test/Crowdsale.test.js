const Crowdsale = artifacts.require('Crowdsale');
const PlotusToken = artifacts.require('PlotXToken');
const TokenMock = artifacts.require('TokenMock');
const DummyTokenMock = artifacts.require('DummyTokenMock');

const assertRevert = require("./utils/assertRevert.js").assertRevert;
const increaseTime = require("./utils/increaseTime.js").increaseTime;
const latestTime = require("./utils/latestTime.js").latestTime;
const encode = require("./utils/encoder.js").encode;
const { toHex, toWei } = require("./utils/ethTools.js");
const expectEvent = require("./utils/expectEvent");
const Web3 = require("web3");
const { assert } = require("chai");
const web3 = new Web3();
let maxAllowance = "115792089237316195423570985008687907853269984665640564039457584007913129639935";
const nullAddress = "0x0000000000000000000000000000000000000000";

let crowdsale;
let plotusToken;
let usdcTok;
let usdtTok;
let usdcTokDummy;
let usdtTokDummy;
let dummyCrowdsale;
let walletAdd;


contract("Crowdsale", (addresses) => {
    let user1 = addresses[0], user2 = addresses[1], wallet = addresses[2];
  before(async function () {
    let nowTime = await latestTime();
    let endTime = nowTime/1 + 3600*24*7;
    plotusToken = await PlotusToken.new(toWei(10000000));
    usdcTok = await TokenMock.new("USDC","USDC");
    usdtTok = await TokenMock.new("USDT","USDT");
    usdcTokDummy = await DummyTokenMock.new("USDC","USDC");
    usdtTokDummy = await DummyTokenMock.new("USDT","USDT");
    crowdsale = await Crowdsale.new(user1, wallet, plotusToken.address, usdcTok.address, usdtTok.address, nowTime/1 + 3600, endTime, (nowTime), nowTime/1 + 3600);
    dummyCrowdsale = await Crowdsale.new(user1, user1, plotusToken.address, usdcTokDummy.address, usdtTokDummy.address, nowTime, endTime, (nowTime/1 - 3600), nowTime);
    await plotusToken.transfer(crowdsale.address, toWei("5000000"));
    await plotusToken.transfer(dummyCrowdsale.address, toWei("100"));
    await usdcTok.approve(crowdsale.address, maxAllowance);
    await usdtTok.approve(crowdsale.address, maxAllowance);
    await usdcTokDummy.approve(dummyCrowdsale.address, maxAllowance);
    await usdtTokDummy.approve(dummyCrowdsale.address, maxAllowance);
    await usdcTok.mint(toWei(100));
    await usdtTok.mint(toWei(100));
    await usdcTokDummy.mint(toWei(100));
    await usdtTokDummy.mint(toWei(100));
    
  });
  describe('Crowdsale', function () {

    it('Crowdsale contract should initialize correctly', async function () {
      assert.equal(await crowdsale.token(), plotusToken.address);
      assert.equal(await crowdsale.wallet(), wallet);
      assert.equal(await crowdsale.tokenUSDC(), usdcTok.address);
      assert.equal(await crowdsale.tokenUSDT(), usdtTok.address);
      assert.equal(await crowdsale.spendingLimitPublicSale(), toWei(10000));
      assert.equal(await crowdsale.tokenSold(), 0);
      assert.equal(await crowdsale.slope(), 4000000000);
      assert.equal(await crowdsale.startRate(), toWei(0.07));
      assert.equal(await crowdsale.authorisedToWhitelist(), user1);
    });

    it('Should revert if ERC20 transfer returns false', async function () {
      await dummyCrowdsale.addUserToWhiteList(user1,1);
      await assertRevert(dummyCrowdsale.buyTokens(user1, toWei(10), usdtTokDummy.address));
      await usdtTokDummy.mint(dummyCrowdsale.address, toWei(1));
      await assertRevert(dummyCrowdsale.forwardFunds());
      await usdcTokDummy.mint(dummyCrowdsale.address, toWei(1));
      await assertRevert(dummyCrowdsale.forwardFunds());
    });

    it('Should forward funds if stuck', async function () {
      await usdtTok.transfer(crowdsale.address, toWei(1));
      await usdcTok.transfer(crowdsale.address, toWei(1));
      let beforeBalUSDT = await usdtTok.balanceOf(crowdsale.address);
      let beforeBalUSDC = await usdcTok.balanceOf(crowdsale.address);
      await crowdsale.forwardFunds();
      let afterBalUSDT = await usdtTok.balanceOf(crowdsale.address);
      let afterBalUSDC = await usdcTok.balanceOf(crowdsale.address);
      assert.equal(beforeBalUSDC - afterBalUSDC, toWei(1));
      assert.equal(beforeBalUSDT - afterBalUSDT, toWei(1));
    });

    it('requires a non-null authorised, token and wallet addresses', async function () {
      let nowTime = await latestTime();
      let endTime = nowTime/1 + 3600*24*7;
      await assertRevert(
        Crowdsale.new(nullAddress, user1, plotusToken.address, usdcTok.address, usdtTok.address, nowTime, endTime, endTime, endTime/1+3600*24*7),
        'Crowdsale: wallet is the zero address'
      );

      await assertRevert(
        Crowdsale.new(user1, nullAddress, plotusToken.address, usdcTok.address, usdtTok.address, nowTime, endTime, endTime, endTime/1+3600*24*7),
        'Crowdsale: wallet is the zero address'
      );
      await assertRevert(
        Crowdsale.new(user1, user1, nullAddress, usdcTok.address, usdtTok.address, nowTime, endTime, endTime, endTime/1+3600*24*7),
        'Crowdsale: token is the zero address'
      );
      await assertRevert(
        Crowdsale.new(user1, user1, plotusToken.address, nullAddress, usdtTok.address, nowTime, endTime, endTime, endTime/1+3600*24*7),
        'Crowdsale: usdc token is the zero address'
      );
      await assertRevert(
        Crowdsale.new(user1, user1, plotusToken.address, usdcTok.address, nullAddress, nowTime, endTime, endTime, endTime/1+3600*24*7),
        'Crowdsale: usdt token is the zero address'
      );
    });

    describe('Reverts', function () {
        it('should revert if beneficiary address is null', async function () {
          await assertRevert(crowdsale.buyTokens(nullAddress, toWei(10), usdcTok.address));
        });
        it('should revert if tries to spend 0 amount', async function () {
          await assertRevert(crowdsale.buyTokens(user1, 0, usdcTok.address));
        });
        it('should revert if tries to spend invalid asset', async function () {
          await assertRevert(crowdsale.buyTokens(user1, toWei(10), plotusToken.address));
        });
        it('should revert if beneficiary is not whitelisted', async function () {
          await assertRevert(crowdsale.buyTokens(user1, toWei(10), usdcTok.address));
        });
        it('should revert if Non-authorised user tries to whitelist', async function () {
          await assertRevert(crowdsale.addUserToWhiteList(user1, 1, {from:user2}));
        });
        it('should revert if Non-authorised user tries to blacklist', async function () {
          await assertRevert(crowdsale.removeUserFromWhiteList(user1, {from:user2}));
        });
    });

    describe('accepting payments', function () {
      before(async function () {
        assert.equal(await crowdsale.whitelisted(user1), false);
        await crowdsale.addUserToWhiteList(user1,1);
        assert.equal(await crowdsale.whitelisted(user1), true);
      });
      describe('buyTokens', function () {
        it('should accept usdc payments', async function () {
          let beforeBalWalletUSDC = await usdcTok.balanceOf(wallet);
          let beforeBalUserUSDC = await usdcTok.balanceOf(user1);
          let beforeUserSpent = await crowdsale.userSpentSoFar(user1);
          await crowdsale.buyTokens(user1, toWei(10), usdcTok.address);
          let afterBalWalletUSDC = await usdcTok.balanceOf(wallet);
          let afterBalUserUSDC = await usdcTok.balanceOf(user1);
          let afterUserSpent = await crowdsale.userSpentSoFar(user1);
          assert.equal(beforeBalUserUSDC - afterBalUserUSDC, toWei(10));
          assert.equal(afterBalWalletUSDC - beforeBalWalletUSDC, toWei(10));
        });

        it('should accept usdt payments', async function () {
          let beforeBalWalletUSDT = await usdtTok.balanceOf(wallet);
          let beforeBalUserUSDT = await usdtTok.balanceOf(user1);
          let beforeUserSpent = await crowdsale.userSpentSoFar(user1);
          await crowdsale.buyTokens(user1, toWei(10), usdtTok.address);
          let afterBalWalletUSDT = await usdtTok.balanceOf(wallet);
          let afterBalUserUSDT = await usdtTok.balanceOf(user1);
          let afterBalCrowdsalePlot = await plotusToken.balanceOf(crowdsale.address);
          let afterBalUserPlot = await plotusToken.balanceOf(user1);
          let afterUserSpent = await crowdsale.userSpentSoFar(user1);
          assert.equal(beforeBalUserUSDT - afterBalUserUSDT, toWei(10));
          assert.equal(afterBalWalletUSDT - beforeBalWalletUSDT, toWei(10));
        });

        it('reverts if tries to spend more than limit', async function () {
          await usdcTok.mint(toWei(10000));
          await plotusToken.transfer(crowdsale.address, toWei("10000"));
          await assertRevert(crowdsale.buyTokens(user1, toWei(10000), usdcTok.address));
        });

        it('reverts if tries call transferLeftOverTokens() while sale is active', async function () {
          await assertRevert(crowdsale.transferLeftOverTokens());
        });


        it('reverts if not prefered whitelisted', async function () {
          await assertRevert(crowdsale.buyTokens(user1, toWei(10000), usdcTok.address));
        });

        it('Authorised address should be able to blacklist user', async function () {
          let beforeBalUserPlot = await plotusToken.balanceOf(user1);
          assert.equal(await crowdsale.whitelisted(user1), true);
          await crowdsale.removeUserFromWhiteList(user1);
          let afterBalUserPlot = await plotusToken.balanceOf(user1);
          assert.equal(await crowdsale.whitelisted(user1), false);
          assert.equal(beforeBalUserPlot/1, afterBalUserPlot/1);
        });

        it('Should revert if tries to  buy tokens after sale', async function () {
          await increaseTime(3600*24*8);
          await assertRevert(crowdsale.buyTokens(user1, toWei(10), usdtTok.address));
        });

        it('Should able to trasfer left over tokens after sale ends', async function () {
          await crowdsale.transferLeftOverTokens();
        });

      });
    });
  });

  describe('Crowdsale: Bonding curve test cases', function () {
    
    let web3;
    let crowdsaleNew;
    let plotusTokenNew;
    let allAccounts=[];
    before(async function () {
      
      allAccounts = addresses;
    walletAdd = allAccounts[66];
    let nowTime = await latestTime();
    let endTime = nowTime/1 + 3600*24*7;
    plotusTokenNew = await PlotusToken.new(toWei(10000000));
    crowdsaleNew = await Crowdsale.new(user1, walletAdd, plotusTokenNew.address, usdcTok.address, usdtTok.address, nowTime/1 + 3600, endTime, nowTime, nowTime/1 + 3600);
    await plotusTokenNew.transfer(crowdsaleNew.address, toWei("5000000"));
    await usdcTok.approve(crowdsaleNew.address, maxAllowance);
    await usdtTok.approve(crowdsaleNew.address, maxAllowance);
    await usdcTok.mint(toWei(1000));
    await usdtTok.mint(toWei(1000));
  });

  it('User should get correct tokens according to rate', async function () {

    let usdAmount = [toWei(220),toWei(150),toWei(200),toWei(220),toWei(150),toWei(200),toWei(220),toWei(150),toWei(200),toWei(8000),toWei(9000),toWei(10000),toWei(1000),toWei(2000),toWei(3000),toWei(4000),toWei(5000),toWei(6000),toWei(7000),toWei(8000),toWei(9000),toWei(10000),toWei(1000),toWei(2000),toWei(3000),toWei(4000),toWei(5000),toWei(6000),toWei(7000),toWei(8000),toWei(9000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000),toWei(10000)];
    let returnTokens = [3142,2142,2856,3142,2142,2856,3142,2142,2857,114126,127561,140717,13961,27900,41785,55584,69267,82802,96163,109323,122258,134946,13397,26774,40104,53358,66508,79529,92394,105081,117567,129832,128963,128110,127275,126455,125652,124863,124089,123330,122584,121851,121132,120425,119731,119048,118377,117717,117068,116430,115802,115184,114576,113978,113388,112808,112237,111674,1873];
    let j = 0;
    for(let i=0;i<59;i++)
    {
      let spendingLimit = toWei(100);
      let _user = allAccounts[j];
      let _userBalPlot = await plotusTokenNew.balanceOf(_user);
      await usdtTok.approve(crowdsaleNew.address, maxAllowance, {from:_user});
      await crowdsaleNew.addUserToWhiteList(_user,await crowdsaleNew.saleType());

      await usdtTok.burnAll({from:_user});
      let _userBalUsd = await usdtTok.balanceOf(_user);
      await usdtTok.mint(usdAmount[i]);
      await usdtTok.transfer(_user, usdAmount[i]);
      await crowdsaleNew.buyTokens(_user, usdAmount[i], usdtTok.address, {from:_user});
      let _userBalPlotAfter = await plotusTokenNew.balanceOf(_user);
      let _userBalUsdAfter = await usdtTok.balanceOf(_user);
      assert.isBelow(Math.floor((_userBalPlotAfter - _userBalPlot)/1e18) - returnTokens[i], 3);
      let returnUSD = 0;
      if(i == 58)
      {
        returnUSD = 9832;
      }
      assert.equal(Math.floor((_userBalUsdAfter - _userBalUsd)/1e18), returnUSD);
      if(usdAmount[i+1]/1+(await crowdsaleNew.userSpentSoFar(_user))/1> spendingLimit)
      {
        j++;
      }
      if(i==8){
        spendingLimit = toWei(10000);
        await increaseTime(await crowdsaleNew._preSaleEndTime() - await latestTime());
      }
    }
  });

  it('should revert if tries to spend more than limit', async function () {
    await assertRevert(crowdsaleNew.buyTokens(addresses[50], toWei(10), usdtTok.address, {from:addresses[50]}));
  });

  it('should revert if beneficiary is not whitelisted', async function () {
    await crowdsaleNew.removeUserFromWhiteList(addresses[0])
    await assertRevert(crowdsaleNew.buyTokens(addresses[0], toWei(10), usdcTok.address));
  });

  });

});
