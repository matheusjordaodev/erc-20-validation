// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/// @notice Minimal interface for an ERC20 token that supports minting, transferFrom, and burning.
interface IERC20MintableBurnable {
    function mint(address to, uint256 amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function burn(uint256 amount) external;
}

/// @notice Minimal interface for an ERC1155 token that supports minting.
interface IERC1155Minter {
    function mint(address to, uint256 id, uint256 amount, bytes memory data) external;
}

/// @title DualERC1155ERC20Converter
/// @notice This contract supports two conversion directions:
///         1. Forward conversion (ERC1155 -> ERC20): when the contract receives ERC1155 tokens,
///            it mints ERC20 tokens (1:1 ratio) to the sender if the pair is allowed.
///         2. Reverse conversion (ERC20 -> ERC1155): a user can convert ERC20 tokens into ERC1155 tokens
///            by calling a function. The contract transfers and burns the ERC20 tokens and then
///            calls mint on an allowed ERC1155 contract.
///         Allowed ERC1155 token pairs (contract address and token ID) are configured separately
///         for forward and reverse conversions. The ERC20 token is set via an admin function.
contract DualERC1155ERC20Converter is Ownable, ERC1155Holder {
    /// @notice The ERC20 token used in conversion.
    IERC20MintableBurnable public erc20Token;

    // --- Allowed Mappings ---
    /// @notice Allowed ERC1155 contract/token pairs for forward conversion (ERC1155 -> ERC20).
    /// When an ERC1155 token is sent to this contract, the sender receives ERC20 tokens if
    /// allowedERC1155Forward[erc1155Contract][tokenId] is true.
    mapping(address => mapping(uint256 => bool)) public allowedERC1155Forward;

    /// @notice Allowed ERC1155 contract/token pairs for reverse conversion (ERC20 -> ERC1155).
    /// When converting ERC20 tokens, the specified ERC1155 contract/token pair must be allowed.
    mapping(address => mapping(uint256 => bool)) public allowedERC1155Reverse;

    /// @notice Structure that records details of a conversion.
    struct ConversionRecord {
        uint256 erc1155TokenId; // The ERC1155 token ID that was received.
        uint256 erc1155Amount;  // The amount of ERC1155 tokens received.
        uint256 erc20Amount;    // The amount of ERC20 tokens minted.
        uint256 timestamp;      // The time the conversion occurred.
    }

    /// @notice Mapping from a sender address to an array of conversion records.
    mapping(address => ConversionRecord[]) public conversionRecordsBySender;
    /// @notice Global array of all conversion records.
    ConversionRecord[] public conversionHistory;

    // --- History Structures for Reverse Conversion ---
    struct ConversionRecordERC20ToERC1155 {
        address user;
        address erc1155Contract;
        uint256 tokenId;
        uint256 amount;
        uint256 timestamp;
    }
    
    /// @notice Global array of reverse conversion records.
    ConversionRecordERC20ToERC1155[] public erc20ToErc1155History;
    
    /// @notice Mapping from a user address to an array of their reverse conversion records.
    mapping(address => ConversionRecordERC20ToERC1155[]) public conversionRecordsERC20ToERC1155ByUser;
    

    /// @notice Emitted when a conversion is performed.
    event ConversionPerformed(
        address indexed sender,
        uint256 indexed erc1155TokenId,
        uint256 erc1155Amount,
        uint256 erc20Amount,
        uint256 timestamp
    );
    // --- Events ---
    event ERC20TokenUpdated(address indexed previousERC20, address indexed newERC20);
    event AllowedERC1155ForwardAdded(address indexed erc1155Contract, uint256 indexed tokenId);
    event AllowedERC1155ForwardRemoved(address indexed erc1155Contract, uint256 indexed tokenId);
    event AllowedERC1155ReverseAdded(address indexed erc1155Contract, uint256 indexed tokenId);
    event AllowedERC1155ReverseRemoved(address indexed erc1155Contract, uint256 indexed tokenId);
    event ERC1155ToERC20Conversion(
        address indexed sender,
        address indexed erc1155Contract,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 timestamp
    );
    event ERC20ToERC1155Conversion(
        address indexed user,
        address indexed erc1155Contract,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @notice Constructor that passes msg.sender to Ownable.
     */
    constructor() Ownable(msg.sender) {}

    // --- Admin Functions ---

    /**
     * @notice Sets (or updates) the ERC20 token contract address.
     * @param _erc20Token The address of the ERC20 token contract.
     */
    function setERC20Token(address _erc20Token) external onlyOwner {
        require(_erc20Token != address(0) && _erc20Token.code.length > 0, "Invalid ERC20 token address");
        address previous = address(erc20Token);
        erc20Token = IERC20MintableBurnable(_erc20Token);
        emit ERC20TokenUpdated(previous, _erc20Token);
    }

    /**
     * @notice Adds an allowed ERC1155 contract/token pair for forward conversion.
     * @param erc1155Contract The ERC1155 contract address.
     * @param tokenId The ERC1155 token id.
     */
    function addAllowedERC1155Forward(address erc1155Contract, uint256 tokenId) external onlyOwner {
        require(erc1155Contract != address(0) && erc1155Contract.code.length > 0, "Invalid ERC1155 address");
        allowedERC1155Forward[erc1155Contract][tokenId] = true;
        emit AllowedERC1155ForwardAdded(erc1155Contract, tokenId);
    }

    /**
     * @notice Removes an allowed ERC1155 contract/token pair for forward conversion.
     * @param erc1155Contract The ERC1155 contract address.
     * @param tokenId The ERC1155 token id.
     */
    function removeAllowedERC1155Forward(address erc1155Contract, uint256 tokenId) external onlyOwner {
        allowedERC1155Forward[erc1155Contract][tokenId] = false;
        emit AllowedERC1155ForwardRemoved(erc1155Contract, tokenId);
    }

    /**
     * @notice Adds an allowed ERC1155 contract/token pair for reverse conversion.
     * @param erc1155Contract The ERC1155 contract address.
     * @param tokenId The ERC1155 token id.
     */
    function addAllowedERC1155Reverse(address erc1155Contract, uint256 tokenId) external onlyOwner {
        require(erc1155Contract != address(0) && erc1155Contract.code.length > 0, "Invalid ERC1155 address");
        allowedERC1155Reverse[erc1155Contract][tokenId] = true;
        emit AllowedERC1155ReverseAdded(erc1155Contract, tokenId);
    }

    /**
     * @notice Removes an allowed ERC1155 contract/token pair for reverse conversion.
     * @param erc1155Contract The ERC1155 contract address.
     * @param tokenId The ERC1155 token id.
     */
    function removeAllowedERC1155Reverse(address erc1155Contract, uint256 tokenId) external onlyOwner {
        allowedERC1155Reverse[erc1155Contract][tokenId] = false;
        emit AllowedERC1155ReverseRemoved(erc1155Contract, tokenId);
    }

    // --- Forward Conversion (ERC1155 -> ERC20) ---
    // When this contract receives ERC1155 tokens, it will mint ERC20 tokens to the sender.
    // The conversion is triggered via the safeTransfer hooks.

    /**
     * @notice Called when a single ERC1155 token type is transferred to this contract.
     * Requirements:
     * - The caller (operator) must equal the token owner (`from`).
     * - The ERC1155 contract (msg.sender) and token id must be allowed for forward conversion.
     * @return bytes4 indicating acceptance.
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes memory data
    ) public override returns (bytes4) {
        require(operator == from, "Only the token owner can trigger conversion");
        require(allowedERC1155Forward[msg.sender][id], "ERC1155 token not allowed for conversion");
        require(address(erc20Token) != address(0), "ERC20 token not set");

        _convertERC1155ToERC20(from, id, value);
        return this.onERC1155Received.selector;
    }

        /**
     * @notice Internal function that performs the conversion.
     * It verifies that the total converted by the sender (for this token ID) does not exceed
     * the sender's original balance. The sender's original balance is derived as the current balance
     * in the ERC1155 token contract plus the transferred amount.
     *
     * @param sender The address of the original ERC1155 token holder.
     * @param erc1155TokenId The ERC1155 token ID that was received.
     * @param erc1155Amount The amount of ERC1155 tokens received.
     */
    function _convertERC1155ToERC20(
        address sender,
        uint256 erc1155TokenId,
        uint256 erc1155Amount
    ) internal {
        // In this example, we use a 1:1 conversion ratio.
        uint256 erc20Amount = erc1155Amount;
        require(address(erc20Token) != address(0), "ERC20 token not defined");

        // Mint the ERC20 tokens to the sender.
        erc20Token.mint(sender, erc20Amount);

        // Record the conversion.
        ConversionRecord memory record = ConversionRecord({
            erc1155TokenId: erc1155TokenId,
            erc1155Amount: erc1155Amount,
            erc20Amount: erc20Amount,
            timestamp: block.timestamp
        });
        conversionHistory.push(record);
        conversionRecordsBySender[sender].push(record);

        emit ConversionPerformed(sender, erc1155TokenId, erc1155Amount, erc20Amount, block.timestamp);
    }

    /**
     * @notice Called when multiple ERC1155 token types are transferred in a batch.
     * Requirements:
     * - The caller (operator) must equal the token owner (`from`).
     * - Each ERC1155 contract (msg.sender) and token id must be allowed.
     * @return bytes4 indicating acceptance.
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public override returns (bytes4) {
        require(operator == from, "Only the token owner can trigger conversion");
        require(ids.length == values.length, "IDs and values length mismatch");
        require(address(erc20Token) != address(0), "ERC20 token not set");

        for (uint256 i = 0; i < ids.length; i++) {
            require(allowedERC1155Forward[msg.sender][ids[i]], "One or more ERC1155 tokens not allowed for conversion");
            erc20Token.mint(from, values[i]);
            emit ERC1155ToERC20Conversion(from, msg.sender, ids[i], values[i], block.timestamp);
        }
        return this.onERC1155BatchReceived.selector;
    }

    // --- Reverse Conversion (ERC20 -> ERC1155) ---
    // A user calls this function to convert their ERC20 tokens back into ERC1155 tokens.
    // The user must have approved this contract to spend the required amount of ERC20 tokens.
    /**
     * @notice Converts ERC20 tokens into ERC1155 tokens.
     * Transfers ERC20 tokens from the user, burns them, and then mints ERC1155 tokens on the specified contract.
     * @param erc1155Contract The address of the ERC1155 contract on which to mint tokens.
     * @param tokenId The ERC1155 token id to mint.
     * @param amount The amount of ERC20 tokens to convert (and thus ERC1155 tokens to mint).
     */
    function convertToERC1155(address erc1155Contract, uint256 tokenId, uint256 amount) external {
        require(allowedERC1155Reverse[erc1155Contract][tokenId], "Conversion not allowed for this ERC1155 token");
        require(amount > 0, "Amount must be greater than zero");
        require(address(erc20Token) != address(0), "ERC20 token not set");

        // Transfer ERC20 tokens from the user to this contract.
        bool success = erc20Token.transferFrom(msg.sender, address(this), amount);
        require(success, "ERC20 transfer failed");

        // Burn the ERC20 tokens.
        erc20Token.burn(amount);

        // Mint the ERC1155 tokens to the user.
        IERC1155Minter(erc1155Contract).mint(msg.sender, tokenId, amount, "");

        // Save history of the conversion.
        ConversionRecordERC20ToERC1155 memory record = ConversionRecordERC20ToERC1155({
            user: msg.sender,
            erc1155Contract: erc1155Contract,
            tokenId: tokenId,
            amount: amount,
            timestamp: block.timestamp
        });
        erc20ToErc1155History.push(record);
        conversionRecordsERC20ToERC1155ByUser[msg.sender].push(record);    

        emit ERC20ToERC1155Conversion(msg.sender, erc1155Contract, tokenId, amount, block.timestamp);
    }
}
