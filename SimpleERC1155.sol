// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title SimpleERC1155
/// @notice A very simple ERC1155 contract for testing and basic usage.
contract SimpleERC1155 is ERC1155, Ownable {
    /**
     * @notice Constructor that sets the base URI for the metadata.
     * The URI should include the {id} placeholder which clients must replace with the actual token ID.
     */
    constructor() ERC1155("https://example.com/metadata/{id}.json") Ownable(msg.sender) {}

    /**
     * @notice Mints `amount` tokens of token type `id` and assigns them to `to`.
     * Can only be called by the contract owner.
     *
     * @param to The address that will receive the tokens.
     * @param id The token ID to mint.
     * @param amount The number of tokens to mint.
     * @param data Additional data with no specified format.
     */
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external onlyOwner {
        _mint(to, id, amount, data);
    }
}
