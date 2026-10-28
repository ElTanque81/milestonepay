// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MilestonePay
/// @notice Milestone-based freelancer escrow on Portaldot. Clients lock native POT,
///         freelancers get paid milestone by milestone. Optional arbiter for disputes.
/// @dev    Uses only native POT (msg.value) — no token contracts needed.
contract MilestonePay {
    // ------------------------------------------------------------------
    // Types
    // ------------------------------------------------------------------

    enum MilestoneStatus {
        Pending,   // funded, waiting for work
        Submitted, // freelancer submitted proof, review period running
        Disputed,  // client disputed, waiting for arbiter
        Released,  // paid to freelancer
        Refunded   // returned to client
    }

    struct Milestone {
        uint256 amount;
        MilestoneStatus status;
        uint64 submittedAt;
        string proof; // link or hash of the delivered work
    }

    struct Project {
        address client;
        address freelancer;
        address arbiter;      // address(0) = no arbiter, disputes disabled
        uint64 reviewPeriod;  // seconds the client has to review a submission
        bool accepted;        // freelancer accepted the job
        bool closed;          // cancelled or all milestones settled
        uint256 totalAmount;
        string title;
    }

    // ------------------------------------------------------------------
    // Storage
    // ------------------------------------------------------------------

    uint256 public constant MAX_MILESTONES = 20;
    uint64 public constant MIN_REVIEW_PERIOD = 60;        // 1 minute (demo friendly)
    uint64 public constant MAX_REVIEW_PERIOD = 30 days;

    uint256 public projectCount;
    mapping(uint256 => Project) private _projects;
    mapping(uint256 => Milestone[]) private _milestones;
    mapping(address => uint256[]) private _projectsByUser;

    uint256 private _locked = 1;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    event ProjectCreated(
        uint256 indexed projectId,
        address indexed client,
        address indexed freelancer,
        address arbiter,
        uint256 totalAmount,
        uint256 milestoneCount,
        string title
    );
    event ProjectAccepted(uint256 indexed projectId);
    event ProjectCancelled(uint256 indexed projectId, uint256 refunded);
    event MilestoneSubmitted(uint256 indexed projectId, uint256 indexed index, string proof);
    event MilestoneDisputed(uint256 indexed projectId, uint256 indexed index);
    event MilestoneReleased(uint256 indexed projectId, uint256 indexed index, uint256 amount, address to);
    event MilestoneRefunded(uint256 indexed projectId, uint256 indexed index, uint256 amount, address to);

    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------

    error InvalidParams();
    error WrongValue();
    error NotAuthorized();
    error WrongStatus();
    error ProjectClosed();
    error ReviewPeriodRunning();
    error NoArbiter();
    error TransferFailed();
    error Reentrancy();

    // ------------------------------------------------------------------
    // Modifiers
    // ------------------------------------------------------------------

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier exists(uint256 projectId) {
        if (projectId == 0 || projectId > projectCount) revert InvalidParams();
        _;
    }

    // ------------------------------------------------------------------
    // Client actions
    // ------------------------------------------------------------------

    /// @notice Create and fully fund a project. msg.value must equal the sum of all milestones.
    function createProject(
        address freelancer,
        address arbiter,
        uint256[] calldata amounts,
        uint64 reviewPeriod,
        string calldata title
    ) external payable returns (uint256 projectId) {
        if (
            freelancer == address(0) ||
            freelancer == msg.sender ||
            arbiter == msg.sender ||
            arbiter == freelancer ||
            amounts.length == 0 ||
            amounts.length > MAX_MILESTONES ||
            reviewPeriod < MIN_REVIEW_PERIOD ||
            reviewPeriod > MAX_REVIEW_PERIOD ||
            bytes(title).length == 0 ||
            bytes(title).length > 100
        ) revert InvalidParams();

        uint256 total;
        for (uint256 i; i < amounts.length; ++i) {
            if (amounts[i] == 0) revert InvalidParams();
            total += amounts[i];
        }
        if (msg.value != total) revert WrongValue();

        projectId = ++projectCount;
        _projects[projectId] = Project({
            client: msg.sender,
            freelancer: freelancer,
            arbiter: arbiter,
            reviewPeriod: reviewPeriod,
            accepted: false,
            closed: false,
            totalAmount: total,
            title: title
        });

        Milestone[] storage ms = _milestones[projectId];
        for (uint256 i; i < amounts.length; ++i) {
            ms.push(Milestone({amount: amounts[i], status: MilestoneStatus.Pending, submittedAt: 0, proof: ""}));
        }

        _projectsByUser[msg.sender].push(projectId);
        _projectsByUser[freelancer].push(projectId);
        if (arbiter != address(0)) _projectsByUser[arbiter].push(projectId);

        emit ProjectCreated(projectId, msg.sender, freelancer, arbiter, total, amounts.length, title);
    }

    /// @notice Client cancels before the freelancer accepted. Full refund.
    function cancelProject(uint256 projectId) external nonReentrant exists(projectId) {
        Project storage p = _projects[projectId];
        if (msg.sender != p.client) revert NotAuthorized();
        if (p.closed) revert ProjectClosed();
        if (p.accepted) revert WrongStatus();

        p.closed = true;
        uint256 refund = _refundPending(projectId, p.client);
        emit ProjectCancelled(projectId, refund);
    }

    /// @notice Client approves a submitted milestone and pays the freelancer.
    function approveMilestone(uint256 projectId, uint256 index) external nonReentrant exists(projectId) {
        Project storage p = _projects[projectId];
        if (msg.sender != p.client) revert NotAuthorized();
        Milestone storage m = _milestone(projectId, index);
        if (m.status != MilestoneStatus.Submitted) revert WrongStatus();

        _release(projectId, index, p.freelancer);
    }

    /// @notice Client disputes a submitted milestone during the review period.
    function disputeMilestone(uint256 projectId, uint256 index) external exists(projectId) {
        Project storage p = _projects[projectId];
        if (msg.sender != p.client) revert NotAuthorized();
        if (p.arbiter == address(0)) revert NoArbiter();
        Milestone storage m = _milestone(projectId, index);
        if (m.status != MilestoneStatus.Submitted) revert WrongStatus();
        if (block.timestamp >= uint256(m.submittedAt) + p.reviewPeriod) revert WrongStatus();

        m.status = MilestoneStatus.Disputed;
        emit MilestoneDisputed(projectId, index);
    }

    // ------------------------------------------------------------------
    // Freelancer actions
    // ------------------------------------------------------------------

    /// @notice Freelancer accepts the job. After this the client can no longer cancel.
    function acceptProject(uint256 projectId) external exists(projectId) {
        Project storage p = _projects[projectId];
        if (msg.sender != p.freelancer) revert NotAuthorized();
        if (p.closed) revert ProjectClosed();
        if (p.accepted) revert WrongStatus();

        p.accepted = true;
        emit ProjectAccepted(projectId);
    }

    /// @notice Freelancer submits proof of work for a milestone.
    function submitMilestone(uint256 projectId, uint256 index, string calldata proof) external exists(projectId) {
        Project storage p = _projects[projectId];
        if (msg.sender != p.freelancer) revert NotAuthorized();
        if (!p.accepted) revert WrongStatus();
        if (p.closed) revert ProjectClosed();
        if (bytes(proof).length == 0 || bytes(proof).length > 300) revert InvalidParams();
        Milestone storage m = _milestone(projectId, index);
        if (m.status != MilestoneStatus.Pending) revert WrongStatus();

        m.status = MilestoneStatus.Submitted;
        m.submittedAt = uint64(block.timestamp);
        m.proof = proof;
        emit MilestoneSubmitted(projectId, index, proof);
    }

    /// @notice Freelancer claims payment if the client did not react within the review period.
    function claimAfterTimeout(uint256 projectId, uint256 index) external nonReentrant exists(projectId) {
        Project storage p = _projects[projectId];
        if (msg.sender != p.freelancer) revert NotAuthorized();
        Milestone storage m = _milestone(projectId, index);
        if (m.status != MilestoneStatus.Submitted) revert WrongStatus();
        if (block.timestamp < uint256(m.submittedAt) + p.reviewPeriod) revert ReviewPeriodRunning();

        _release(projectId, index, p.freelancer);
    }

    /// @notice Freelancer walks away: all not-yet-submitted milestones go back to the client.
    function withdrawFromProject(uint256 projectId) external nonReentrant exists(projectId) {
        Project storage p = _projects[projectId];
        if (msg.sender != p.freelancer) revert NotAuthorized();
        if (p.closed) revert ProjectClosed();

        uint256 refund = _refundPending(projectId, p.client);
        _maybeClose(projectId);
        emit ProjectCancelled(projectId, refund);
    }

    // ------------------------------------------------------------------
    // Arbiter actions
    // ------------------------------------------------------------------

    /// @notice Arbiter settles a disputed milestone.
    function resolveDispute(uint256 projectId, uint256 index, bool payFreelancer)
        external
        nonReentrant
        exists(projectId)
    {
        Project storage p = _projects[projectId];
        if (msg.sender != p.arbiter) revert NotAuthorized();
        Milestone storage m = _milestone(projectId, index);
        if (m.status != MilestoneStatus.Disputed) revert WrongStatus();

        if (payFreelancer) {
            _release(projectId, index, p.freelancer);
        } else {
            m.status = MilestoneStatus.Refunded;
            uint256 amount = m.amount;
            _maybeClose(projectId);
            emit MilestoneRefunded(projectId, index, amount, p.client);
            _send(p.client, amount);
        }
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function getProject(uint256 projectId) external view exists(projectId) returns (Project memory) {
        return _projects[projectId];
    }

    function getMilestones(uint256 projectId) external view exists(projectId) returns (Milestone[] memory) {
        return _milestones[projectId];
    }

    function getProjectsOf(address user) external view returns (uint256[] memory) {
        return _projectsByUser[user];
    }

    /// @notice POT still locked in a project.
    function lockedAmount(uint256 projectId) public view exists(projectId) returns (uint256 locked) {
        Milestone[] storage ms = _milestones[projectId];
        for (uint256 i; i < ms.length; ++i) {
            MilestoneStatus s = ms[i].status;
            if (s == MilestoneStatus.Pending || s == MilestoneStatus.Submitted || s == MilestoneStatus.Disputed) {
                locked += ms[i].amount;
            }
        }
    }

    // ------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------

    function _milestone(uint256 projectId, uint256 index) internal view returns (Milestone storage) {
        Milestone[] storage ms = _milestones[projectId];
        if (index >= ms.length) revert InvalidParams();
        return ms[index];
    }

    function _release(uint256 projectId, uint256 index, address to) internal {
        Milestone storage m = _milestones[projectId][index];
        m.status = MilestoneStatus.Released;
        uint256 amount = m.amount;
        _maybeClose(projectId);
        emit MilestoneReleased(projectId, index, amount, to);
        _send(to, amount);
    }

    function _refundPending(uint256 projectId, address to) internal returns (uint256 refund) {
        Milestone[] storage ms = _milestones[projectId];
        for (uint256 i; i < ms.length; ++i) {
            if (ms[i].status == MilestoneStatus.Pending) {
                ms[i].status = MilestoneStatus.Refunded;
                refund += ms[i].amount;
                emit MilestoneRefunded(projectId, i, ms[i].amount, to);
            }
        }
        if (refund > 0) _send(to, refund);
    }

    function _maybeClose(uint256 projectId) internal {
        Milestone[] storage ms = _milestones[projectId];
        for (uint256 i; i < ms.length; ++i) {
            MilestoneStatus s = ms[i].status;
            if (s != MilestoneStatus.Released && s != MilestoneStatus.Refunded) return;
        }
        _projects[projectId].closed = true;
    }

    function _send(address to, uint256 amount) internal {
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
