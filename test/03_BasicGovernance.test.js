const OwnedUpgradeabilityProxy = artifacts.require('OwnedUpgradeabilityProxy');
const Governance = artifacts.require("Governance");
const MemberRoles = artifacts.require("MemberRoles");
const ProposalCategory = artifacts.require("ProposalCategory");
const TokenController = artifacts.require("TokenController");
const NXMaster = artifacts.require("Master");
const PlotusToken = artifacts.require("MockPLOT");
const assertRevert = require("./utils/assertRevert.js").assertRevert;
const increaseTime = require("./utils/increaseTime.js").increaseTime;
const encode = require("./utils/encoder.js").encode;
const { toHex, toWei } = require("./utils/ethTools.js");
const expectEvent = require("./utils/expectEvent");
const gvProp = require("./utils/gvProposal.js").gvProposal;
const Web3 = require("web3");
const { assert } = require("chai");
const gvProposalWithIncentive = require("./utils/gvProposal.js").gvProposalWithIncentive;
const gvProposalWithIncentiveViaTokenHolder = require("./utils/gvProposal.js").gvProposalWithIncentiveViaTokenHolder;
const web3 = new Web3();
const AdvisoryBoard = "0x41420000";
let maxAllowance = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

let gv;
let cr;
let pc;
let nxms;
let proposalId;
let pId;
let mr;
let nxmToken;
let tc;
let td;

