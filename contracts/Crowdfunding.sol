// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Crowdfunding is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Campaign {
        address creator;
        uint256 goal;
        uint256 deadline;
        uint256 raised;
        bool withdrawn;
        address token; // address(0) for ETH
    }

    uint256 public campaignCount;
    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(address => uint256)) public contributions;

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 goal,
        uint256 deadline,
        address token
    );
    event Contribution(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event Withdrawn(uint256 indexed campaignId, address indexed creator, uint256 amount);
    event Refunded(uint256 indexed campaignId, address indexed contributor, uint256 amount);

    error InvalidCampaign();
    error DeadlineInPast();
    error ZeroAmount();
    error WrongCurrency();
    error CampaignEnded();
    error NotCreator();
    error GoalNotReached();
    error AlreadyWithdrawn();
    error DeadlineNotReached();
    error GoalReached();
    error NoContribution();
    error TransferFailed();

    function createCampaign(uint256 goal, uint256 deadline, address token) external returns (uint256) {
        if (goal == 0) revert ZeroAmount();
        if (deadline <= block.timestamp) revert DeadlineInPast();

        campaignCount += 1;
        campaigns[campaignCount] = Campaign({
            creator: msg.sender,
            goal: goal,
            deadline: deadline,
            raised: 0,
            withdrawn: false,
            token: token
        });

        emit CampaignCreated(campaignCount, msg.sender, goal, deadline, token);
        return campaignCount;
    }

    function contributeETH(uint256 campaignId) external payable {
        Campaign storage campaign = _getCampaign(campaignId);
        if (campaign.token != address(0)) revert WrongCurrency();
        if (campaign.withdrawn || block.timestamp >= campaign.deadline) revert CampaignEnded();
        if (msg.value == 0) revert ZeroAmount();

        campaign.raised += msg.value;
        contributions[campaignId][msg.sender] += msg.value;

        emit Contribution(campaignId, msg.sender, msg.value);
    }

    function contributeToken(uint256 campaignId, uint256 amount) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (campaign.token == address(0)) revert WrongCurrency();
        if (campaign.withdrawn || block.timestamp >= campaign.deadline) revert CampaignEnded();
        if (amount == 0) revert ZeroAmount();

        campaign.raised += amount;
        contributions[campaignId][msg.sender] += amount;

        IERC20(campaign.token).safeTransferFrom(msg.sender, address(this), amount);
        emit Contribution(campaignId, msg.sender, amount);
    }

    function withdraw(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.creator) revert NotCreator();
        if (campaign.withdrawn) revert AlreadyWithdrawn();
        if (campaign.raised < campaign.goal) revert GoalNotReached();

        campaign.withdrawn = true;
        uint256 amount = campaign.raised;

        if (campaign.token == address(0)) {
            (bool success, ) = campaign.creator.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(campaign.token).safeTransfer(campaign.creator, amount);
        }

        emit Withdrawn(campaignId, campaign.creator, amount);
    }

    function refund(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (block.timestamp < campaign.deadline) revert DeadlineNotReached();
        if (campaign.raised >= campaign.goal) revert GoalReached();
        if (campaign.withdrawn) revert AlreadyWithdrawn();

        uint256 amount = contributions[campaignId][msg.sender];
        if (amount == 0) revert NoContribution();

        contributions[campaignId][msg.sender] = 0;

        if (campaign.token == address(0)) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(campaign.token).safeTransfer(msg.sender, amount);
        }

        emit Refunded(campaignId, msg.sender, amount);
    }

    function _getCampaign(uint256 campaignId) internal view returns (Campaign storage) {
        if (campaignId == 0 || campaignId > campaignCount) revert InvalidCampaign();
        return campaigns[campaignId];
    }
}
