// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SwapContract is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    uint8 public feePercent;
    address public treasury;

    enum SwapStatus { Pending, Approved, Rejected, Cancelled }

    struct SwapRequest {
        address requester;
        address recipient;
        address offerToken;
        uint256 offerAmount;
        address receiveToken;
        uint256 receiveAmount;
        SwapStatus status;
    }

    SwapRequest[] public swapRequests;

    event SwapRequested(uint256 indexed requestId, address indexed requester, address indexed recipient, address offerToken, uint256 offerAmount, address receiveToken, uint256 receiveAmount);
    event SwapStatusChanged(uint256 indexed requestId, SwapStatus status);

    constructor() {
        _disableInitializers();
    }

    // ================================ EXTERNAL FUNCTIONS ================================

    function initialize(address _owner, address _treasury) external initializer {
        __ReentrancyGuard_init();
        __Ownable_init(_owner);
        treasury = _treasury;
        feePercent = 5;
    }

    function createSwapRequest(address _recipient, address _offerToken, uint256 _offerAmount, address _receiveToken, uint256 _receiveAmount) external {
        require(_recipient != address(0), "Invalid recipient address");
        require(_offerToken != address(0) && _receiveToken != address(0), "Invalid token address");
        require(_offerAmount > 0 && _receiveAmount > 0, "Amounts must be greater than zero");
        IERC20(_offerToken).safeTransferFrom(msg.sender, address(this), _offerAmount);
        SwapRequest memory newRequest = SwapRequest({
            requester: msg.sender,
            recipient: _recipient,
            offerToken: _offerToken,
            offerAmount: _offerAmount,
            receiveToken: _receiveToken,
            receiveAmount: _receiveAmount,
            status: SwapStatus.Pending
        });
        swapRequests.push(newRequest);
        emit SwapRequested(swapRequests.length - 1, msg.sender, _recipient, _offerToken, _offerAmount, _receiveToken, _receiveAmount);
    }

    function approveSwapRequest(uint256 _requestId) external nonReentrant requestExists(_requestId) isPending(_requestId) onlyRecipient(_requestId) {
        SwapRequest storage request = swapRequests[_requestId];

        // Transfer receive token to contract
        IERC20(request.receiveToken).safeTransferFrom(msg.sender, address(this), request.receiveAmount);

        // Calculate fee
        uint256 requestFee = (request.offerAmount * feePercent) / 100;
        uint256 offerAmountAfterFee = request.offerAmount - requestFee;
        uint256 receiveFee = (request.receiveAmount * feePercent) / 100;
        uint256 receiveAmountAfterFee = request.receiveAmount - receiveFee;

        // Transfer tokens
        _transferWithFee(request.offerToken, request.recipient, offerAmountAfterFee, requestFee);
        _transferWithFee(request.receiveToken, request.requester, receiveAmountAfterFee, receiveFee);
        
        // Update status
        request.status = SwapStatus.Approved;

        // Emit event
        emit SwapStatusChanged(_requestId, SwapStatus.Approved);
    }


    function rejectSwapRequest(uint256 _requestId) external nonReentrant requestExists(_requestId) isPending(_requestId) onlyRecipient(_requestId) {
        SwapRequest storage request = swapRequests[_requestId];

        // Transfer request token back to requester
        IERC20(request.offerToken).safeTransfer(request.requester, request.offerAmount);

        // Update status
        request.status = SwapStatus.Rejected;

        // Emit event
        emit SwapStatusChanged(_requestId, SwapStatus.Rejected);
    }

    function cancelSwapRequest(uint256 _requestId) external nonReentrant requestExists(_requestId) isPending(_requestId) {
        require(swapRequests[_requestId].requester == msg.sender, "Only requester can cancel");

        SwapRequest storage request = swapRequests[_requestId];

        // Transfer request token back to requester
        IERC20(request.offerToken).safeTransfer(request.requester, request.offerAmount);

        // Update status
        request.status = SwapStatus.Cancelled;

        // Emit event
        emit SwapStatusChanged(_requestId, SwapStatus.Cancelled);
    }

    // ================================ PUBLIC FUNCTIONS ================================

    function setTreasury(address _newTreasury) public onlyOwner {
        treasury = _newTreasury;
    }

    function setFeePercent(uint8 _newFeePercent) public onlyOwner {
        require(_newFeePercent <= 100, "Invalid fee percentage");
        feePercent = _newFeePercent;
    }

    // ================================ MODIFIERS ================================
    // check if request exists
    modifier requestExists(uint256 _requestId) {
        require(_requestId < swapRequests.length, "Request does not exist");
        _;
    }

    // check if request is pending
    modifier isPending(uint256 _requestId) {
        require(swapRequests[_requestId].status == SwapStatus.Pending, "Swap request is not pending");
        _;
    }

    // check if caller is the recipient
    modifier onlyRecipient(uint256 _requestId) {
        require(swapRequests[_requestId].recipient == msg.sender, "Not authorized");
        _;
    }

    // ================================ VIEW FUNCTIONS ================================
    function getSwapRequest(uint256 _requestId) external view returns (SwapRequest memory) {
        return swapRequests[_requestId];
    }

    // ================================ FALLBACK FUNCTIONS ================================
    // fallback, receive function to check if the user sends ETH into the contract
    receive() external payable {
        revert("This contract does not accept ETH");
    }

    // fallback, fallback function to receive ETH
    fallback() external payable {
        revert("This contract does not accept ETH");
    }

    // ================================ INTERNAL FUNCTIONS ================================
    function _transferWithFee(address _token, address _recipient, uint256 _amountAfterFee, uint256 _fee) internal {
        IERC20(_token).safeTransfer(treasury, _fee);
        IERC20(_token).safeTransfer(_recipient, _amountAfterFee);
    }
}