pragma solidity ^0.5.0;

import "./IERC777.sol";
import "./IERC777Recipient.sol";
import "./IERC777Sender.sol";
import "../../token/ERC20/IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";
import "../../introspection/IERC1820Registry.sol";

/**
 * @dev Implementation of the `IERC777` interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using `_mint`.
 *
 * Support for ERC20 is included in this contract, as specified by the EIP: both
 * the ERC777 and ERC20 interfaces can be safely used when interacting with it.
 * Both `IERC777.Sent` and `IERC20.Transfer` events are emitted on token
 * movements.
 *
 * Additionally, the `granularity` value is hard-coded to `1`, meaning that there
 * are no special restrictions in the amount of tokens that created, moved, or
 * destroyed. This makes integration with ERC20 applications seamless.
 */
contract ERC777 is IERC777, IERC20 {
    using SafeMath for uint256;
    using Address for address;

    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    mapping(address => uint256) private _balances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    // We inline the result of the following hashes because Solidity doesn't resolve them at compile time.
    // See https://github.com/ethereum/solidity/issues/4024.

    // keccak256("ERC777TokensSender")
    bytes32 constant private TOKENS_SENDER_INTERFACE_HASH =
        0x29ddb589b1fb5fc7cf394961c1adf5f8c6454761adf795e67fe149f658abe895;

    // keccak256("ERC777TokensRecipient")
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH =
        0xb281fc8c12954d22544db45de3159a39272895b169a852b314f9cc762e44c53b;

    // This isn't ever read from - it's only used to respond to the defaultOperators query.
    address[] private _defaultOperatorsArray;

    // Immutable, but accounts may revoke them (tracked in __revokedDefaultOperators).
    mapping(address => bool) private _defaultOperators;

    // For each account, a mapping of its operators and revoked default operators.
    mapping(address => mapping(address => bool)) private _operators;
    mapping(address => mapping(address => bool)) private _revokedDefaultOperators;

    // ERC20-allowances
    mapping (address => mapping (address => uint256)) private _allowances;

    /**
     * @dev `defaultOperators` may be an empty array.
     */
    constructor(
        string memory name,
        string memory symbol,
        address[] memory defaultOperators
    ) public {
        _name = name;
        _symbol = symbol;

        _defaultOperatorsArray = defaultOperators;
        for (uint256 i = 0; i < _defaultOperatorsArray.length; i++) {
            _defaultOperators[_defaultOperatorsArray[i]] = true;
        }

        // register interfaces
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));
        _erc1820.setInterfaceImplementer(address(this), keccak256("ERC20Token"), address(this));
    }

    /**
     * See `IERC777.name`.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * See `IERC777.symbol`.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * See `ERC20Detailed.decimals`.
     *
     * Always returns 18, as per the
     * [ERC777 EIP](https://eips.ethereum.org/EIPS/eip-777#backward-compatibility).
     */
    function decimals() public pure returns (uint8) {
        return 18;
    }

    /**
     * See `IERC777.granularity`.
     *
     * This implementation always returns `1`.
     */
    function granularity() public view returns (uint256) {
        return 1;
    }

    /**
     * See `IERC777.totalSupply`.
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Returns the amount of tokens owned by an account (`owner`).
     */
    function balanceOf(address tokenHolder) public view returns (uint256) {
        return _balances[tokenHolder];
    }

    /**
     * @dev See `IERC777.send`.
     *
     * Also emits a `Transfer` event for ERC20 compatibility.
     */
    function send(address to, uint256 amount, bytes calldata data) external {
        _sendRequiringReceptionAck(msg.sender, msg.sender, to, amount, data, "");
    }

    /**
     * @dev See `IERC20.transfer`.
     *
     * Unlike `send`, `to` is _not_ required to implement the `tokensReceived`
     * interface if it is a contract.
     *
     * Also emits a `Sent` event.
     */
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, msg.sender, to, value);
        return true;
    }

    /**
     * @dev See `IERC777.burn`.
     *
     * Also emits a `Transfer` event for ERC20 compatibility.
     */
    function burn(uint256 amount, bytes calldata data) external {
        _burn(msg.sender, msg.sender, amount, data, "");
    }

    /**
     * @dev See `IERC777.isOperatorFor`.
     */
    function isOperatorFor(
        address operator,
        address tokenHolder
    ) public view returns (bool) {
        return operator == tokenHolder ||
            (_defaultOperators[operator] && !_revokedDefaultOperators[tokenHolder][operator]) ||
            _operators[tokenHolder][operator];
    }

    /**
     * @dev See `IERC777.authorizeOperator`.
     */
    function authorizeOperator(address operator) external {
        require(msg.sender != operator, "ERC777: authorizing self as operator");

        if (_defaultOperators[operator]) {
            delete _revokedDefaultOperators[msg.sender][operator];
        } else {
            _operators[msg.sender][operator] = true;
        }

        emit AuthorizedOperator(operator, msg.sender);
    }

    /**
     * @dev See `IERC777.revokeOperator`.
     */
    function revokeOperator(address operator) external {
        require(operator != msg.sender, "ERC777: revoking self as operator");

        if (_defaultOperators[operator]) {
            _revokedDefaultOperators[msg.sender][operator] = true;
        } else {
            delete _operators[msg.sender][operator];
        }

        emit RevokedOperator(operator, msg.sender);
    }

    /**
     * @dev See `IERC777.defaultOperators`.
     */
    function defaultOperators() public view returns (address[] memory) {
        return _defaultOperatorsArray;
    }

    /**
     * @dev See `IERC777.operatorSend`.
     *
     * Emits `Sent` and `Transfer` events.
     */
    function operatorSend(
        address from,
        address to,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    )
    external
    {
        require(isOperatorFor(msg.sender, from), "ERC777: caller is not an operator for holder");
        _sendRequiringReceptionAck(msg.sender, from, to, amount, data, operatorData);
    }

    /**
     * @dev See `IERC777.operatorBurn`.
     *
     * Emits `Sent` and `Transfer` events.
     */
    function operatorBurn(address from, uint256 amount, bytes calldata data, bytes calldata operatorData) external {
        require(isOperatorFor(msg.sender, from), "ERC777: caller is not an operator for holder");
        _burn(msg.sender, from, amount, data, operatorData);
    }

    /**
     * @dev See `IERC20.allowance`.
     *
     * Note that operator and allowance concepts are orthogonal: operators may
     * not have allowance, and accounts with allowance may not be operators
     * themselves.
     */
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See `IERC20.approve`.
     *
     * Note that accounts cannot have allowance issued by their operators.
     */
    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

   /**
    * @dev See `IERC20.transferFrom`.
    *
    * Note that operator and allowance concepts are orthogonal: operators cannot
    * call `transferFrom` (unless they have allowance), and accounts with
    * allowance cannot call `operatorSend` (unless they are operators).
    *
    * Emits `Sent` and `Transfer` events.
    */
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, from, to, value);
        _approve(from, msg.sender, _allowances[from][msg.sender].sub(value));
        return true;
    }

    /**
     * @dev Creates `amount` tokens and assigns them to a specified recipient
     * (`to`), increasing the total supply.
     *
     * If a send hook is registered for `to`, the corresponding function will be
     * called with `operator`, `data` and `operatorData`.
     *
     * See `IERC777Sender` and `IERC777Recipient`.
     *
     * Emits `Sent` and `Transfer` events.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     * - if `to` is a contract, it must implement the `tokensReceived`
     * interface.
     */
    function _mint(
        address operator,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    )
    internal
    {
        require(to != address(0), "ERC777: mint to the zero address");

        // Update state variables
        _totalSupply = _totalSupply.add(amount);
        _balances[to] = _balances[to].add(amount);

        _callTokensReceived(operator, address(0), to, amount, userData, operatorData, true);

        emit Minted(operator, to, amount, userData, operatorData);
        emit Transfer(address(0), to, amount);
    }

    function _transfer(address operator, address from, address to, uint256 amount) private {
        _sendAllowingNoReceptionAck(operator, from, to, amount, "", "");
    }

    function _sendRequiringReceptionAck(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) private {
        _send(operator, from, to, amount, userData, operatorData, true);
    }

    function _sendAllowingNoReceptionAck(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) private {
        _send(operator, from, to, amount, userData, operatorData, false);
    }

    /**
     * @dev Send tokens
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
     */
    function _send(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    )
    private
    {
        require(from != address(0), "ERC777: transfer from the zero address");
        require(to != address(0), "ERC777: transfer to the zero address");

        _callTokensToSend(operator, from, to, amount, userData, operatorData);

        // Update state variables
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount);

        _callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);

        emit Sent(operator, from, to, amount, userData, operatorData);
        emit Transfer(from, to, amount);
    }

    /**
     * @dev Burn tokens
     * @param operator address operator requesting the operation
     * @param from address token holder address
     * @param amount uint256 amount of tokens to burn
     * @param data bytes extra information provided by the token holder
     * @param operatorData bytes extra information provided by the operator (if any)
     */
    function _burn(
        address operator,
        address from,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    )
    private
    {
        require(from != address(0), "ERC777: burn from the zero address");

        _callTokensToSend(operator, from, address(0), amount, data, operatorData);

        // Update state variables
        _totalSupply = _totalSupply.sub(amount);
        _balances[from] = _balances[from].sub(amount);

        emit Burned(operator, from, amount, data, operatorData);
        emit Transfer(from, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 value) private {
        // TODO: restore this require statement if this function becomes internal, or is called at a new callsite. It is
        // currently unnecessary.
        //require(owner != address(0), "ERC777: approve from the zero address");
        require(spender != address(0), "ERC777: approve to the zero address");

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /**
     * @dev Call from.tokensToSend() if the interface is registered
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     */
    function _callTokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    )
    private
    {
        address implementer = _erc1820.getInterfaceImplementer(from, TOKENS_SENDER_INTERFACE_HASH);
        if (implementer != address(0)) {
            IERC777Sender(implementer).tokensToSend(operator, from, to, amount, userData, operatorData);
        }
    }

    /**
     * @dev Call to.tokensReceived() if the interface is registered. Reverts if the recipient is a contract but
     * tokensReceived() was not registered for the recipient
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
     */
    function _callTokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    )
    private
    {
        address implementer = _erc1820.getInterfaceImplementer(to, TOKENS_RECIPIENT_INTERFACE_HASH);
        if (implementer != address(0)) {
            IERC777Recipient(implementer).tokensReceived(operator, from, to, amount, userData, operatorData);
        } else if (requireReceptionAck) {
            require(!to.isContract(), "ERC777: token recipient contract has no implementer for ERC777TokensRecipient");
        }
    }
}