contract("Governance", ([ab1, ab2, ab3, ab4, mem1, mem2, mem3, mem4, mem5, mem6, mem7, notMember, dr1, dr2, dr3]) => {
  before(async function () {
    nxms = await OwnedUpgradeabilityProxy.deployed();
    nxms = await NXMaster.at(nxms.address);
    nxmToken = await PlotusToken.deployed();
    let address = await nxms.getLatestAddress(toHex("GV"));
    gv = await Governance.at(address);
    address = await nxms.getLatestAddress(toHex("PC"));
    pc = await ProposalCategory.at(address);
    address = await nxms.getLatestAddress(toHex("MR"));
    mr = await MemberRoles.at(address);
    tc = await TokenController.at(await nxms.getLatestAddress(toHex("MR")));
  });

  it("15.1 Should be able to change tokenHoldingTime manually", async function () {
    await assertRevert(gv.updateUintParameters(toHex("GOVHOLD"), 3000));
  });

  it("15.2 Only Advisory Board members are authorized to categorize proposal", async function () {
    let allowedToCategorize = await gv.allowedToCatgorize();
    assert.equal(allowedToCategorize.toNumber(), 1);
  });

  it("15.3 Should not allow unauthorized to change master address", async function () {
    await assertRevert(gv.setMasterAddress({ from: notMember }));
    // await gv.changeDependentContractAddress();
  });

  it("15.4 Should not allow unauthorized to create proposal", async function () {
    await assertRevert(
      gv.createProposal("Proposal", "Description", "Hash", 0, {
        from: notMember,
      })
    );
    await assertRevert(
      gv.createProposalwithSolution("Add new member", "Add new member", "hash", 9, "", "0x", { from: notMember })
    );
  });

  it("Should not allow to add in AB if not member", async function () {
    await assertRevert(mr.addInitialABandDRMembers([ab2, ab3, ab4], []));
  });

  it("15.5 Should create a proposal", async function () {
    let propLength = await gv.getProposalLength();
    proposalId = propLength.toNumber();
    await gv.createProposal("Proposal1", "Proposal1", "Proposal1", 0); //Pid 1
    let propLength2 = await gv.getProposalLength();
    assert.isAbove(propLength2.toNumber(), propLength.toNumber(), "Proposal not created");
  });

  it("15.6 Should not allow unauthorized person to categorize proposal", async function () {
    await assertRevert(gv.categorizeProposal(proposalId, 1, 0, { from: notMember }));
  });

  it("15.7 Should not categorize under invalid category", async function () {
    await assertRevert(gv.categorizeProposal(proposalId, 0, 0));
    await assertRevert(gv.categorizeProposal(proposalId, 35, 0));
  });

  it("Should not open proposal for voting before categorizing", async () => {
    await assertRevert(gv.submitProposalWithSolution(proposalId, "Addnewmember", "0x4d52"));
  });

  it("Should categorize proposal", async function () {
    assert.equal(await mr.checkRole(ab1, 1), 1);
    await gv.categorizeProposal(proposalId, 2, 0);
    let proposalData = await gv.proposal(proposalId);
    assert.equal(proposalData[1].toNumber(), 2, "Proposal not categorized");
  });

  it("Should allow only owner to open proposal for voting", async () => {
    // await gv.categorizeProposal(proposalId, 2, 0);
    await gv.proposal(proposalId);
    await pc.category(9);
    await assertRevert(gv.submitVote(proposalId, 1));
    await assertRevert(
      gv.submitProposalWithSolution(
        proposalId,
        "Addnewmember",
        "0xffa3992900000000000000000000000000000000000000000000000000000000000000004344000000000000000000000000000000000000000000000000000000000000",
        { from: notMember }
      )
    );
    await gv.submitProposalWithSolution(
      proposalId,
      "Addnewmember",
      "0xffa3992900000000000000000000000000000000000000000000000000000000000000004344000000000000000000000000000000000000000000000000000000000000"
    );
    assert.equal((await gv.canCloseProposal(proposalId)).toNumber(), 0);
  });

  it("15.13 Should not categorize proposal if solution exists", async function () {
    await assertRevert(gv.categorizeProposal(proposalId, 2, toWei(1)));
  });

  it("15.14 Should not allow voting for non existent solution", async () => {
    await assertRevert(gv.submitVote(proposalId, 5));
  });

  it("15.15 Should not allow unauthorized people to vote", async () => {
    await assertRevert(gv.submitVote(proposalId, 1, { from: notMember }));
  });

  it("15.16 Should submit vote to valid solution", async function () {
    await gv.submitVote(proposalId, 1);
    await gv.proposalDetails(proposalId);
    await assertRevert(gv.submitVote(proposalId, 1));
  });

  // it('15.17 Should not claim reward for an open proposal', async function() {
  //   await assertRevert(cr.claimAllPendingReward(20));
  // });

  it("15.18 Should close proposal", async function () {
    let canClose = await gv.canCloseProposal(proposalId);
    assert.equal(canClose.toNumber(), 1);
    await gv.closeProposal(proposalId);
  });

  it("15.19 Should not close already closed proposal", async function () {
    let canClose = await gv.canCloseProposal(proposalId);
    assert.equal(canClose.toNumber(), 2);
    await assertRevert(gv.closeProposal(proposalId));
  });

  it("15.20 Should get rewards", async function () {
    let pendingRewards = await gv.getPendingReward(ab1);
  });

  it("15.22 Should claim rewards", async function () {
    await gv.claimReward(ab1, 20);
    let pendingRewards = await gv.getPendingReward(ab1);
    assert.equal(pendingRewards.toNumber(), 0, "Rewards not claimed");
    pId = await gv.getProposalLength();
    lastClaimed = await gv.lastRewardClaimed(ab1);
    pendingRewards = await gv.getPendingReward(ab1);
  });

  // it('15.23 Should not claim reward twice for same proposal', async function() {
  //   await assertRevert(cr.claimAllPendingReward(20));
  // });

  it("Should claim rewards for multiple number of proposals", async function () {
    let action = "updateUintParameters(bytes8,uint)";
    let code = "MAXFOL";
    let proposedValue = 50;
    let lastClaimed = await gv.lastRewardClaimed(ab1);
    let actionHash = encode(action, code, proposedValue);
    pId = await gv.getProposalLength();
    lastClaimed = await gv.lastRewardClaimed(ab1);
    for (let i = 0; i < 3; i++) {
      //   await gv.createProposal("Proposal1", "Proposal1", "Proposal1", 0); //Pid 1
      // await gv.categorizeProposal(proposalId, 2, toWei(1));
      // await gv.submitProposalWithSolution(
      //   proposalId,
      //   "Addnewmember",
      //   "0xffa3992900000000000000000000000000000000000000000000000000000000000000004344000000000000000000000000000000000000000000000000000000000000"
      // );

      await gvProposalWithIncentiveViaTokenHolder(12, actionHash, mr, gv, 2, 10);
    }
    // let members = await mr.members(2);
    // let iteration = 0;
    // for (iteration = 0; iteration < members[1].length; iteration++) {
    //   await cr.claimAllPendingReward(20);
    // }
    pId = await gv.getProposalLength();
    lastClaimed = await gv.lastRewardClaimed(ab1);
  });

  it("Claim rewards for proposals which are not in sequence", async function () {
    pId = await gv.getProposalLength();
    let action = "updateUintParameters(bytes8,uint)";
    let code = "MAXFOL";
    let proposedValue = 50;
    let actionHash = encode(action, code, proposedValue);
    for (let i = 0; i < 3; i++) {
      await gvProposalWithIncentiveViaTokenHolder(12, actionHash, mr, gv, 2, 10);
    }
    let p = await gv.getProposalLength();
    await assertRevert(gv.rejectAction(pId));
    await gv.createProposal("proposal", "proposal", "proposal", 0);
    await gv.categorizeProposal(p, 12, 10);
    await gv.submitProposalWithSolution(p, "proposal", actionHash);
    // let members = await mr.members(2);
    // let iteration = 0;
    // for (iteration = 0; iteration < members[1].length; iteration++) {
    //   await gv.submitVote(p, 1, {
    //     from: members[1][iteration],
    //   });
    // }
    await gv.submitVote(p, 1);
    for (let i = 0; i < 3; i++) {
      await gvProposalWithIncentiveViaTokenHolder(12, actionHash, mr, gv, 2, 10);
    }
    await gv.claimReward(ab1, 20);

    let p1 = await gv.getProposalLength();
    let lastClaimed = await gv.lastRewardClaimed(ab1);
    assert.equal(lastClaimed.toNumber(), p.toNumber() - 1);
    await gv.closeProposal(p);
    await gv.claimReward(ab1, 20);

    lastClaimed = await gv.lastRewardClaimed(ab1);
    assert.equal(lastClaimed.toNumber(), p1.toNumber() - 1);
  });

  it("Claim Rewards for maximum of 20 proposals", async function () {
    await gv.claimReward(ab1, 20);
    let actionHash = encode("updateUintParameters(bytes8,uint)", "MAXFOL", 50);
    let p1 = await gv.getProposalLength();
    let lastClaimed = await gv.lastRewardClaimed(ab1);
    for (let i = 0; i < 7; i++) {
      await gvProposalWithIncentiveViaTokenHolder(12, actionHash, mr, gv, 2, 10);
    }
    await gv.claimReward(ab1, 5);
    p1 = await gv.getProposalLength();
    let lastProposal = p1.toNumber() - 1;
    lastClaimed = await gv.lastRewardClaimed(ab1);
    //Two proposal are still pending to be claimed since 5 had been passed as max records to claim
    assert.equal(lastClaimed.toNumber(), lastProposal - 2);
  });

  it("Proposal should be closed if not categorized for more than 14 days", async function () {
    pId = await gv.getProposalLength();
    await gv.createProposal("Proposal", "Proposal", "Proposal", 0);
    await increaseTime(604810 * 2);
    await gv.closeProposal(pId);
  });

  it("Proposal should be closed if not submitted to vote for more than 14 days", async function () {
    pId = await gv.getProposalLength();
    await gv.createProposal("Proposal", "Proposal", "Proposal", 0);
    await gv.categorizeProposal(pId, 12, 10);
    await increaseTime(604810 * 2);
    await gv.closeProposal(pId);
  });
});