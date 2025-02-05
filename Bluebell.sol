// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts@5.2.0/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts@5.2.0/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts@5.2.0/token/ERC20/extensions/ERC20Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts@5.2.0/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts@5.2.0/access/Ownable.sol";

contract Bluebell is ERC20, ERC20Burnable, ERC20Pausable, Ownable, ERC20Permit {
    // Authorized contract address allowed to mint tokens.
    address public minter;

    /// @notice Emitted when the minter is updated.
    /// @param previousMinter The previous minter address.
    /// @param newMinter The new minter address.
    event MinterUpdated(address indexed previousMinter, address indexed newMinter);

    /**
     * @notice Modifier to ensure the provided address is a valid contract.
     * @param _addr The address to verify.
     */
    modifier onlyValidContract(address _addr) {
        require(_addr != address(0) && _addr.code.length > 0, "Address must be a valid contract address");
        _;
    }

    /**
     * @notice Contract constructor.
     * @param initialOwner The address that will own the contract.
     * @param name The name of the token.
     * @param symbol The token symbol.
     * @param initialMinter The contract address authorized to mint tokens.
     */
    constructor(
        address initialOwner,
        string memory name,
        string memory symbol,
        address initialMinter
    )
        ERC20(name, symbol)
        Ownable(initialOwner)
        ERC20Permit(name)
        onlyValidContract(initialMinter) // Using the modifier in the constructor
    {
        minter = initialMinter;
    }

    /**
     * @notice Overrides the decimals function to always return 0.
     * @return uint8 Always returns 0.
     */
    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    /**
     * @notice Allows the owner to change the authorized minting contract address.
     * @param newMinter The new contract address authorized to mint tokens.
     */
    function setMinter(address newMinter) external onlyOwner onlyValidContract(newMinter) {
        address previousMinter = minter;
        minter = newMinter;
        emit MinterUpdated(previousMinter, newMinter);
    }

    /**
     * @notice Mint tokens. This function can only be called by the authorized minter contract.
     * @param to The address to receive the minted tokens.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) public {
        require(msg.sender == minter, "Only the authorized minter contract can mint tokens");
        _mint(to, amount);
    }

    /**
     * @notice Pause all token transfers.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause token transfers.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    // The following function overrides are required by Solidity for multiple inheritance.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
