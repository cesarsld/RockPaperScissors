pragma solidity ^0.7.0;

library SafeMath {
	function add(uint256 a, uint256 b) internal pure returns (uint256) {
		uint256 c = a + b;
		require(c >= a, "SafeMath: addition overflow");

		return c;
	}
	function sub(uint256 a, uint256 b) internal pure returns (uint256) {
		return sub(a, b, "SafeMath: subtraction overflow");
	}
	function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
		require(b <= a, errorMessage);
		uint256 c = a - b;

		return c;
	}
	function mul(uint256 a, uint256 b) internal pure returns (uint256) {
		if (a == 0) {
			return 0;
		}

		uint256 c = a * b;
		require(c / a == b, "SafeMath: multiplication overflow");

		return c;
	}
	function div(uint256 a, uint256 b) internal pure returns (uint256) {
		return div(a, b, "SafeMath: division by zero");
	}
	function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
		// Solidity only automatically asserts when dividing by 0
		require(b > 0, errorMessage);
		uint256 c = a / b;

		return c;
	}
	function mod(uint256 a, uint256 b) internal pure returns (uint256) {
		return mod(a, b, "SafeMath: modulo by zero");
	}
	function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
		require(b != 0, errorMessage);
		return a % b;
	}
}
interface IERC20 {
	function totalSupply() external view returns (uint256);
	function balanceOf(address account) external view returns (uint256);
	function transfer(address recipient, uint256 amount) external returns (bool);
	function allowance(address owner, address spender) external view returns (uint256);
	function approve(address spender, uint256 amount) external returns (bool);
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
	event Transfer(address indexed from, address indexed to, uint256 value);
	event Approval(address indexed owner, address indexed spender, uint256 value);
}
library SafeERC20 {
	using SafeMath for uint256;
	using Address for address;

	function safeTransfer(IERC20 token, address to, uint256 value) internal {
		callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
	}

	function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
		callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
	}

	function safeApprove(IERC20 token, address spender, uint256 value) internal {
		require((value == 0) || (token.allowance(address(this), spender) == 0),
			"SafeERC20: approve from non-zero to non-zero allowance"
		);
		callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
	}
	function callOptionalReturn(IERC20 token, bytes memory data) private {
		require(address(token).isContract(), "SafeERC20: call to non-contract");

		// solhint-disable-next-line avoid-low-level-calls
		(bool success, bytes memory returndata) = address(token).call(data);
		require(success, "SafeERC20: low-level call failed");

		if (returndata.length > 0) { // Return data is optional
			// solhint-disable-next-line max-line-length
			require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
		}
	}
}
library Address {
	function isContract(address account) internal view returns (bool) {
		bytes32 codehash;
		bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
		// solhint-disable-next-line no-inline-assembly
		assembly { codehash := extcodehash(account) }
		return (codehash != 0x0 && codehash != accountHash);
	}
	function toPayable(address account) internal pure returns (address payable) {
		return address(uint160(account));
	}
	function sendValue(address payable recipient, uint256 amount) internal {
		require(address(this).balance >= amount, "Address: insufficient balance");

		// solhint-disable-next-line avoid-call-value
		(bool success, ) = recipient.call{ value: amount }("");
		require(success, "Address: unable to send value, recipient may have reverted");
	}
}
contract Ownable {
	address public owner;

	constructor () {
		owner = msg.sender;
	}

	modifier onlyOwner() {
		require (msg.sender == owner, "Not owner");
		_;
	}
	
	function SetOwnership(address _newOwner) external onlyOwner {
		owner = _newOwner;
	}

	
}

contract Pausable is Ownable {
	bool public isPaused;
	
	constructor () {
		isPaused = false;
	}
	
	modifier isNotPaused() {
		require (!isPaused, "Game is paused");
		_;
	}
	
	function pause() external onlyOwner {
		isPaused = true;
	}
	
	function unpause() external onlyOwner {
		isPaused = false;
	}
}

