// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Crowdfunding is ReentrancyGuard, ERC721, Ownable {
    using SafeERC20 for IERC20;

    struct Campaign {
        address creator;
        uint256 goal;
        uint256 deadline;
        uint256 raised;
        bool withdrawn;
        address token; // address(0) for ETH, otherwise ERC-20 token
        uint256 minContribution;
        bool cancelled;
        bool whitelistEnabled;
        bool rewardEnabled;
        bool approved;
        bool isIco;
        uint256 tokenPrice; // tokens per 1 ETH, scaled by 1e18
        uint256 tokensSold;
        uint256 tokensClaimed;
    }

    uint256 public constant FEE_BPS_DENOMINATOR = 10_000;
    uint256 public constant MAX_FEE_BPS = 300;
    uint256 public constant PRICE_DENOMINATOR = 1e18;

    uint256 public campaignCount;
    uint256 public nextRewardId;
    uint256 public feeBps;
    address public feeRecipient;
    address public dao;

    string private rewardBaseURI;

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(address => uint256)) public contributions;
    mapping(uint256 => mapping(address => bool)) public whitelist;
    mapping(uint256 => mapping(address => bool)) public rewardMinted;
    mapping(uint256 => mapping(address => uint256)) public icoOwed;
    mapping(uint256 => uint256) public icoTokenPool;
    mapping(address => uint256) public reservedIcoTokens;
    mapping(uint256 => uint256) public rewardCampaign;

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 goal,
        uint256 deadline,
        address token,
        uint256 minContribution,
        bool whitelistEnabled,
        bool rewardEnabled,
        bool isIco,
        uint256 tokenPrice
    );
    event CampaignApproved(uint256 indexed campaignId, address indexed dao);
    event CampaignCancelled(uint256 indexed campaignId, address indexed creator);
    event Contribution(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event IcoContribution(uint256 indexed campaignId, address indexed contributor, uint256 ethAmount, uint256 tokenAmount);
    event Withdrawn(uint256 indexed campaignId, address indexed creator, uint256 amount, uint256 fee);
    event Refunded(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event FeeUpdated(uint256 feeBps, address feeRecipient);
    event DaoUpdated(address dao);
    event WhitelistUpdated(uint256 indexed campaignId, address indexed contributor, bool allowed);
    event RewardMinted(uint256 indexed campaignId, address indexed contributor, uint256 tokenId);
    event RewardBaseURIUpdated(string newBaseURI);
    event IcoTokensDeposited(uint256 indexed campaignId, uint256 amount);
    event IcoTokensClaimed(uint256 indexed campaignId, address indexed contributor, uint256 amount);
    event IcoTokensWithdrawn(uint256 indexed campaignId, address indexed creator, uint256 amount);

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
    error CampaignIsCancelled();
    error CampaignNotApproved();
    error BelowMinimumContribution();
    error NotWhitelisted();
    error InvalidFeeBps();
    error InvalidFeeRecipient();
    error NotDao();
    error NotIcoCampaign();
    error InvalidTokenPrice();
    error InsufficientIcoTokens();
    error NoIcoTokensAvailable();
    error CampaignActive();

    constructor() ERC721("Crowdfunding Reward", "CROWD") Ownable(msg.sender) {
        feeBps = 0;
        feeRecipient = msg.sender;
        nextRewardId = 1;
    }

    function createCampaign(
        uint256 goal,
        uint256 deadline,
        address token,
        uint256 minContribution,
        bool whitelistEnabled,
        bool rewardEnabled
    ) external returns (uint256) {
        if (goal == 0) revert ZeroAmount();
        if (deadline <= block.timestamp) revert DeadlineInPast();

        campaignCount += 1;
        campaigns[campaignCount] = Campaign({
            creator: msg.sender,
            goal: goal,
            deadline: deadline,
            raised: 0,
            withdrawn: false,
            token: token,
            minContribution: minContribution,
            cancelled: false,
            whitelistEnabled: whitelistEnabled,
            rewardEnabled: rewardEnabled,
            approved: dao == address(0),
            isIco: false,
            tokenPrice: 0,
            tokensSold: 0,
            tokensClaimed: 0
        });

        emit CampaignCreated(
            campaignCount,
            msg.sender,
            goal,
            deadline,
            token,
            minContribution,
            whitelistEnabled,
            rewardEnabled,
            false,
            0
        );
        return campaignCount;
    }

    function createIcoCampaign(
        uint256 goal,
        uint256 deadline,
        address token,
        uint256 minContribution,
        bool whitelistEnabled,
        bool rewardEnabled,
        uint256 tokenPrice
    ) external returns (uint256) {
        if (goal == 0) revert ZeroAmount();
        if (deadline <= block.timestamp) revert DeadlineInPast();
        if (token == address(0)) revert WrongCurrency();
        if (tokenPrice == 0) revert InvalidTokenPrice();

        campaignCount += 1;
        campaigns[campaignCount] = Campaign({
            creator: msg.sender,
            goal: goal,
            deadline: deadline,
            raised: 0,
            withdrawn: false,
            token: token,
            minContribution: minContribution,
            cancelled: false,
            whitelistEnabled: whitelistEnabled,
            rewardEnabled: rewardEnabled,
            approved: dao == address(0),
            isIco: true,
            tokenPrice: tokenPrice,
            tokensSold: 0,
            tokensClaimed: 0
        });

        emit CampaignCreated(
            campaignCount,
            msg.sender,
            goal,
            deadline,
            token,
            minContribution,
            whitelistEnabled,
            rewardEnabled,
            true,
            tokenPrice
        );
        return campaignCount;
    }

    function approveCampaign(uint256 campaignId) external {
        if (dao == address(0) || msg.sender != dao) revert NotDao();
        Campaign storage campaign = _getCampaign(campaignId);
        campaign.approved = true;
        emit CampaignApproved(campaignId, msg.sender);
    }

    function cancelCampaign(uint256 campaignId) external {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.creator) revert NotCreator();
        if (campaign.cancelled) revert CampaignIsCancelled();
        if (campaign.withdrawn) revert AlreadyWithdrawn();
        if (campaign.raised > 0) revert CampaignActive();

        campaign.cancelled = true;
        emit CampaignCancelled(campaignId, msg.sender);
    }

    function setFee(uint256 newFeeBps, address newRecipient) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert InvalidFeeBps();
        if (newFeeBps > 0 && newRecipient == address(0)) revert InvalidFeeRecipient();
        feeBps = newFeeBps;
        feeRecipient = newRecipient;
        emit FeeUpdated(newFeeBps, newRecipient);
    }

    function setDao(address newDao) external onlyOwner {
        dao = newDao;
        emit DaoUpdated(newDao);
    }

    function setRewardBaseURI(string calldata newBaseURI) external onlyOwner {
        rewardBaseURI = newBaseURI;
        emit RewardBaseURIUpdated(newBaseURI);
    }

    function setWhitelist(uint256 campaignId, address contributor, bool allowed) external {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.creator) revert NotCreator();
        whitelist[campaignId][contributor] = allowed;
        emit WhitelistUpdated(campaignId, contributor, allowed);
    }

    function setWhitelistBatch(uint256 campaignId, address[] calldata contributors, bool allowed) external {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.creator) revert NotCreator();
        for (uint256 i = 0; i < contributors.length; i++) {
            whitelist[campaignId][contributors[i]] = allowed;
            emit WhitelistUpdated(campaignId, contributors[i], allowed);
        }
    }

    function contributeETH(uint256 campaignId) external payable {
        Campaign storage campaign = _getCampaign(campaignId);
        if (campaign.token != address(0) || campaign.isIco) revert WrongCurrency();
        _validateContribution(campaignId, campaign, msg.value);

        campaign.raised += msg.value;
        contributions[campaignId][msg.sender] += msg.value;

        _maybeMintReward(campaignId, msg.sender, campaign.rewardEnabled);
        emit Contribution(campaignId, msg.sender, msg.value);
    }

    function contributeToken(uint256 campaignId, uint256 amount) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (campaign.token == address(0) || campaign.isIco) revert WrongCurrency();
        _validateContribution(campaignId, campaign, amount);

        campaign.raised += amount;
        contributions[campaignId][msg.sender] += amount;

        IERC20(campaign.token).safeTransferFrom(msg.sender, address(this), amount);
        _maybeMintReward(campaignId, msg.sender, campaign.rewardEnabled);
        emit Contribution(campaignId, msg.sender, amount);
    }

    function contributeICO(uint256 campaignId) external payable {
        Campaign storage campaign = _getCampaign(campaignId);
        if (!campaign.isIco) revert NotIcoCampaign();
        _validateContribution(campaignId, campaign, msg.value);

        uint256 tokenAmount = (msg.value * campaign.tokenPrice) / PRICE_DENOMINATOR;
        if (tokenAmount == 0) revert ZeroAmount();

        uint256 available = _availableIcoTokens(campaignId, campaign);
        if (available < tokenAmount) revert InsufficientIcoTokens();

        campaign.raised += msg.value;
        contributions[campaignId][msg.sender] += msg.value;
        icoOwed[campaignId][msg.sender] += tokenAmount;
        campaign.tokensSold += tokenAmount;

        _maybeMintReward(campaignId, msg.sender, campaign.rewardEnabled);
        emit IcoContribution(campaignId, msg.sender, msg.value, tokenAmount);
    }

    function depositIcoTokens(uint256 campaignId, uint256 amount) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (!campaign.isIco) revert NotIcoCampaign();
        if (msg.sender != campaign.creator) revert NotCreator();
        if (amount == 0) revert ZeroAmount();

        icoTokenPool[campaignId] += amount;
        reservedIcoTokens[campaign.token] += amount;

        IERC20(campaign.token).safeTransferFrom(msg.sender, address(this), amount);
        emit IcoTokensDeposited(campaignId, amount);
    }

    function claimIcoTokens(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (!campaign.isIco) revert NotIcoCampaign();
        if (campaign.cancelled) revert CampaignIsCancelled();
        if (campaign.raised < campaign.goal) revert GoalNotReached();

        uint256 owed = icoOwed[campaignId][msg.sender];
        if (owed == 0) revert NoContribution();

        icoOwed[campaignId][msg.sender] = 0;
        campaign.tokensClaimed += owed;
        icoTokenPool[campaignId] -= owed;
        reservedIcoTokens[campaign.token] -= owed;

        IERC20(campaign.token).safeTransfer(msg.sender, owed);
        emit IcoTokensClaimed(campaignId, msg.sender, owed);
    }

    function withdrawIcoTokens(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (!campaign.isIco) revert NotIcoCampaign();
        if (msg.sender != campaign.creator) revert NotCreator();
        if (!campaign.cancelled && block.timestamp < campaign.deadline && campaign.raised < campaign.goal) {
            revert CampaignActive();
        }

        uint256 available = _availableIcoTokens(campaignId, campaign);
        if (available == 0) revert NoIcoTokensAvailable();

        icoTokenPool[campaignId] -= available;
        reservedIcoTokens[campaign.token] -= available;

        IERC20(campaign.token).safeTransfer(msg.sender, available);
        emit IcoTokensWithdrawn(campaignId, msg.sender, available);
    }

    function withdraw(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (msg.sender != campaign.creator) revert NotCreator();
        if (campaign.cancelled) revert CampaignIsCancelled();
        if (campaign.withdrawn) revert AlreadyWithdrawn();
        if (campaign.raised < campaign.goal) revert GoalNotReached();

        campaign.withdrawn = true;
        uint256 amount = campaign.raised;
        uint256 fee = (amount * feeBps) / FEE_BPS_DENOMINATOR;
        uint256 payout = amount - fee;

        bool isEthContribution = campaign.token == address(0) || campaign.isIco;

        if (fee > 0) {
            if (feeRecipient == address(0)) revert InvalidFeeRecipient();
            if (isEthContribution) {
                (bool feeSuccess, ) = feeRecipient.call{value: fee}("");
                if (!feeSuccess) revert TransferFailed();
            } else {
                IERC20(campaign.token).safeTransfer(feeRecipient, fee);
            }
        }

        if (isEthContribution) {
            (bool success, ) = campaign.creator.call{value: payout}("");
            if (!success) revert TransferFailed();
        } else {
            uint256 availableBalance = IERC20(campaign.token).balanceOf(address(this)) - reservedIcoTokens[campaign.token];
            if (availableBalance < payout) revert TransferFailed();
            IERC20(campaign.token).safeTransfer(campaign.creator, payout);
        }

        emit Withdrawn(campaignId, campaign.creator, payout, fee);
    }

    function refund(uint256 campaignId) external nonReentrant {
        Campaign storage campaign = _getCampaign(campaignId);
        if (campaign.cancelled) revert CampaignIsCancelled();
        if (block.timestamp < campaign.deadline) revert DeadlineNotReached();
        if (campaign.raised >= campaign.goal) revert GoalReached();
        if (campaign.withdrawn) revert AlreadyWithdrawn();

        uint256 amount = contributions[campaignId][msg.sender];
        if (amount == 0) revert NoContribution();

        contributions[campaignId][msg.sender] = 0;

        if (campaign.isIco) {
            uint256 owed = icoOwed[campaignId][msg.sender];
            if (owed > 0) {
                icoOwed[campaignId][msg.sender] = 0;
                campaign.tokensSold -= owed;
            }
        }

        if (campaign.token == address(0) || campaign.isIco) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(campaign.token).safeTransfer(msg.sender, amount);
        }

        emit Refunded(campaignId, msg.sender, amount);
    }

    function _validateContribution(uint256 campaignId, Campaign storage campaign, uint256 amount) internal view {
        if (campaign.cancelled) revert CampaignIsCancelled();
        if (campaign.withdrawn || block.timestamp >= campaign.deadline) revert CampaignEnded();
        if (!campaign.approved) revert CampaignNotApproved();
        if (amount == 0) revert ZeroAmount();
        if (amount < campaign.minContribution) revert BelowMinimumContribution();
        if (campaign.whitelistEnabled && !whitelist[campaignId][msg.sender]) revert NotWhitelisted();
    }

    function _availableIcoTokens(uint256 campaignId, Campaign storage campaign) internal view returns (uint256) {
        uint256 owed = campaign.tokensSold - campaign.tokensClaimed;
        uint256 pool = icoTokenPool[campaignId];
        if (pool <= owed) {
            return 0;
        }
        return pool - owed;
    }

    function _maybeMintReward(uint256 campaignId, address contributor, bool enabled) internal {
        if (!enabled || rewardMinted[campaignId][contributor]) return;
        uint256 tokenId = nextRewardId++;
        rewardMinted[campaignId][contributor] = true;
        rewardCampaign[tokenId] = campaignId;
        _safeMint(contributor, tokenId);
        emit RewardMinted(campaignId, contributor, tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return rewardBaseURI;
    }

    function _getCampaign(uint256 campaignId) internal view returns (Campaign storage) {
        if (campaignId == 0 || campaignId > campaignCount) revert InvalidCampaign();
        return campaigns[campaignId];
    }
}
