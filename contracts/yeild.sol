// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

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
    error ZeroAddress();
    error ZeroValue();
    error TransferFailed();
    error InsufficientBalance(uint256 currentBalance, uint256 expectedBalance);

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
        if (_rewardToken == address(0)) {
            revert ZeroAddress();
        }
        if (_lpToken == address(0)) {
            revert ZeroAddress();
        }
        if (_rewardRate == 0) {
            revert ZeroValue();
        }

        lpToken = IERC20(_lpToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    function updateReward(address _user) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (_user != address(0)) {
            UserInfo storage user = userInfo[_user];
            user.pendingRewards = earned(_user);
            user.rewardDebt = (user.amount * rewardPerTokenStored) / 1e18;
        }
        // else owner is updating reward
    }

    function rewardPerToken() public view returns (uint256) {
        // Requirements:
        // 1. Calculate rewards since last update
        // 2. Apply boost multiplier
        // 3. Return total pending rewards
         if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        uint256 timeDelta = block.timestamp - lastUpdateTime;
        uint256 rewardAccrued = (timeDelta * rewardRate);
        return rewardPerTokenStored + ((rewardAccrued * 1e18) / totalStaked);
    }

    function earned(address _user) public view returns (uint256) {
        // Requirements:
        // 1. Calculate rewards since last update
        // 2. Apply boost multiplier
        // 3. Return total pending rewards
        UserInfo memory user = userInfo[_user];
        uint256 currentRewardPerToken = rewardPerToken();

        if (currentRewardPerToken <= user.rewardDebt) {
            return user.pendingRewards;
        }

        uint256 newReward = ((user.amount *
            (currentRewardPerToken - user.rewardDebt)) / 1e18);
        uint256 boostMultiplier = calculateBoostMultiplier(_user);
        uint256 boostedReward = (newReward * boostMultiplier) / 100;

        return user.pendingRewards + boostedReward;
    }

    /**
     * @notice Stake LP tokens into the farm
     * @param _amount Amount of LP tokens to stake
     */
    function stake(uint256 _amount) external nonReentrant {
        // Requirements:
        // 1. Update rewards
        // 2. Transfer LP tokens from user
        // 3. Update user info and total staked amount
        // 4. Emit Staked event

        if (_amount == 0) {
            revert ZeroValue();
        }
        updateReward(msg.sender);

        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) {
            user.startTime = block.timestamp;
        }

        totalStaked += _amount;
        user.amount += _amount;

        if (lpToken.transferFrom(msg.sender, address(this), _amount) == false) {
            revert TransferFailed();
        }
        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Withdraw staked LP tokens
     * @param _amount Amount of LP tokens to withdraw
     */
    function withdraw(uint256 _amount) external nonReentrant {
        // Requirements:
        // 1. Update rewards
        // 2. Transfer LP tokens to user
        // 3. Update user info and total staked amount
        // 4. Emit Withdrawn event
        if (_amount == 0) {
            revert ZeroValue();
        }
        UserInfo storage user = userInfo[msg.sender];
        if (user.amount < _amount) {
            revert InsufficientBalance(user.amount, _amount);
        }

        updateReward(msg.sender);

        totalStaked -= _amount;
        user.amount -= _amount;

        if (lpToken.transfer(msg.sender, _amount) == false) {
            revert TransferFailed();
        }
        emit Withdrawn(msg.sender, _amount);
    }

    /**
     * @notice Claim pending rewards
     */
    function claimRewards() external nonReentrant {
        // Requirements:
        // 1. Calculate pending rewards with boost multiplier
        // 2. Transfer rewards to user
        // 3. Update user reward debt
        // 4. Emit RewardsClaimed event
        updateReward(msg.sender);
        UserInfo storage user = userInfo[msg.sender];

        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            user.pendingRewards = 0;
            if (rewardToken.transfer(msg.sender, reward) == false) {
                revert TransferFailed();
            }
            emit RewardsClaimed(msg.sender, reward);
        } else {
            revert ZeroValue();
        }
    }

    /**
     * @notice Emergency withdraw without caring about rewards
     */
    function emergencyWithdraw() external nonReentrant {
        // Requirements:
        // 1. Transfer all LP tokens back to user
        // 2. Reset user info
        // 3. Emit EmergencyWithdrawn event
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        if (amount == 0) {
            revert ZeroValue();
        }

        totalStaked -= amount;
        user.amount = 0;
        user.startTime = 0;
        user.rewardDebt = 0;
        user.pendingRewards = 0;

        if (lpToken.transfer(msg.sender, amount) == false) {
            revert TransferFailed();
        }
        emit EmergencyWithdrawn(msg.sender, amount);
    }

    /**
     * @notice Calculate boost multiplier based on staking duration
     * @param _user Address of the user
     * @return Boost multiplier (100 = 1x, 150 = 1.5x, etc.)
     */
    function calculateBoostMultiplier(
        address _user
    ) public view returns (uint256) {
        // Requirements:
        // 1. Calculate staking duration
        // 2. Return appropriate multiplier based on duration thresholds
        UserInfo storage user = userInfo[_user];
        if (user.amount == 0) return 100;

        uint256 stakingDuration = block.timestamp - user.startTime;

        if (stakingDuration >= BOOST_THRESHOLD_3) {
            return 200; // 2x boost
        } else if (stakingDuration >= BOOST_THRESHOLD_2) {
            return 150; // 1.5x boost
        } else if (stakingDuration >= BOOST_THRESHOLD_1) {
            return 125; // 1.25x boost
        } else {
            return 100; // No boost
        }
    }

    /**
     * @notice Update reward rate
     * @param _newRate New reward rate per second
     */
    function updateRewardRate(uint256 _newRate) external onlyOwner {
        // Requirements:
        // 1. Update rewards before changing rate
        // 2. Set new reward rate
        if (_newRate == 0) revert ZeroValue();
        updateReward(address(0));
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
