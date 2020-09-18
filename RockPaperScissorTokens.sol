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

contract RockPaperScissorToken is Pausable{
	using SafeMath for uint;
	using SafeERC20 for IERC20;

	uint public constant maxShare = 10000;
	uint public constant DAY = 86400;

	struct Game {
		uint 	wager;
		address token;
		address player1;
		address player2;
		uint8	p2Action;
		uint 	player1SecretHash;
		uint 	deadline;
		bool    ongoing;
		bool    created;
	}
	

	uint public houseShare = 0;
	mapping(address => Game) public  games;
	
	mapping(address => uint) public lockedPrizes;
	
	/**
	 * We will use uint8 to represent an action
	 * ROCK = 0
	 * PAPER = 1
	 * SCISSOR = 2
	 */
	
	event GameCreated(address indexed player1, address token ,uint wager);
	event GameJoined(address indexed player1, address indexed player2, address token, uint wager, uint deadline);
	event GameEnded(address indexed winner, address indexed loser, address token, uint prize, uint8 p1Action, uint8 p2Action);
	event GameEndedByForfeit(address indexed winner, address indexed loser, uint prize);
	event GameCancelled(address indexed player1);


	/**
	 * @dev Cancels a game for msg.sender.
	 * 
	 * requirement: game.created == true mand game.created == false
	 *
	 * Emits a {GameCreated} event.
	 */
	function CancelGame() external isNotPaused {
		Game storage game = games[msg.sender];
		require (game.created && !game.ongoing, "Game cannot be cancelled");
		require (msg.sender == game.player1, "Not player 1");
		game.created = false;
		IERC20(game.token).safeTransfer(msg.sender, game.wager);
		emit GameCancelled(msg.sender);
	}

	/**
	 * @dev Creates a new game for msg.sender.
	 * _p2 may be set to address(0) if game is public or to a specified address to play against one person in particular.
	 * _hash represents the the hash of the keccak encryption of player1's outcome and a random secret.
	 * _token represents the token address
	 * _amount represents the amount of tokens to wager
	 * 
	 * Using web3.js, for outcome _out (uint8) and secret _secret (uint256)
	 * hash = web3.utils.soliditySha3({type: 'uint8', value: _out}, {type: 'uint256', value: _secret});
	 * 
	 * requirement: game.created and game.created must be false
	 *
	 * Emits a {GameCreated} event.
	 */
	function CreateGame(address _p2, uint _hash, address _token, uint _amount) external isNotPaused {
		Game storage game = games[msg.sender];
		require (!game.ongoing && !game.created, "Game not in clean state");
		require (_p2 != msg.sender, "Cannot play against yourself");
		require (_amount > 0, "Bet cannot be 0");
		require (IERC20(_token).balanceOf(msg.sender) >= _amount, "Player does not have sufficient balance");
		IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
		lockedPrizes[_token] = lockedPrizes[_token].add(_amount);
		game.wager = _amount;
		game.token = _token;
		game.player1 = msg.sender;
		game.player2 = _p2;
		game.player1SecretHash = _hash;
		game.created = true;
		emit GameCreated(msg.sender, _token, _amount);
	}

	/**
	 * @dev Allows player 2 to join a created game and give his outcome
	 * _outcome is player 2's choice
	 * _p1 is the address mapped to the game player 2 wishes to join
	 * _token represents the token address
	 * _amount represents the amount of tokens to wager
	 * 
	 * Player 2 must match player 1's wager.
	 * 
	 * requirement : player 2 game.created and game.ongoing must be false
	 *              _token == game.token
	 * 
	 * Emits a {GameJoined} event.
	 */
	function JoinGameAndPlay(uint8 _action, address _p1, address _token, uint _amount) external isNotPaused{
		Game memory p2Game = games[msg.sender];
		require (!p2Game.ongoing && !p2Game.created, "Joining player has ongoing game");
		
		Game storage game = games[_p1];
		require (game.created && !game.ongoing, "Game ongoing");
		require (game.player2 == msg.sender || game.player2 == address(0), "Joining player not allowed to join game");
		require (_amount == game.wager, "Bet does not match record");
		require (_token == game.token, "Tokens do not match");
		require (IERC20(_token).balanceOf(msg.sender) >= _amount, "Player does not have sufficient balance");
		IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
		lockedPrizes[_token] = lockedPrizes[_token].add(_amount);
		if (game.player2 == address(0))
			game.player2 = msg.sender;
		game.p2Action = _action % 3;
		game.deadline = block.timestamp.add(DAY);
		game.ongoing = true;
		games[msg.sender] = game;
		emit GameJoined(_p1, msg.sender, _token, game.wager, game.deadline);
	}
	
	/**
	 * @dev Allows player 2 to claim the prize if player 1 takes too long to reveal his move
	 * 
	 * reuirement: function call must happen after the deadline of 24 hours
	 * 
	 * Requires that both player 1 and player 2 are playing against each other
	 * 
	 * Emits a {GameEndedByForfeit} event.
	 */
	function ClaimByForfeit() external isNotPaused{
		Game storage game = games[msg.sender];
		require (game.player2 == msg.sender, "Not player 2");
		Game memory gameP1Perspective = games[game.player1];
		require (game.ongoing && gameP1Perspective.ongoing, "Game does not exist");
		require (block.timestamp >= game.deadline, "Deadline has not been reached");
		uint prize = game.wager.mul(2).mul(maxShare.sub(houseShare)).div(maxShare);
		IERC20(game.token).safeTransfer(msg.sender, prize);
		lockedPrizes[game.token] = lockedPrizes[game.token].sub(game.wager.mul(2));
		game.ongoing = false;
		game.created = false;
		games[game.player1] = game;
		emit GameEndedByForfeit(msg.sender, game.player1, prize);
	}
	
	
	/**
	 * @dev Allows player 1 to reveal his action
	 * _action is player 1's choice
	 * _secret is a random uint256 value that he chose to hash his action
	 * 
	 * Requires that both player 1 and player 2 are playing against each other
	 * 
	 * Emits a {GameEnded} event.
	 */
	function RevealGame(uint8 _action, uint _secret) external isNotPaused{
		Game storage game = games[msg.sender];

		require (msg.sender != game.player2, "Player cannot be player 2");
		Game memory gameP2Perspective = games[game.player2];
		require (game.ongoing && gameP2Perspective.ongoing, "Game does not exist");

		uint secretHash = uint(keccak256(abi.encodePacked(_action, _secret)));
		require (secretHash == game.player1SecretHash, "Hash values do not match");
		uint8 p1Action = _action % 3;
		address winner;
		address loser;
		(winner, loser) = GetWinner(msg.sender, game.player2, p1Action, game.p2Action);
		uint prize = game.wager.mul(2).mul(maxShare.sub(houseShare)).div(maxShare);
		if (winner == address(0)) {
			IERC20(game.token).safeTransfer(msg.sender, prize.div(2));
			IERC20(game.token).safeTransfer(game.player2, prize.div(2));
		}
		else {
			IERC20(game.token).safeTransfer(winner, prize);
		}
		lockedPrizes[game.token] = lockedPrizes[game.token].sub(game.wager.mul(2));
		emit GameEnded(winner, loser, game.token, prize, p1Action, game.p2Action);
		game.ongoing = false;
		game.created = false;
		games[game.player2] = game;
	}

	function GetWinner(address _p1, address _p2, uint8 _out1, uint8 _out2) internal pure returns(address, address) {
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
}