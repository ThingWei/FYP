// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract RentalAgreement {
    enum State { Created, Active, Completed, Cancelled, Disputed, Resolved }
    address public immutable backend;
    address public immutable renter;
    address public immutable owner;
    uint256 public immutable rentalAmount;
    uint256 public immutable depositAmount;
    State public state;
    bool public renterSigned;
    bool public ownerSigned;
    uint256 public penalty;
    string public resolutionReference;

    event Signed(address indexed party);
    event StateChanged(State state);
    event DepositSettled(uint256 renterAmount, uint256 ownerAmount);

    modifier onlyBackend() { require(msg.sender == backend, 'Backend only'); _; }
    modifier onlyParty() { require(msg.sender == renter || msg.sender == owner, 'Party only'); _; }

    constructor(address renter_, address owner_, uint256 rentalAmount_, uint256 depositAmount_) payable {
        require(renter_ != address(0) && owner_ != address(0), 'Invalid party');
        require(msg.value == rentalAmount_ + depositAmount_, 'Incorrect escrow');
        backend = msg.sender; renter = renter_; owner = owner_;
        rentalAmount = rentalAmount_; depositAmount = depositAmount_; state = State.Created;
    }

    function sign() external onlyParty {
        require(state == State.Created, 'Not signable');
        if (msg.sender == renter) renterSigned = true; else ownerSigned = true;
        emit Signed(msg.sender);
        if (renterSigned && ownerSigned) { state = State.Active; emit StateChanged(state); }
    }

    function complete(uint256 penalty_) external onlyBackend {
        require(state == State.Active, 'Not active'); require(penalty_ <= depositAmount, 'Penalty exceeds deposit');
        penalty = penalty_; state = State.Completed;
        payable(owner).transfer(rentalAmount + penalty_); payable(renter).transfer(depositAmount - penalty_);
        emit DepositSettled(depositAmount - penalty_, rentalAmount + penalty_); emit StateChanged(state);
    }

    function cancel(uint256 ownerShare) external onlyBackend {
        require(state == State.Created || state == State.Active, 'Not cancellable'); require(ownerShare <= address(this).balance, 'Invalid share');
        state = State.Cancelled; uint256 refund = address(this).balance - ownerShare;
        if (ownerShare > 0) payable(owner).transfer(ownerShare); payable(renter).transfer(refund); emit StateChanged(state);
    }

    function openDispute() external onlyParty { require(state == State.Active, 'Not active'); state = State.Disputed; emit StateChanged(state); }

    function resolve(uint256 renterShare, string calldata reference) external onlyBackend {
        require(state == State.Disputed, 'Not disputed'); require(renterShare <= address(this).balance, 'Invalid share');
        state = State.Resolved; resolutionReference = reference; uint256 ownerShare = address(this).balance - renterShare;
        if (ownerShare > 0) payable(owner).transfer(ownerShare); if (renterShare > 0) payable(renter).transfer(renterShare); emit StateChanged(state);
    }
}

