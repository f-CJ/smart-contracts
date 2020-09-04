// /* Copyright (C) 2017 GovBlocks.io

//   This program is free software: you can redistribute it and/or modify
//     it under the terms of the GNU General Public License as published by
//     the Free Software Foundation, either version 3 of the License, or
//     (at your option) any later version.

//   This program is distributed in the hope that it will be useful,
//     but WITHOUT ANY WARRANTY; without even the implied warranty of
//     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//     GNU General Public License for more details.

//   You should have received a copy of the GNU General Public License
//     along with this program.  If not, see http://www.gnu.org/licenses/ */

pragma solidity 0.5.7;

import "./external/govblocks-protocol/interfaces/IGovernance.sol";
import "./external/govblocks-protocol/interfaces/IProposalCategory.sol";
import "./external/govblocks-protocol/interfaces/IMemberRoles.sol";
import "./external/proxy/OwnedUpgradeabilityProxy.sol";
import "./external/openzeppelin-solidity/math/SafeMath.sol";
import "./interfaces/Iupgradable.sol";
import "./interfaces/IMarketRegistry.sol";
import "./interfaces/ITokenController.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IMaster.sol";

contract Governance is IGovernance, Iupgradable {
    using SafeMath for uint256;

    enum ProposalStatus {
        Draft,
        AwaitingSolution,
        VotingStarted,
        Accepted,
        Rejected,
        Denied
    }

    struct ProposalData {
        uint256 propStatus;
        uint256 finalVerdict;
        uint256 category;
        uint256 commonIncentive;
        uint256 dateUpd;
        uint256 totalVoteValue;
        address owner;
    }

    struct ProposalVote {
        address voter;
        uint256 proposalId;
        uint256 solutionChosen;
        uint256 voteValue;
        uint256 dateAdd;
    }
    struct VoteTally {
        mapping(uint256 => uint256) voteValue;
        // mapping(uint=>uint) abVoteValue;
        uint256 voters;
    }

    struct DelegateVote {
        address follower;
        address leader;
        uint256 lastUpd;
    }

    ProposalVote[] internal allVotes;
    DelegateVote[] public allDelegation;

    mapping(uint256 => ProposalData) internal allProposalData;
    mapping(uint256 => bytes[]) internal allProposalSolutions;
    mapping(address => uint256[]) internal allVotesByMember;
    mapping(uint256 => mapping(address => bool)) public rewardClaimed;
    mapping(address => mapping(uint256 => uint256)) public memberProposalVote;
    mapping(address => uint256) public followerDelegation;
    mapping(address => uint256) internal followerCount;
    mapping(address => uint256[]) internal leaderDelegation;
    mapping(address => uint256) public followerIndex;
    mapping(uint256 => VoteTally) public proposalVoteTally;
    mapping(address => bool) public isOpenForDelegation;
    mapping(address => uint256) public lastRewardClaimed;

    bool internal constructorCheck;
    uint256 public tokenHoldingTime;
    uint256 internal roleIdAllowedToCatgorize;
    // uint internal maxVoteWeigthPer;
    uint256 internal maxFollowers;
    uint256 internal totalProposals;
    uint256 internal maxDraftTime;
    uint256 internal minTokenLockedForDR;
    uint256 internal lockTimeForDR;
    uint256 internal votePercRejectAction;
    uint256 internal actionRejectAuthRole;

    IMaster public ms;
    IMemberRoles internal memberRole;
    IMarketRegistry internal marketRegistry;
    IProposalCategory internal proposalCategory;
    //Plot Token Instance
    IToken internal tokenInstance;
    ITokenController internal tokenController;

    mapping(uint256 => uint256) public proposalActionStatus;
    mapping(uint256 => uint256) internal proposalExecutionTime;
    mapping(uint256 => mapping(address => bool)) public isActionRejected;
    mapping(uint256 => uint256) internal actionRejectedCount;

    uint256 internal actionWaitingTime;

    enum ActionStatus {Pending, Accepted, Rejected, Executed, NoAction}

    /**
     * @dev Called whenever an action execution is failed.
     */
    event ActionFailed(uint256 proposalId);

    /**
     * @dev Called whenever an AB member rejects the action execution.
     */
    event ActionRejected(uint256 indexed proposalId, address rejectedBy);

    /**
     * @dev Checks if msg.sender is proposal owner
     */
    modifier onlyProposalOwner(uint256 _proposalId) {
        require(
            msg.sender == allProposalData[_proposalId].owner,
            "Not allowed"
        );
        _;
    }

    /**
     * @dev Checks if proposal is opened for voting
     */
    modifier voteNotStarted(uint256 _proposalId) {
        require(
            allProposalData[_proposalId].propStatus <
                uint256(ProposalStatus.VotingStarted)
        );
        _;
    }

    /**
     * @dev Checks if msg.sender is allowed to create proposal under given category
     */
    modifier isAllowed(uint256 _categoryId) {
        require(allowedToCreateProposal(_categoryId), "Not allowed");
        _;
    }

    /**
     * @dev Checks if msg.sender is allowed categorize proposal under given category
     */
    modifier isAllowedToCategorize() {
        require(
            memberRole.checkRole(msg.sender, roleIdAllowedToCatgorize),
            "Not allowed"
        );
        _;
    }

    /**
     * @dev Checks if msg.sender had any pending rewards to be claimed
     */
    modifier checkPendingRewards {
        require(getPendingReward(msg.sender) == 0, "Claim reward");
        _;
    }

    /**
     * @dev Event emitted whenever a proposal is categorized
     */
    event ProposalCategorized(
        uint256 indexed proposalId,
        address indexed categorizedBy,
        uint256 categoryId
    );

    /**
     * @dev Creates a new proposal
     * @param _proposalDescHash Proposal description hash through IPFS having Short and long description of proposal
     * @param _categoryId This id tells under which the proposal is categorized i.e. Proposal's Objective
     */
    function createProposal(
        string calldata _proposalTitle,
        string calldata _proposalSD,
        string calldata _proposalDescHash,
        uint256 _categoryId
    ) external isAllowed(_categoryId) {
        require(
            memberRole.checkRole(
                msg.sender,
                uint256(IMemberRoles.Role.TokenHolder)
            ),
            "Not Member"
        );

        _createProposal(
            _proposalTitle,
            _proposalSD,
            _proposalDescHash,
            _categoryId
        );
    }

    /**
     * @dev Edits the details of an existing proposal
     * To implement the governance interface
     */
    function updateProposal(
        uint256 _proposalId,
        string calldata _proposalTitle,
        string calldata _proposalSD,
        string calldata _proposalDescHash
    ) external {
    }

    /**
     * @dev Categorizes proposal to proceed further. Categories shows the proposal objective.
     */
    function categorizeProposal(
        uint256 _proposalId,
        uint256 _categoryId,
        uint256 _incentive
    ) external voteNotStarted(_proposalId) isAllowedToCategorize {
        _categorizeProposal(_proposalId, _categoryId, _incentive);
    }

    /**
     * @dev Initiates add solution
     * To implement the governance interface
     */
    function addSolution(
        uint256,
        string calldata,
        bytes calldata
    ) external {}

    /**
     * @dev Opens proposal for voting
     * To implement the governance interface
     */
    function openProposalForVoting(uint256) external {}

    /**
     * @dev Submit proposal with solution
     * @param _proposalId Proposal id
     * @param _solutionHash Solution hash contains  parameters, values and description needed according to proposal
     */
    function submitProposalWithSolution(
        uint256 _proposalId,
        string calldata _solutionHash,
        bytes calldata _action
    ) external onlyProposalOwner(_proposalId) {
        require(
            allProposalData[_proposalId].propStatus ==
                uint256(ProposalStatus.AwaitingSolution)
        );

        _proposalSubmission(_proposalId, _solutionHash, _action);
    }

    /**
     * @dev Creates a new proposal with solution
     * @param _proposalDescHash Proposal description hash through IPFS having Short and long description of proposal
     * @param _categoryId This id tells under which the proposal is categorized i.e. Proposal's Objective
     * @param _solutionHash Solution hash contains  parameters, values and description needed according to proposal
     */
    function createProposalwithSolution(
        string calldata _proposalTitle,
        string calldata _proposalSD,
        string calldata _proposalDescHash,
        uint256 _categoryId,
        string calldata _solutionHash,
        bytes calldata _action
    ) external isAllowed(_categoryId) {
        uint256 proposalId = totalProposals;

        _createProposal(
            _proposalTitle,
            _proposalSD,
            _proposalDescHash,
            _categoryId
        );

        require(_categoryId > 0);

        _proposalSubmission(proposalId, _solutionHash, _action);
    }

    /**
     * @dev Submit a vote on the proposal.
     * @param _proposalId to vote upon.
     * @param _solutionChosen is the chosen vote.
     */
    function submitVote(uint256 _proposalId, uint256 _solutionChosen) external {
        require(
            allProposalData[_proposalId].propStatus ==
                uint256(Governance.ProposalStatus.VotingStarted),
            "Not allowed"
        );

        require(_solutionChosen < allProposalSolutions[_proposalId].length);

        _submitVote(_proposalId, _solutionChosen);
    }

    /**
     * @dev Closes the proposal.
     * @param _proposalId of proposal to be closed.
     */
    function closeProposal(uint256 _proposalId) external {
        uint256 category = allProposalData[_proposalId].category;

        if (
            allProposalData[_proposalId].dateUpd.add(maxDraftTime) <= now &&
            allProposalData[_proposalId].propStatus <
            uint256(ProposalStatus.VotingStarted)
        ) {
            _updateProposalStatus(_proposalId, uint256(ProposalStatus.Denied));
        } else {
            require(canCloseProposal(_proposalId) == 1);
            _closeVote(_proposalId, category);
        }
    }

    /**
     * @dev Claims reward for member.
     * @param _memberAddress to claim reward of.
     * @param _maxRecords maximum number of records to claim reward for.
     _proposals list of proposals of which reward will be claimed.
     * @return amount of pending reward.
     */
    function claimReward(address _memberAddress, uint256 _maxRecords)
        external
        returns (uint256 pendingDAppReward)
    {
        uint256 voteId;
        address leader;
        uint256 lastUpd;

        uint256 delegationId = followerDelegation[_memberAddress];
        DelegateVote memory delegationData = allDelegation[delegationId];
        if (delegationId > 0 && delegationData.leader != address(0)) {
            leader = delegationData.leader;
            lastUpd = delegationData.lastUpd;
        } else leader = _memberAddress;

        uint256 proposalId;
        uint256 totalVotes = allVotesByMember[leader].length;
        uint256 lastClaimed = totalVotes;
        uint256 j;
        uint256 i;
        for (
            i = lastRewardClaimed[_memberAddress];
            i < totalVotes && j < _maxRecords;
            i++
        ) {
            voteId = allVotesByMember[leader][i];
            proposalId = allVotes[voteId].proposalId;
            if(memberProposalVote[_memberAddress][proposalId] == voteId) {
                if (
                    proposalVoteTally[proposalId].voters > 0 &&
                    (allVotes[voteId].dateAdd > (lastUpd.add(tokenHoldingTime)) ||
                        leader == _memberAddress)
                ) {
                    if (
                        allProposalData[proposalId].propStatus >
                        uint256(ProposalStatus.VotingStarted)
                    ) {
                        if (!rewardClaimed[voteId][_memberAddress]) {
                            pendingDAppReward = pendingDAppReward.add(
                                allProposalData[proposalId].commonIncentive.div(
                                    proposalVoteTally[proposalId].voters
                                )
                            );
                            rewardClaimed[voteId][_memberAddress] = true;
                            j++;
                        }
                    } else {
                        if (lastClaimed == totalVotes) {
                            lastClaimed = i;
                        }
                    }
                }
            }
        }

        if (lastClaimed == totalVotes) {
            lastRewardClaimed[_memberAddress] = i;
        } else {
            lastRewardClaimed[_memberAddress] = lastClaimed;
        }

        if (j > 0) {
            tokenInstance.transfer(_memberAddress, pendingDAppReward);
            emit RewardClaimed(_memberAddress, pendingDAppReward);
        }
    }

    /**
     * @dev Sets delegation acceptance status of individual user
     * @param _status delegation acceptance status
     */
    function setDelegationStatus(bool _status) external checkPendingRewards {
        isOpenForDelegation[msg.sender] = _status;
    }

    /**
     * @dev Delegates vote to an address.
     * @param _add is the address to delegate vote to.
     */
    function delegateVote(address _add) external checkPendingRewards {
        require(delegatedTo(_add) == address(0));

        if (followerDelegation[msg.sender] > 0) {
            require(
                (allDelegation[followerDelegation[msg.sender]].lastUpd).add(
                    tokenHoldingTime
                ) < now
            );
        }

        require(!alreadyDelegated(msg.sender));
        require(
            !memberRole.checkRole(
                msg.sender,
                uint256(IMemberRoles.Role.AdvisoryBoard)
            )
        );
        require(
            !memberRole.checkRole(
                msg.sender,
                uint256(IMemberRoles.Role.DisputeResolution)
            )
        );
        require(
            memberRole.checkRole(
                msg.sender,
                uint256(IMemberRoles.Role.TokenHolder)
            ),
            "Not a token holder"
        );

        require(followerCount[_add] < maxFollowers);

        if (allVotesByMember[msg.sender].length > 0) {
            require(
                (
                    allVotes[allVotesByMember[msg.sender][allVotesByMember[msg
                        .sender]
                        .length.sub(1)]]
                        .dateAdd
                )
                    .add(tokenHoldingTime) < now
            );
        }

        require(isOpenForDelegation[_add]);

        allDelegation.push(DelegateVote(msg.sender, _add, now));
        followerDelegation[msg.sender] = allDelegation.length.sub(1);
        followerIndex[msg.sender] = leaderDelegation[_add].length;
        leaderDelegation[_add].push(allDelegation.length.sub(1));
        followerCount[_add]++;
        lastRewardClaimed[msg.sender] = allVotesByMember[_add].length;
    }

    /**
     * @dev Undelegates the sender
     */
    function unDelegate() external checkPendingRewards {
        _unDelegate(msg.sender);
    }

    /**
     * @dev Triggers action of accepted proposal after waiting time is finished
     */
    function triggerAction(uint256 _proposalId) external {
        require(
            proposalActionStatus[_proposalId] ==
                uint256(ActionStatus.Accepted) &&
                proposalExecutionTime[_proposalId] <= now,
            "Cannot trigger"
        );
        _triggerAction(_proposalId, allProposalData[_proposalId].category);
    }

    /**
     * @dev Provides option to Advisory board member to reject proposal action execution within actionWaitingTime, if found suspicious
     */
    function rejectAction(uint256 _proposalId) external {
        require(
            memberRole.checkRole(msg.sender, actionRejectAuthRole) &&
                proposalExecutionTime[_proposalId] > now
        );

        require(
            proposalActionStatus[_proposalId] == uint256(ActionStatus.Accepted)
        );

        require(!isActionRejected[_proposalId][msg.sender]);

        isActionRejected[_proposalId][msg.sender] = true;
        actionRejectedCount[_proposalId]++;
        emit ActionRejected(_proposalId, msg.sender);
        if (
            actionRejectedCount[_proposalId].mul(100).div(
                memberRole.numberOfMembers(actionRejectAuthRole)
            ) >= votePercRejectAction
        ) {
            proposalActionStatus[_proposalId] = uint256(ActionStatus.Rejected);
        }
    }

    /**
     * @dev Gets Uint Parameters of a code
     * @param code whose details we want
     * @return string value of the code
     * @return associated amount (time or perc or value) to the code
     */
    function getUintParameters(bytes8 code)
        external
        view
        returns (bytes8 codeVal, uint256 val)
    {
        codeVal = code;

        if (code == "GOVHOLD") {
            val = tokenHoldingTime / (1 days);
        } else if (code == "MAXFOL") {
            val = maxFollowers;
        } else if (code == "MAXDRFT") {
            val = maxDraftTime / (1 days);
        } else if (code == "ACWT") {
            val = actionWaitingTime / (1 hours);
        } else if (code == "MINLOCDR") {
            val = minTokenLockedForDR;
        } else if (code == "TLOCDR") {
            val = lockTimeForDR / (1 days);
        } else if (code == "REJAUTH") {
            val = actionRejectAuthRole;
        } else if (code == "REJCOUNT") {
            val = votePercRejectAction;
        }
    }

    /**
     * @dev Gets all details of a propsal
     * @param _proposalId whose details we want
     * @return proposalId
     * @return category
     * @return status
     * @return finalVerdict
     * @return totalReward
     */
    function proposal(uint256 _proposalId)
        external
        view
        returns (
            uint256 proposalId,
            uint256 category,
            uint256 status,
            uint256 finalVerdict,
            uint256 totalRewar
        )
    {
        return (
            _proposalId,
            allProposalData[_proposalId].category,
            allProposalData[_proposalId].propStatus,
            allProposalData[_proposalId].finalVerdict,
            allProposalData[_proposalId].commonIncentive
        );
    }

    /**
     * @dev Gets some details of a propsal
     * @param _proposalId whose details we want
     * @return proposalId
     * @return number of all proposal solutions
     * @return amount of votes
     */
    function proposalDetails(uint256 _proposalId)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            _proposalId,
            allProposalSolutions[_proposalId].length,
            proposalVoteTally[_proposalId].voters
        );
    }

    /**
     * @dev Gets solution action on a proposal
     * @param _proposalId whose details we want
     * @param _solution whose details we want
     * @return action of a solution on a proposal
     */
    function getSolutionAction(uint256 _proposalId, uint256 _solution)
        external
        view
        returns (uint256, bytes memory)
    {
        return (_solution, allProposalSolutions[_proposalId][_solution]);
    }

    /**
     * @dev Gets length of propsal
     * @return length of propsal
     */
    function getProposalLength() external view returns (uint256) {
        return totalProposals;
    }

    /**
     * @dev Get followers of an address
     * @return get followers of an address
     */
    function getFollowers(address _add)
        external
        view
        returns (uint256[] memory)
    {
        return leaderDelegation[_add];
    }

    /**
     * @dev Gets pending rewards of a member
     * @param _memberAddress in concern
     * @return amount of pending reward
     */
    function getPendingReward(address _memberAddress)
        public
        view
        returns (uint256 pendingDAppReward)
    {
        uint256 delegationId = followerDelegation[_memberAddress];
        address leader;
        uint256 lastUpd;
        DelegateVote memory delegationData = allDelegation[delegationId];
        if (delegationId > 0 && delegationData.leader != address(0)) {
            leader = delegationData.leader;
            lastUpd = delegationData.lastUpd;
        } else leader = _memberAddress;

        uint256 proposalId;
        uint256 voteId;
        for (
            uint256 i = lastRewardClaimed[_memberAddress];
            i < allVotesByMember[leader].length;
            i++
        ) {
            voteId = allVotesByMember[leader][i];
            proposalId = allVotes[voteId].proposalId;
            if(memberProposalVote[_memberAddress][proposalId] == voteId) {
                if (
                    allVotes[voteId].dateAdd >
                    (lastUpd.add(tokenHoldingTime)) ||
                    leader == _memberAddress
                ) {
                    if (
                        !rewardClaimed[voteId][_memberAddress]
                    ) {
                        if (
                            proposalVoteTally[proposalId].voters > 0 &&
                            allProposalData[proposalId].propStatus >
                            uint256(ProposalStatus.VotingStarted)
                        ) {
                            pendingDAppReward = pendingDAppReward.add(
                                allProposalData[proposalId].commonIncentive.div(
                                    proposalVoteTally[proposalId].voters
                                )
                            );
                        }
                    }
                }
            }
        }
    }

    /**
     * @dev Updates Uint Parameters of a code
     * @param code whose details we want to update
     * @param val value to set
     */
    function updateUintParameters(bytes8 code, uint256 val) public {
        require(ms.isAuthorizedToGovern(msg.sender));
        if (code == "GOVHOLD") {
            tokenHoldingTime = val * 1 days;
        } else if (code == "MAXFOL") {
            maxFollowers = val;
        } else if (code == "MAXDRFT") {
            maxDraftTime = val * 1 days;
        } else if (code == "ACWT") {
            actionWaitingTime = val * 1 hours;
        } else if (code == "MINLOCDR") {
            minTokenLockedForDR = val;
        } else if (code == "TLOCDR") {
            lockTimeForDR = val * 1 days;
        } else if (code == "REJAUTH") {
            actionRejectAuthRole = val;
        } else if (code == "REJCOUNT") {
            votePercRejectAction = val;
        } else {
            revert("Invalid code");
        }
    }

    /**
     * @dev Updates all dependency addresses to latest ones from Master
     */
    function setMasterAddress() public {
        OwnedUpgradeabilityProxy proxy =  OwnedUpgradeabilityProxy(address(uint160(address(this))));
        require(msg.sender == proxy.proxyOwner(),"Sender is not proxy owner.");

        require(!constructorCheck);
        _initiateGovernance();
        ms = IMaster(msg.sender);
        tokenInstance = IToken(ms.dAppToken());
        memberRole = IMemberRoles(ms.getLatestAddress("MR"));
        proposalCategory = IProposalCategory(ms.getLatestAddress("PC"));
        tokenController = ITokenController(ms.getLatestAddress("TC"));
        marketRegistry = IMarketRegistry(address(uint160(ms.getLatestAddress("PL"))));
    }

    /**
     * @dev Checks if msg.sender is allowed to create a proposal under given category
     */
    function allowedToCreateProposal(uint256 category)
        public
        view
        returns (bool check)
    {
        if (category == 0) return true;
        uint256[] memory mrAllowed;
        (, , , , mrAllowed, , ) = proposalCategory.category(category);
        for (uint256 i = 0; i < mrAllowed.length; i++) {
            if (
                mrAllowed[i] == 0 ||
                memberRole.checkRole(msg.sender, mrAllowed[i])
            ) return true;
        }
    }

    function delegatedTo(address _follower) public returns(address) {
        if(followerDelegation[_follower] > 0) {
            return allDelegation[followerDelegation[_follower]].leader;
        }
    }

    /**
     * @dev Checks if an address is already delegated
     * @param _add in concern
     * @return bool value if the address is delegated or not
     */
    function alreadyDelegated(address _add)
        public
        view
        returns (bool delegated)
    {
        for (uint256 i = 0; i < leaderDelegation[_add].length; i++) {
            if (allDelegation[leaderDelegation[_add][i]].leader == _add) {
                return true;
            }
        }
    }

    /**
     * @dev Pauses a proposal
     * To implement govblocks interface
     */
    function pauseProposal(uint256) public {}

    /**
     * @dev Resumes a proposal
     * To implement govblocks interface
     */
    function resumeProposal(uint256) public {}

    /**
     * @dev Checks If the proposal voting time is up and it's ready to close
     *      i.e. Closevalue is 1 if proposal is ready to be closed, 2 if already closed, 0 otherwise!
     * @param _proposalId Proposal id to which closing value is being checked
     */
    function canCloseProposal(uint256 _proposalId)
        public
        view
        returns (uint256)
    {
        uint256 dateUpdate;
        uint256 pStatus;
        uint256 _closingTime;
        uint256 _roleId;
        uint256 majority;
        pStatus = allProposalData[_proposalId].propStatus;
        dateUpdate = allProposalData[_proposalId].dateUpd;
        (, _roleId, majority, , , _closingTime, ) = proposalCategory.category(
            allProposalData[_proposalId].category
        );
        if (pStatus == uint256(ProposalStatus.VotingStarted)) {
            uint256 numberOfMembers = memberRole.numberOfMembers(_roleId);
            if (
                _roleId == uint256(IMemberRoles.Role.AdvisoryBoard) ||
                _roleId == uint256(IMemberRoles.Role.DisputeResolution)
            ) {
                if (
                    proposalVoteTally[_proposalId].voteValue[1].mul(100).div(
                        numberOfMembers
                    ) >=
                    majority ||
                    proposalVoteTally[_proposalId].voteValue[1].add(
                        proposalVoteTally[_proposalId].voteValue[0]
                    ) ==
                    numberOfMembers ||
                    dateUpdate.add(_closingTime) <= now
                ) {
                    return 1;
                }
            } else {
                if(_roleId == uint256(IMemberRoles.Role.TokenHolder)) {
                    if(dateUpdate.add(_closingTime) <= now)
                        return 1;
                } else if (
                    numberOfMembers <= proposalVoteTally[_proposalId].voters ||
                    dateUpdate.add(_closingTime) <= now
                ) return 1;
            }
        } else if (pStatus > uint256(ProposalStatus.VotingStarted)) {
            return 2;
        } else {
            return 0;
        }
    }

    /**
     * @dev Gets Id of member role allowed to categorize the proposal
     * @return roleId allowed to categorize the proposal
     */
    function allowedToCatgorize() public view returns (uint256 roleId) {
        return roleIdAllowedToCatgorize;
    }

    /**
     * @dev Gets vote tally data
     * @param _proposalId in concern
     * @param _solution of a proposal id
     * @return member vote value
     * @return advisory board vote value
     * @return amount of votes
     */
    function voteTallyData(uint256 _proposalId, uint256 _solution)
        public
        view
        returns (uint256, uint256)
    {
        return (
            proposalVoteTally[_proposalId].voteValue[_solution],
            proposalVoteTally[_proposalId].voters
        );
    }

    /**
     * @dev Internal call to create proposal
     * @param _proposalTitle of proposal
     * @param _proposalSD is short description of proposal
     * @param _proposalDescHash IPFS hash value of propsal
     * @param _categoryId of proposal
     */
    function _createProposal(
        string memory _proposalTitle,
        string memory _proposalSD,
        string memory _proposalDescHash,
        uint256 _categoryId
    ) internal {
        (, uint256 roleAuthorizedToVote, , , , , ) = proposalCategory.category(
            _categoryId
        );
        require(
            _categoryId == 0 ||
                roleAuthorizedToVote ==
                uint256(IMemberRoles.Role.AdvisoryBoard) ||
                roleAuthorizedToVote ==
                uint256(IMemberRoles.Role.DisputeResolution)
        );
        uint256 _proposalId = totalProposals;
        allProposalData[_proposalId].owner = msg.sender;
        allProposalData[_proposalId].dateUpd = now;
        allProposalSolutions[_proposalId].push("");
        totalProposals++;

        emit Proposal(
            msg.sender,
            _proposalId,
            now,
            _proposalTitle,
            _proposalSD,
            _proposalDescHash
        );

        if (_categoryId > 0) {
            (, , , uint defaultIncentive, ) = proposalCategory
            .categoryActionDetails(_categoryId);
            _categorizeProposal(_proposalId, _categoryId, defaultIncentive);
        }
    }

    /**
     * @dev Internal call to categorize a proposal
     * @param _proposalId of proposal
     * @param _categoryId of proposal
     * @param _incentive is commonIncentive
     */
    function _categorizeProposal(
        uint256 _proposalId,
        uint256 _categoryId,
        uint256 _incentive
    ) internal {
        require(
            _categoryId > 0 && _categoryId < proposalCategory.totalCategories(),
            "Invalid category"
        );
        allProposalData[_proposalId].category = _categoryId;
        allProposalData[_proposalId].commonIncentive = _incentive;
        allProposalData[_proposalId].propStatus = uint256(
            ProposalStatus.AwaitingSolution
        );

        emit ProposalCategorized(_proposalId, msg.sender, _categoryId);
    }

    /**
     * @dev Internal call to add solution to a proposal
     * @param _proposalId in concern
     * @param _action on that solution
     * @param _solutionHash string value
     */
    function _addSolution(
        uint256 _proposalId,
        bytes memory _action,
        string memory _solutionHash
    ) internal {
        allProposalSolutions[_proposalId].push(_action);
        emit Solution(
            _proposalId,
            msg.sender,
            allProposalSolutions[_proposalId].length.sub(1),
            _solutionHash,
            now
        );
    }

    /**
     * @dev Internal call to add solution and open proposal for voting
     */
    function _proposalSubmission(
        uint256 _proposalId,
        string memory _solutionHash,
        bytes memory _action
    ) internal {
        uint256 _categoryId = allProposalData[_proposalId].category;
        if (proposalCategory.categoryActionHashes(_categoryId).length == 0) {
            require(keccak256(_action) == keccak256(""));
            proposalActionStatus[_proposalId] = uint256(ActionStatus.NoAction);
        }

        _addSolution(_proposalId, _action, _solutionHash);

        _updateProposalStatus(
            _proposalId,
            uint256(ProposalStatus.VotingStarted)
        );
        (, , , , , uint256 closingTime, ) = proposalCategory.category(
            _categoryId
        );
        emit CloseProposalOnTime(_proposalId, closingTime.add(now));
    }

    /**
     * @dev Internal call to submit vote
     * @param _proposalId of proposal in concern
     * @param _solution for that proposal
     */
    function _submitVote(uint256 _proposalId, uint256 _solution) internal {
        uint256 delegationId = followerDelegation[msg.sender];
        uint256 mrSequence;
        uint256 majority;
        uint256 closingTime;
        (, mrSequence, majority, , , closingTime, ) = proposalCategory.category(
            allProposalData[_proposalId].category
        );

        require(
            allProposalData[_proposalId].dateUpd.add(closingTime) > now,
            "Closed"
        );

        require(
            memberProposalVote[msg.sender][_proposalId] == 0,
            "Not allowed"
        );
        require(
            (delegationId == 0) ||
                (delegationId > 0 &&
                    allDelegation[delegationId].leader == address(0) &&
                    _checkLastUpd(allDelegation[delegationId].lastUpd))
        );

        require(memberRole.checkRole(msg.sender, mrSequence), "Not Authorized");
        if (mrSequence == uint256(IMemberRoles.Role.DisputeResolution)) {
            require(
                minTokenLockedForDR <=
                    tokenController.tokensLockedAtTime(
                        msg.sender,
                        "DR",
                        lockTimeForDR.add(now)
                    ), "Not locked"
            );
        }
        uint256 voteId = allVotes.length;

        allVotesByMember[msg.sender].push(voteId);
        memberProposalVote[msg.sender][_proposalId] = voteId;
        tokenController.lockForGovernanceVote(msg.sender, tokenHoldingTime);

        emit Vote(msg.sender, _proposalId, voteId, now, _solution);
        uint256 numberOfMembers = memberRole.numberOfMembers(mrSequence);
        _setVoteTally(_proposalId, _solution, mrSequence, voteId);

        if (
            numberOfMembers == proposalVoteTally[_proposalId].voters &&
            mrSequence != uint256(IMemberRoles.Role.TokenHolder)
        ) {
            emit VoteCast(_proposalId);
        }
    }

    function _setVoteTally(
        uint256 _proposalId,
        uint256 _solution,
        uint256 mrSequence,
        uint256 voteId
    ) internal {
        uint256 voters = 1;
        uint256 voteWeight;
        uint256 tokenBalance = tokenController.totalBalanceOf(msg.sender);
        allVotes.push(
            ProposalVote(msg.sender, _proposalId, _solution, tokenBalance, now)
        );
        if (
            mrSequence != uint256(IMemberRoles.Role.AdvisoryBoard) &&
            mrSequence != uint256(IMemberRoles.Role.DisputeResolution)
        ) {
            voteWeight = tokenBalance;
            DelegateVote memory delegationData;
            for (uint256 i = 0; i < leaderDelegation[msg.sender].length; i++) {
                delegationData = allDelegation[leaderDelegation[msg.sender][i]];
                if (
                    delegationData.leader == msg.sender &&
                    _checkLastUpd(delegationData.lastUpd)
                ) {
                    if (
                        memberRole.checkRole(
                            delegationData.follower,
                            mrSequence
                        )
                    ) {
                        tokenBalance = tokenController.totalBalanceOf(
                            delegationData.follower
                        );
                        tokenController.lockForGovernanceVote(
                            delegationData.follower,
                            tokenHoldingTime
                        );
                        memberProposalVote[delegationData.follower][_proposalId] = voteId;
                        voters++;
                        voteWeight = voteWeight.add(tokenBalance);
                    }
                }
            }
        } else {
            voteWeight = 1;
        }
        allProposalData[_proposalId]
            .totalVoteValue = allProposalData[_proposalId].totalVoteValue.add(
            voteWeight
        );
        proposalVoteTally[_proposalId]
            .voteValue[_solution] = proposalVoteTally[_proposalId]
            .voteValue[_solution]
            .add(voteWeight);
        proposalVoteTally[_proposalId].voters =
            proposalVoteTally[_proposalId].voters.add(voters);
    }

    /**
     * @dev Check the time since last update has exceeded token holding time or not
     * @param _lastUpd is last update time
     * @return the bool which tells if the time since last update has exceeded token holding time or not
     */
    function _checkLastUpd(uint256 _lastUpd) internal view returns (bool) {
        return ((now).sub(_lastUpd)) > tokenHoldingTime;
    }

    /**
     * @dev Checks if the vote count against any solution passes the threshold value or not.
     */
    function _checkForThreshold(uint256 _proposalId, uint256 _category)
        internal
        view
        returns (bool check)
    {
        uint256 categoryQuorumPerc;
        uint256 roleAuthorized;
        (, roleAuthorized, , categoryQuorumPerc, , , ) = proposalCategory
            .category(_category);
        if (roleAuthorized == uint256(IMemberRoles.Role.TokenHolder)) {
            check =
                (allProposalData[_proposalId].totalVoteValue).mul(100).div(
                    tokenController.totalSupply()
                ) >=
                categoryQuorumPerc;
        } else {
            check =
                (proposalVoteTally[_proposalId].voters).mul(100).div(
                    memberRole.numberOfMembers(roleAuthorized)
                ) >=
                categoryQuorumPerc;
        }
    }

    /**
     * @dev Called when vote majority is reached
     * @param _proposalId of proposal in concern
     * @param _status of proposal in concern
     * @param category of proposal in concern
     * @param max vote value of proposal in concern
     */
    function _callIfMajReached(
        uint256 _proposalId,
        uint256 _status,
        uint256 category,
        uint256 max,
        uint256 role
    ) internal {
        allProposalData[_proposalId].finalVerdict = max;
        _updateProposalStatus(_proposalId, _status);
        emit ProposalAccepted(_proposalId);
        if (
            proposalActionStatus[_proposalId] != uint256(ActionStatus.NoAction)
        ) {
            if (role == actionRejectAuthRole) {
                _triggerAction(_proposalId, category);
            } else {
                proposalActionStatus[_proposalId] = uint256(
                    ActionStatus.Accepted
                );
                proposalExecutionTime[_proposalId] = actionWaitingTime.add(now);
            }
        }
    }

    /**
     * @dev Internal function to trigger action of accepted proposal
     */
    function _triggerAction(uint256 _proposalId, uint256 _categoryId) internal {
        proposalActionStatus[_proposalId] = uint256(ActionStatus.Executed);
        bytes2 contractName;
        address actionAddress;
        bytes memory _functionHash;
        (, actionAddress, contractName, , _functionHash) = proposalCategory
            .categoryActionDetails(_categoryId);
        if (contractName == "MS") {
            actionAddress = address(ms);
        } else if (contractName != "EX") {
            actionAddress = ms.getLatestAddress(contractName);
        }
        (bool actionStatus, ) = actionAddress.call(
            abi.encodePacked(
                _functionHash,
                allProposalSolutions[_proposalId][1]
            )
        );
        if (actionStatus) {
            emit ActionSuccess(_proposalId);
        } else {
            proposalActionStatus[_proposalId] = uint256(ActionStatus.Accepted);
            emit ActionFailed(_proposalId);
        }
    }

    /**
     * @dev Internal call to update proposal status
     * @param _proposalId of proposal in concern
     * @param _status of proposal to set
     */
    function _updateProposalStatus(uint256 _proposalId, uint256 _status)
        internal
    {
        if (
            _status == uint256(ProposalStatus.Rejected) ||
            _status == uint256(ProposalStatus.Denied)
        ) {
            proposalActionStatus[_proposalId] = uint256(ActionStatus.NoAction);
        }
        allProposalData[_proposalId].dateUpd = now;
        allProposalData[_proposalId].propStatus = _status;
    }

    /**
     * @dev Internal call to undelegate a follower
     * @param _follower is address of follower to undelegate
     */
    function _unDelegate(address _follower) internal {
        uint256 followerId = followerDelegation[_follower];
        address leader = allDelegation[followerId].leader;
        if (followerId > 0) {
            //Remove followerId from leaderDelegation array
                uint256 idOfLastFollower = leaderDelegation[leader][leaderDelegation[leader].length.sub(1)];
                leaderDelegation[leader][followerIndex[_follower]] = idOfLastFollower;
                followerIndex[allDelegation[idOfLastFollower].follower] = followerIndex[_follower];
                leaderDelegation[leader].length--;
                delete followerIndex[_follower];

            followerCount[allDelegation[followerId]
                .leader] = followerCount[allDelegation[followerId].leader].sub(
                1
            );
            allDelegation[followerId].leader = address(0);
            allDelegation[followerId].lastUpd = now;

            lastRewardClaimed[_follower] = allVotesByMember[_follower].length;
        }
    }

    /**
     * @dev Internal call to close member voting
     * @param _proposalId of proposal in concern
     * @param category of proposal in concern
     */
    function _closeVote(uint256 _proposalId, uint256 category) internal {
        uint256 majorityVote;
        uint256 mrSequence;
        (, mrSequence, majorityVote, , , , ) = proposalCategory.category(
            category
        );
        if (_checkForThreshold(_proposalId, category)) {
            if (
                (
                    (
                        proposalVoteTally[_proposalId].voteValue[1]
                            .mul(100)
                    )
                        .div(allProposalData[_proposalId].totalVoteValue)
                ) >= majorityVote
            ) {
                _callIfMajReached(
                    _proposalId,
                    uint256(ProposalStatus.Accepted),
                    category,
                    1,
                    mrSequence
                );
            } else {
                _updateProposalStatus(
                    _proposalId,
                    uint256(ProposalStatus.Rejected)
                );
            }
        } else {
            _updateProposalStatus(_proposalId, uint256(ProposalStatus.Denied));
        }
        if(allProposalData[_proposalId].propStatus > uint256(ProposalStatus.Accepted)) {
            bytes memory _functionHash = proposalCategory.categoryActionHashes(category);
            if(keccak256(_functionHash) == keccak256(abi.encodeWithSignature("resolveDispute(address,uint256)"))) {
                marketRegistry.burnDisputedProposalTokens(_proposalId);
            }
        }

        if (proposalVoteTally[_proposalId].voters > 0 && allProposalData[_proposalId].commonIncentive > 0) {
            tokenInstance.transferFrom(
                address(marketRegistry),
                address(this),
                allProposalData[_proposalId].commonIncentive
            );
        }
    }

    /**
     * @dev to initiate the governance process
     */
    function _initiateGovernance() internal {
        allVotes.push(ProposalVote(address(0), 0, 0, 0, 0));
        totalProposals = 1;
        allDelegation.push(DelegateVote(address(0), address(0), now));
        tokenHoldingTime = 1 * 7 days;
        maxFollowers = 40;
        constructorCheck = true;
        roleIdAllowedToCatgorize = uint256(IMemberRoles.Role.AdvisoryBoard);
        minTokenLockedForDR = 1000 ether;
        lockTimeForDR = 15 days;
        actionWaitingTime = 1 hours;
        actionRejectAuthRole = uint256(IMemberRoles.Role.AdvisoryBoard);
        votePercRejectAction = 60;
    }

}
