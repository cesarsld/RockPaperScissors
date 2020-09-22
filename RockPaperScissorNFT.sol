pragma solidity ^0.7.0;

interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function setApprovalForAll(address operator, bool _approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
    external returns (bytes4);
}

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

contract RockPaperScissorNFT is Pausable, IERC721Receiver{
	using SafeMath for uint;

	uint public constant DAY = 86400;
	enum GameState {NULL, CREATED, PENDING, ONGOING, CANCELLED, OVER}
	enum Action {ROCK, PAPER, SCISSOR}

	struct Game {
		address 	nft1;
		address 	nft2;
		uint		tokenId1;
		uint		tokenId2;
		address 	player1;
		address 	player2;
		Action		p1Action;
		Action		p2Action;
		uint 		player1SecretHash;
		uint		player2SecretHash;
		uint 		deadline;
		GameState	state;
	}
	
	uint gameFee = 0;
	uint warrant;
	mapping(address => Game) public  games;
	mapping(address => bool) public whitelistedNFTs;
	
	event GameCreated(address indexed player1, address nft ,uint tokenId);
	event GameJoined(address indexed player1, address indexed player2, address nft1, uint tokenId1, address nft2, uint tokenId2, uint deadline);
	event GameOngoing(address indexed player1, address indexed player2);
	event GameEnded(address indexed winner, address indexed loser, address nftPrize, uint tokenIdPrize, Action p1Action, Action p2Action);
	event GameEndedByForfeit(address indexed winner, address indexed loser, address nftPrize, uint tokenIdPrize);
	event GameCancelled(address indexed player1);
	event GameDraw(address indexed player1, address indexed player2);

	/**
	 * @dev Whitelists an address to wager on
	 * 
	 * requirement: must be contract owner
	 */
	function WhitelistNFTAddress(address _nft) external onlyOwner {
		whitelistedNFTs[_nft] = true;
	}

	/**
	 * @dev Blacklists an address to wager on
	 * 
	 * requirement: must be contract owner
	 */
	function blacklistNFTAddress(address _nft) external onlyOwner {
		whitelistedNFTs[_nft] = false;
	}

	/**
	 * @dev Cancels a game for msg.sender.
	 * 
	 * requirement: game.created == true and game.pending == false
	 * calls internal function to handle player1 or player 2 cancels
	 *
	 * Emits a {GameCancelled} event.
	 */
	function CancelGame() external isNotPaused {
		Game storage game = games[msg.sender];
		require (game.state == GameState.CREATED || game.state == GameState.PENDING ||
				game.state == GameState.CANCELLED, "Game cannot be cancelled");
		if (game.player1 == msg.sender)
			_cancelFromP1Perspective(game);
		else if (game.player2 == msg.sender)
			_cancelFromP2Perspective(game);
		emit GameCancelled(msg.sender);
	}

	function _cancelFromP1Perspective(Game storage game) internal {
		Game storage gameP2 = games[game.player2];
		if (game.state == GameState.PENDING)
			gameP2.state = GameState.CANCELLED;
		game.state = GameState.NULL;
		msg.sender.transfer(gameFee);
		IERC721(game.nft1).safeTransferFrom(address(this) , msg.sender, game.tokenId1);
	}

	function _cancelFromP2Perspective(Game storage game) internal {
		Game storage gameP1 = games[game.player1];
		if (game.state == GameState.PENDING)
			gameP1.state = GameState.CANCELLED;
		game.state = GameState.NULL;
		msg.sender.transfer(gameFee);
		IERC721(game.nft2).safeTransferFrom(address(this) , msg.sender, game.tokenId2);
	}

	/**
	 * @dev Creates a new game for msg.sender.
	 * _p2 may be set to address(0) if game is public or to a specified address to play against one person in particular.
	 * _hash represents the the hash of the keccak encryption of player1's outcome and a random secret.
	 * _nft represents the nft address
	 * _token represents the nft token ID
	 * 
	 * Using web3.js, for outcome _out (uint8) and secret _secret (uint256)
	 * hash = web3.utils.soliditySha3({type: 'uint8', value: _out}, {type: 'uint256', value: _secret});
	 * 
	 * requirement: game.created and game.ongoing must be false
	 *
	 * Emits a {GameCreated} event.
	 */
	function CreateGame(address _p2, address _nft, uint _tokenId) external payable isNotPaused {
		Game storage game = games[msg.sender];
		require (game.state == GameState.NULL || game.state == GameState.OVER, "Game not in clean state");
		require (_p2 != msg.sender, "Cannot play against yourself");
		require (whitelistedNFTs[_nft], "Token not supported");
		require (msg.value == gameFee, "Game fee is wrong");
		warrant = warrant.add(gameFee);
		game.nft1 = _nft;
		game.tokenId1 = _tokenId;
		game.player1 = msg.sender;
		game.player2 = _p2;
		game.state = GameState.CREATED;
		IERC721(game.nft1).safeTransferFrom(msg.sender, address(this), game.tokenId1);
		emit GameCreated(msg.sender, _nft, _tokenId);
	}

	/**
	 * @dev Allows player 2 to join a created game and give his hashed outcome
	 * _hash is player 2's hash
	 * _p1 is the address mapped to the game player 2 wishes to join
	 * _nft represents the NFT address
	 * _tokenId represents the nft's token ID
	 * 
	 * requirement : player 2 game.state must be NULL or OVER
	 * 
	 * Emits a {GameJoined} event.
	 */
	function JoinGameAndPlay(uint _hash, address _p1, address _nft, uint _tokenId) external payable isNotPaused{
		Game memory p2Game = games[msg.sender];
		require (p2Game.state == GameState.NULL || p2Game.state == GameState.OVER, "Joining player has ongoing game");
		Game storage game = games[_p1];
		require (game.state == GameState.CREATED, "Game not joinable");
		require (game.player2 == msg.sender || game.player2 == address(0), "Joining player not allowed to join game");
		require (whitelistedNFTs[_nft], "Token not supported");
		require (msg.value == gameFee, "Game fee is wrong");
		warrant = warrant.add(gameFee);
		if (game.player2 == address(0))
			game.player2 = msg.sender;
		game.nft2 = _nft;
		game.tokenId2 = _tokenId;
		game.player2SecretHash = _hash;
		game.state = GameState.PENDING;
		games[msg.sender] = game;
		IERC721(game.nft1).safeTransferFrom(msg.sender, address(this), _tokenId);
		emit GameJoined(_p1, msg.sender, game.nft1, game.tokenId1, game.nft2, game.tokenId2, game.deadline);
	}

	/**
	 * @dev Allows player 1 to accept player 2's wager
	 * _action is player 1's choice
	 * 
	 * Requires that both player 1 and player 2 are playing against each other
	 * 
	 * Emits a {GameEnded} event.
	 */
	function AcceptAndPlayGame(Action _action) external isNotPaused{
		Game storage game = games[msg.sender];
		require (msg.sender != game.player2, "Player cannot be player 2");
		Game memory gameP2Perspective = games[game.player2];
		require (game.state == GameState.PENDING && gameP2Perspective.player1 == msg.sender, "Game does not exist");
		game.p1Action = _action;
		game.deadline = block.timestamp.add(DAY);
		game.state = GameState.ONGOING;
		games[game.player2] = game;
		emit GameOngoing(game.player1, game.player2);
	}

	/**
	 * @dev Allows player 1 to claim the prize if player 2 takes too long to reveal his move
	 * 
	 * reuirement: function call must happen after the deadline of 24 hours
	 * 
	 * Requires that both player 1 and player 2 are playing against each other
	 * 
	 * Emits a {GameEndedByForfeit} event.
	 */
	function ClaimByForfeit() external isNotPaused{
		Game storage game = games[msg.sender];
		require (game.player1 == msg.sender, "Not player 1");
		require (game.state == GameState.ONGOING, "Game is not ongoing");
		require (block.timestamp >= game.deadline, "Deadline has not been reached");
		game.state = GameState.OVER;
		games[game.player1] = game;
		IERC721(game.nft2).safeTransferFrom(address(this), msg.sender, game.tokenId2);
		emit GameEndedByForfeit(msg.sender, game.player1, game.nft2, game.tokenId2);
	}


	/**
	 * @dev Allows player 2 to reveal his action
	 * _action is player 2's choice
	 * _secret is a random uint256 value that he chose to hash his action
	 * 
	 * Requires that both player 1 and player 2 are playing against each other
	 * 
	 * Emits a {GameEnded} or {GameDraw} event.
	 */
	function Player2Reveal(Action _action, uint _secret) external isNotPaused {
		address winner;
		address loser;
		Game storage game = games[msg.sender];
		uint secretHash = uint(keccak256(abi.encodePacked(_action, _secret)));

		require (msg.sender != game.player1, "Player cannot be player 1");
		require (game.state == GameState.ONGOING, "Game does not exist");
		require (secretHash == game.player2SecretHash, "Hash values do not match");

		game.p2Action = _action;
		(winner, loser) = GetWinner(msg.sender, game.player2, uint8(game.p1Action), uint8(game.p2Action));
		game.state = GameState.OVER;
		games[game.player2] = game;
		if (winner == address(0)) {
			IERC721(game.nft1).safeTransferFrom(address(this), game.player1, game.tokenId1);
			IERC721(game.nft2).safeTransferFrom(address(this), game.player2, game.tokenId2);
			emit GameDraw(winner, loser);
		}
		else {
			IERC721(game.nft1).safeTransferFrom(address(this), winner, game.tokenId1);
			IERC721(game.nft2).safeTransferFrom(address(this), winner, game.tokenId2);
			if (winner == game.player1)
				emit GameEnded(winner, loser, game.nft2, game.tokenId2, game.p1Action, game.p2Action);
			else
				emit GameEnded(winner, loser, game.nft1, game.tokenId1, game.p1Action, game.p2Action);
		}
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

	function SendEther(address payable _recipient) external onlyOwner {
			_recipient.transfer(address(this).balance);
	}

	function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
    external override pure returns (bytes4)  {
		return RockPaperScissorNFT.onERC721Received.selector;
	}
}