contract RockPaperScissor is Pausable{
	using SafeMath for uint;
	using SafeERC20 for IERC20;
	using Address for address;


	address public constant ETH_ADDRESS = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
	uint public constant maxShare = 10000;
	uint public constant DAY = 86400;
	enum GameState {NULL, CREATED, ONGOING, CANCELLED, OVER}
	enum Action {ROCK, PAPER, SCISSOR}

	struct Game {
		uint 			wager;
		address			token;
		address payable player1;
		address payable player2;
		Action			p2Action;
		uint 			player1SecretHash;
		uint 			deadline;
		GameState   	state;
	}
	
	mapping(address => uint) public lockedPrizes;

	uint public houseShare = 0;
	mapping(address => Game) public  games;
	mapping(address => bool) public whitelistedTokens;
	
	constructor() {
		whitelistedTokens[ETH_ADDRESS] = true;
	}

	event GameCreated(address indexed player1, address token , uint wager);
	event GameJoined(address indexed player1, address indexed player2, address token, uint wager, uint deadline);
	event GameEnded(address indexed winner, address indexed loser, address token, uint prize, Action p1Action, Action p2Action);
	event GameEndedByForfeit(address indexed winner, address indexed loser, uint prize);
	event GameCancelled(address indexed player1);
	event GameDraw(address indexed player1, address indexed player2, address token, uint wager);

	/**
	 * @dev Whitelists an address to wager on
	 * 
	 * requirement: must be contract owner
	 */
	function WhitelistAddress(address _token) external onlyOwner {
		whitelistedTokens[_token] = true;
	}

	/**
	 * @dev Blacklists an address to wager on
	 * 
	 * requirement: must be contract owner
	 */
	function blacklistAddress(address _token) external onlyOwner {
		whitelistedTokens[_token] = false;
	}

	/**
	 * @dev Cancels a game for msg.sender.
	 * 
	 * requirement: game.state == CREATED
	 *
	 * Emits a {GameCancelled} event.
	 */
	function CancelGame() external isNotPaused {
		Game storage game = games[msg.sender];
		require (game.state == GameState.CREATED, "Game cannot be cancelled");
		require (msg.sender == game.player1, "Not player 1");
		game.state = GameState.NULL;
		if (game.token == ETH_ADDRESS)
		    msg.sender.transfer(game.wager);
		else
		    IERC20(game.token).safeTransfer(msg.sender, game.wager);
		emit GameCancelled(msg.sender);
	}

	/**
	 * @dev Creates a new game for msg.sender.
	 * _p2 may be set to address(0) if game is public or to a specified address to play against one person in particular.
	 * _hash represents the the hash of the keccak encryption of player1's outcome and a random secret.
	 * _token and _wager repsent the amount of a specific token to bet
	 * Ether is represented by the dummy 0xeeeeeee....eee address
	 * 
	 * Using web3.js, for outcome _out (uint8) and secret _secret (uint256)
	 * hash = web3.utils.soliditySha3({type: 'uint8', value: _out}, {type: 'uint256', value: _secret});
	 * 
	 * requirement: game.state must be NULL || OVER
	 *
	 * Emits a {GameCreated} event.
	 */
	function CreateGame(address payable _p2, uint _hash, address _token, uint _wager) external payable isNotPaused {
		Game storage game = games[msg.sender];
		require (game.state == GameState.NULL || game.state == GameState.OVER, "Game not in clean state");
		require (_p2 != msg.sender, "Cannot play against yourself");
		require (whitelistedTokens[_token], "Token not supported");
		if (_token == ETH_ADDRESS)
			require (msg.value > 0 && _wager == msg.value, "Bet cannot be 0");
		lockedPrizes[_token] = lockedPrizes[_token].add(_wager);
		game.token = _token;
		game.player1 = msg.sender;
		game.player2 = _p2;
		game.player1SecretHash = _hash;
		game.state = GameState.CREATED;
		if (_token != ETH_ADDRESS) {
			uint pre = IERC20(_token).balanceOf(msg.sender);
			IERC20(_token).safeTransferFrom(msg.sender, address(this), _wager);
			uint post = IERC20(_token).balanceOf(msg.sender);
			game.wager = post.sub(pre);
		}
		else
			game.wager = _wager;
		emit GameCreated(msg.sender, _token, msg.value);
	}

	/**
	 * @dev Allows player 2 to join a created game and give his outcome
	 * _action is player 2's choice
	 * _p1 is the address mapped to the game player 2 wishes to join
	 * _token and _wager repsent the amount of a specific token to bet
	 * 
	 * Player 2 must match player 1's wager.
	 * 
	 * requirement : player 2 game.state == NULL || OVER
	 * 
	 * Emits a {GameJoined} event.
	 */
	function JoinGameAndPlay(Action _action, address _p1, address _token, uint _wager) external payable isNotPaused{
		Game memory p2Game = games[msg.sender];
		require (p2Game.state == GameState.NULL || p2Game.state == GameState.OVER, "Game not in clean state");
		
		Game storage game = games[_p1];
		require (game.state == GameState.CREATED, "Game ongoing");
		require (game.player2 == msg.sender || game.player2 == address(0), "Joining player not allowed to join game");
		require (whitelistedTokens[_token], "Token not supported");
		if (_token == ETH_ADDRESS)
			require (msg.value == game.wager && _wager ==  msg.value, "Bet cannot be 0");
		lockedPrizes[_token] = lockedPrizes[_token].add(_wager);
		if (game.player2 == address(0))
			game.player2 = msg.sender;
		game.p2Action = _action;
		game.deadline = block.timestamp.add(DAY);
		game.state = GameState.ONGOING;
		games[msg.sender] = game;
		if (_token != ETH_ADDRESS){
			uint pre = IERC20(_token).balanceOf(msg.sender);
			IERC20(_token).safeTransferFrom(msg.sender, address(this), _wager);
			uint post = IERC20(_token).balanceOf(msg.sender);
			require(post.sub(pre) == game.wager, "Wager amount not the same");
		}
		emit GameJoined(_p1, msg.sender, game.token, game.wager, game.deadline);
	}
	
	/**
	 * @dev Allows player 2 to claim the prize if player 1 takes too long to reveal his move
	 * 
	 * Requirement: function call must happen after the deadline of 24 hours
	 * 
	 * Requires that both player 1 and player 2 are playing against each other
	 * 
	 * Emits a {GameEndedByForfeit} event.
	 */
	function ClaimByForfeit() external isNotPaused{
		Game storage game = games[msg.sender];
		require (game.player2 == msg.sender, "Not player 2");
		require (game.state == GameState.ONGOING, "Game does not exist");
		require (block.timestamp >= game.deadline, "Deadline has not been reached");
		uint prize = game.wager.mul(2).mul(maxShare.sub(houseShare)).div(maxShare);
		lockedPrizes[game.token] = lockedPrizes[game.token].sub(game.wager.mul(2));
		game.state = GameState.OVER;
		games[game.player1] = game;
		if (game.token == ETH_ADDRESS)
			msg.sender.transfer(prize);
		else
			IERC20(game.token).safeTransfer(msg.sender, prize);
		emit GameEndedByForfeit(msg.sender, game.player1, prize);
	}
	
	
	/**
	 * @dev Allows player 1 to reveal his action
	 * _action is player 1's choice
	 * _secret is a random uint256 value that he chose to hash his action
	 * 
	 * Requires that both player 1 and player 2 are playing against each other
	 * 
	 * Emits a {GameEnded} or {GameDraw} event.
	 */
	function RevealGame(Action _action, uint _secret) external isNotPaused{
		Game storage game = games[msg.sender];

		require (msg.sender != game.player2, "Player cannot be player 2");
		require (game.state == GameState.ONGOING, "Game does not exist");
		uint secretHash = uint(keccak256(abi.encodePacked(_action, _secret)));
		require (secretHash == game.player1SecretHash, "Hash values do not match");
		address payable winner ;
		address loser;
		lockedPrizes[game.token] = lockedPrizes[game.token].sub(game.wager.mul(2));
		game.state = GameState.OVER;
		games[game.player2] = game;
		(winner, loser) = GetWinner(msg.sender, game.player2, uint8(_action), uint8(game.p2Action));
		uint prize = ((game.wager.mul(maxShare.sub(houseShare))).div(maxShare));
		if (winner == address(0)) {
			if (game.token == ETH_ADDRESS) {
				msg.sender.transfer(prize);
				game.player2.transfer(prize);
			}
			else {
				IERC20(game.token).safeTransfer(msg.sender, prize);
				IERC20(game.token).safeTransfer(game.player2, prize);
			}
			emit GameDraw(game.player1, game.player2, loser, game.wager);
		}
		else {
			uint fullPrize = prize.mul(2);
			if (game.token == ETH_ADDRESS)
				winner.transfer(fullPrize);
			else
				IERC20(game.token).safeTransfer(winner, fullPrize);
			emit GameEnded(winner, loser, game.token, fullPrize, _action, game.p2Action);
		}
	}

	function GetWinner(address payable _p1, address payable _p2, uint8 _out1, uint8 _out2) internal pure returns(address payable, address) {
		if (_out1 == _out2) {
			return (address(0), address(0));
		}
		else if (_out1 > _out2) {
			if (_out2 + 1 == _out1)
				return (_p1, _p2);
			else
				return (_p2, _p1);
		}
		else {
			if (_out2 == _out1 + 1)
				return (_p2, _p1);
			else
				return (_p1, _p2);
		}
	}

	function SendTokens(address payable _recipient, address _token) external onlyOwner {
		if (_token == ETH_ADDRESS)
			_recipient.transfer(address(this).balance.sub(lockedPrizes[_token]));
		else {
			uint amount = IERC20(_token).balanceOf(address(this)).sub(lockedPrizes[_token]);
			IERC20(_token).safeTransfer(_recipient, amount);
		}
	}
}