// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title YieldFarm
 * @notice Challenge: Implement a yield farming contract with the following requirements:
 *
 * 1. Users can stake LP tokens and earn reward tokens
 * 2. Rewards are distributed based on time and amount staked
 * 3. Implement reward boosting mechanism for long-term stakers
 * 4. Add emergency withdrawal functionality
 * 5. Implement reward rate adjustment mechanism
 */

contract YieldFarm is ReentrancyGuard, Ownable {
    // LP token that users can stake
    IERC20 public lpToken;

    // Token given as reward
    IERC20 public rewardToken;

    // Reward rate per second
    uint256 public rewardRate;

    // Last update time
    uint256 public lastUpdateTime;

    // Reward per token stored
    uint256 public rewardPerTokenStored;

    // Total staked amount
    uint256 public totalStaked;

    // User struct to track staking info
    struct UserInfo {
        uint256 amount; // Amount of LP tokens staked
        uint256 startTime; // Time when user started staking
        uint256 rewardDebt; // Reward debt
        uint256 pendingRewards; // Unclaimed rewards
    }

    // Mapping of user address to their info
    mapping(address => UserInfo) public userInfo;

    // Boost multiplier thresholds (in seconds)
    uint256 public constant BOOST_THRESHOLD_1 = 7 days;
    uint256 public constant BOOST_THRESHOLD_2 = 30 days;
    uint256 public constant BOOST_THRESHOLD_3 = 90 days;

    // Events
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event EmergencyWithdrawn(address indexed user, uint256 amount);

    // TODO: Implement the following functions

    /**
     * @notice Initialize the contract with the LP token and reward token addresses
     * @param _lpToken Address of the LP token
     * @param _rewardToken Address of the reward token
     * @param _rewardRate Initial reward rate per second
     */
    constructor(
        address _lpToken,
        address _rewardToken,
        uint256 _rewardRate
    ) Ownable(msg.sender) {
        lpToken = IERC20(_lpToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    function updateReward(address _user) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        UserInfo storage user = userInfo[_user];
        if (user.amount > 0) {
            user.pendingRewards = earned(_user);
            user.rewardDebt = (user.amount * rewardPerTokenStored) / 1e18;
        }
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        uint256 duration = block.timestamp - lastUpdateTime;
        uint256 newReward = duration * rewardRate;
        return rewardPerTokenStored + (newReward * 1e18) / totalStaked;
    }

    function earned(address _user) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];

        uint256 _rewardPerToken = rewardPerToken();

        if (_rewardPerToken <= user.rewardDebt) {
            return user.pendingRewards;
        }

        uint256 newReward = ((_rewardPerToken - user.rewardDebt) *
            user.amount) / 1e18;
        return
            user.pendingRewards +
            ((newReward * calculateBoostMultiplier(_user)) / 100);
    }

    /**
     * @notice Stake LP tokens into the farm
     * @param _amount Amount of LP tokens to stake
     */
    function stake(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Cannot stake 0");
        require(
            lpToken.balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );

        updateReward(msg.sender);

        totalStaked += _amount;

        UserInfo storage user = userInfo[msg.sender];

        if (user.amount == 0) {
            user.startTime = block.timestamp;
        }

        user.amount += _amount;

        require(
            lpToken.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );

        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Withdraw staked LP tokens
     * @param _amount Amount of LP tokens to withdraw
     */
    function withdraw(uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be greater than 0");

        UserInfo storage user = userInfo[msg.sender];

        require(_amount <= user.amount, "Insufficient balance");

        updateReward(msg.sender);

        totalStaked -= _amount;
        user.amount -= _amount;

        require(lpToken.transfer(msg.sender, _amount), "Transfer failed");

        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external nonReentrant {
        updateReward(msg.sender);
        uint256 rewards = earned(msg.sender);

        if (rewards > 0) {
            UserInfo storage user = userInfo[msg.sender];
            user.pendingRewards = 0;
            user.rewardDebt = (user.amount * rewardPerTokenStored) / 1e18;

            require(
                rewardToken.transfer(msg.sender, rewards),
                "Reward transfer failed"
            );

            emit RewardsClaimed(msg.sender, rewards);
        }

        lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Emergency withdraw without caring about rewards
     */
    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "No staked amount");
        require(lpToken.transfer(msg.sender, user.amount), "Transfer failed");

        totalStaked -= user.amount;

        emit EmergencyWithdrawn(msg.sender, user.amount);

        user.amount = 0;
        user.startTime = 0;
        user.rewardDebt = 0;
        user.pendingRewards = 0;
    }

    /**
     * @notice Calculate boost multiplier based on staking duration
     * @param _user Address of the user
     * @return Boost multiplier (100 = 1x, 150 = 1.5x, etc.)
     */
    function calculateBoostMultiplier(
        address _user
    ) public view returns (uint256) {
        UserInfo memory user = userInfo[_user];
        if (user.amount == 0) {
            return 100;
        }

        uint256 duration = block.timestamp - user.startTime;
        if (duration >= BOOST_THRESHOLD_3) {
            return 200;
        } else if (duration >= BOOST_THRESHOLD_2) {
            return 150;
        } else if (duration >= BOOST_THRESHOLD_1) {
            return 125;
        } else {
            return 100;
        }
    }

    /**
     * @notice Update reward rate
     * @param _newRate New reward rate per second
     */
    function updateRewardRate(uint256 _newRate) external onlyOwner {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
        rewardRate = _newRate;
    }

    /**
     * @notice View function to see pending rewards for a user
     * @param _user Address of the user
     * @return Pending reward amount
     */
    function pendingRewards(address _user) external view returns (uint256) {
        return earned(_user);
    }
}
