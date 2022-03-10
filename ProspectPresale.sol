// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import './libraries/Ownable.sol';
import './libraries/SafeERC20.sol';

interface IUniswapV2Router01 {
  function addLiquidity(
      address tokenA,
      address tokenB,
      uint amountADesired,
      uint amountBDesired,
      uint amountAMin,
      uint amountBMin,
      address to,
      uint deadline
  ) external returns (uint amountA, uint amountB, uint liquidity);
}

interface IMintable {
    function mint(address account_, uint256 amount_) external;
}

interface IToken {
    function transfer(address to, uint256 amount) external;
}

contract ProspectPresale is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct UserInfo {
        uint256 amount; // Amount BUSD deposited by user
        uint256 debt; // total PECT claimed by user
        bool claimed; // True if a user has claimed PECT
    }

    IERC20 public BUSD;
    IERC20 public pPECT;
    IERC20 public PECT;
    IUniswapV2Router01 public router;
    address public dao;

    uint decimalsBUSD = 18;
    uint decimalsPECT = 18;

    constructor(
        address _pPECT,
        address _PECT,
        address _BUSD,
        address _router,
        address _dao
    ) {
        pPECT = IERC20(_pPECT);
        PECT = IERC20(_PECT);
        BUSD = IERC20(_BUSD);
        router = IUniswapV2Router01(_router);
        dao = _dao;
    }


    uint256 public price = 1 * 10**(decimalsBUSD - 3); // 0.001 BUSD per PECT

    uint256 public maxAllocation = 500 * 10**decimalsBUSD; // 500 BUSD per whitelist

    uint256 public totalRaisedBUSD; // total BUSD raised by sale

    uint256 public totalDebt; // total PECT owed to users

    bool public started; // true when sale starts

    bool public ended; // true when sale ends

    bool public claimable; // true when PECT is claimable

    bool public claimAlpha; // true when pPECT is claimable

    bool public contractPaused;

    mapping(address => UserInfo) public userInfo;

    mapping(address => bool) public whitelistedAdrs; // True if user is whitelisted

    mapping(address => uint256) public PECTClaimable; // amount of PECT claimable by address

    event Deposit(address indexed who, uint256 amount);
    event Withdraw(address token, address indexed who, uint256 amount);
    event SaleStarted(uint256 block);
    event SaleEnded(uint256 block);
    event ClaimUnlocked(uint256 block);
    event ClaimAlphaUnlocked(uint256 block);
    event AdminWithdrawal(address token);

    //* @notice modifer to check if contract is paused
    modifier checkIfPaused() {
        require(contractPaused == false, "contract is paused");
        _;
    }
    /**
     *  @notice adds a single whitelist to the sale
     *  @param _address: address to whitelist
     */
    function addWhitelist(address _address) external onlyOwner {
        whitelistedAdrs[_address] = true;
    }

    /**
     *  @notice adds multiple whitelist to the sale
     *  @param _addresses: dynamic array of addresses to whitelist
     */
    function addWhitelistArray(address[] calldata _addresses) external onlyOwner {
        require(_addresses.length <= 200,"too many addresses");
        for (uint256 i = 0; i < _addresses.length; i++) {
            whitelistedAdrs[_addresses[i]] = true;
        }
    }

    /**
     *  @notice removes a single whitelist from the sale
     *  @param _address: address to remove from whitelist
     */
    function removeWhitelist(address _address) external onlyOwner {
        whitelistedAdrs[_address] = false;
    }

    // @notice Starts the sale
    function start() external onlyOwner {
        require(!started, "Sale has already started");
        started = true;
        emit SaleStarted(block.number);
    }

    // @notice Ends the sale
    function end() external onlyOwner {
        require(started, "Sale has not started");
        require(!ended, "Sale has already ended");
        ended = true;
        emit SaleEnded(block.number);
    }

    // @notice lets users claim PECT
    function claimUnlock() external onlyOwner {
        require(ended, "Sale has not ended");
        require(!claimable, "Claim has already been unlocked");
        
        claimable = true;
        emit ClaimUnlocked(block.number);
    }

    // @notice lets owner pause contract
    function togglePause() external onlyOwner returns (bool){
        contractPaused = !contractPaused;
        return contractPaused;
    }

    /**
     *  @notice deposits BUSD
     *  @param _amount: amount of BUSD to deposit
     */
    function deposit(uint256 _amount) external checkIfPaused {
        require(started, 'Sale has not started');
        require(!ended, 'Sale has ended');
        require(whitelistedAdrs[msg.sender] == true, 'sender is not whitelisted');

        UserInfo storage user = userInfo[msg.sender];

        require(maxAllocation >= user.amount.add(_amount), 'new amount above user limit');

        user.amount = user.amount.add(_amount);
        totalRaisedBUSD = totalRaisedBUSD.add(_amount);

        uint256 payout = _amount.mul(10**decimalsPECT).div(price); // pPECT to mint for _amount
        totalDebt = totalDebt.add(payout);

        BUSD.safeTransferFrom(msg.sender, address(this), _amount);
            
        IMintable(address(pPECT)).mint(address(msg.sender), payout);

        emit Deposit(msg.sender, _amount);
    }

    /**
     *  @notice it deposits pPECT to withdraw PECT from the sale
     *  @param _amount: amount of pPECT to deposit to sale
     */
    function withdraw(uint256 _amount) external checkIfPaused {
        require(claimable, 'PECT is not yet claimable');
        require(_amount > 0, '_amount must be greater than zero');

        UserInfo storage user = userInfo[msg.sender];

        user.debt = user.debt.add(_amount);

        totalDebt = totalDebt.sub(_amount);

        pPECT.safeTransferFrom( msg.sender, address(this), _amount );

        IMintable(address(PECT)).mint(msg.sender, _amount);

        emit Withdraw(address(PECT), msg.sender, _amount);
    }

    // @notice it checks a users BUSD allocation remaining
    function getUserRemainingAllocation(address _user) external view returns ( uint256 ) {
        require(whitelistedAdrs[_user] == true, 'msg.sender is not whitelisted user');
        UserInfo memory user = userInfo[_user];
        
        return maxAllocation.sub(user.amount);
    }

    function addLiquidityAfterPresale(uint PECTAmount, uint BUSDAmount) onlyOwner external {
        IMintable(address(PECT)).mint(address(this), PECTAmount);
        PECT.approve(address(router), PECTAmount);
        BUSD.approve(address(router), BUSDAmount);
        router.addLiquidity(address(PECT), address(BUSD), PECTAmount, BUSDAmount, 1, 1, dao, block.timestamp + 1);
    }

    function withdrawToDao(uint amount, address tokenAdrs) onlyOwner external {
        IToken(tokenAdrs).transfer(dao, amount);
    }
}
