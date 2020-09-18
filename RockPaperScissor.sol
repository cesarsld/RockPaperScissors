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

	uint public constant maxShare = 10000;
	uint public constant DAY = 86400;

	struct Game {
		uint 	wager;
		address payable player1;
		address payable player2;
		uint8	p2Action;
		uint 	player1SecretHash;
		uint 	deadline;
		bool    ongoing;
		bool    created;
	}
	
	uint public lockedPrize;

	uint public houseShare = 0;
	mapping(address => Game) public  games;
	
	/**
	 * We will use uint8 to represent an action
	 * ROCK = 0
	 * PAPER = 1
	 * SCISSOR = 2
	 */
	
	event GameCreated(address indexed player1, uint wager);
	event GameJoined(address indexed player1, address indexed player2, uint wager, uint deadline);
	event GameEnded(address indexed winner, address indexed loser, uint prize, uint8 p1Action, uint8 p2Action);
	event GameEndedByForfeit(address indexed winner, address indexed loser, uint prize);
	event GameCancelled(address indexed player1);
	event GameDraw(address indexed player1, address indexed player2, uint wager);


	/**
	 * @dev Cancels a game for msg.sender.
	 * 
	 * requirement: game.created == true and game.ongoing == false
	 *
	 * Emits a {GameCreated} event.
	 */
	function CancelGame() external isNotPaused {
		Game storage game = games[msg.sender];
		require (game.created && !game.ongoing, "Game cannot be cancelled");
		require (msg.sender == game.player1, "Not player 1");
		game.created = false;
		msg.sender.transfer(game.wager);
		emit GameCancelled(msg.sender);
	}

	/**
	 * @dev Creates a new game for msg.sender.
	 * _p2 may be set to address(0) if game is public or to a specified address to play against one person in particular.
	 * _hash represents the the hash of the keccak encryption of player1's outcome and a random secret.
	 * 
	 * Using web3.js, for outcome _out (uint8) and secret _secret (uint256)
	 * hash = web3.utils.soliditySha3({type: 'uint8', value: _out}, {type: 'uint256', value: _secret});
	 * 
	 * requirement: game.created and game.ongoing must be false
	 *
	 * Emits a {GameCreated} event.
	 */
	function CreateGame(address payable _p2, uint _hash) external payable isNotPaused {
		Game storage game = games[msg.sender];
		require (!game.ongoing && !game.created, "Game not in clean state");
		require (_p2 != msg.sender, "Cannot play against yourself");
		require (msg.value > 0, "Bet cannot be 0");
		
		lockedPrize = lockedPrize.add(msg.value);
		game.wager = msg.value;
		game.player1 = msg.sender;
		game.player2 = _p2;
		game.player1SecretHash = _hash;
		game.created = true;
		emit GameCreated(msg.sender, msg.value);
	}

	/**
	 * @dev Allows player 2 to join a created game and give his outcome
	 * _outcome is player 2's choice
	 * _p1 is the address mapped to the game player 2 wishes to join
	 * 
	 * Player 2 must match player 1's wager.
	 * 
	 * requirement : player 2 game.created and game.ongoing must be false
	 * 
	 * Emits a {GameJoined} event.
	 */
	function JoinGameAndPlay(uint8 _action, address _p1) external payable isNotPaused{
		Game memory p2Game = games[msg.sender];
		require (!p2Game.ongoing && !p2Game.created, "Joining player has ongoing game");
		
		Game storage game = games[_p1];
		require (game.created && !game.ongoing, "Game ongoing");
		require (game.player2 == msg.sender || game.player2 == address(0), "Joining player not allowed to join game");
		require (msg.value >= game.wager, "Bet not equal to opponent");
		lockedPrize = lockedPrize.add(game.wager);
		uint remainder = msg.value.sub(game.wager);
		if (remainder > 0)
			msg.sender.transfer(remainder);
		if (game.player2 == address(0))
			game.player2 = msg.sender;
		game.p2Action = _action % 3;
		game.deadline = block.timestamp.add(DAY);
		game.ongoing = true;
		games[msg.sender] = game;
		emit GameJoined(_p1, msg.sender, game.wager, game.deadline);
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
		Game memory gameP1Perspective = games[game.player1];
		require (game.ongoing && gameP1Perspective.ongoing, "Game does not exist");
		require (block.timestamp >= game.deadline, "Deadline has not been reached");
		uint prize = game.wager.mul(2).mul(maxShare.sub(houseShare)).div(maxShare);
		msg.sender.transfer(prize);
		lockedPrize = lockedPrize.sub(game.wager.mul(2));
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
		address payable winner ;
		address loser;
		(winner, loser) = GetWinner(msg.sender, game.player2, p1Action, game.p2Action);
		uint prize = game.wager.mul(2).mul(maxShare.sub(houseShare)).div(maxShare);
		if (winner == address(0)) {
			msg.sender.transfer(prize.div(2));
			game.player2.transfer(prize.div(2));
			emit GameDraw(winner, loser, game.wager);
		}
		else {
			winner.transfer(prize);
			emit GameEnded(winner, loser, prize, p1Action, game.p2Action);
		}
		lockedPrize = lockedPrize.sub(game.wager.mul(2));
		game.ongoing = false;
		game.created = false;
		games[game.player2] = game;
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
}