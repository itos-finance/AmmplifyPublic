// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/INonfungibleTokenPositionDescriptor.sol";
import "./interfaces/INonfungiblePositionManager.sol";

/// @title Mock implementation of NonfungibleTokenPositionDescriptor
contract NonfungibleTokenPositionDescriptor is INonfungibleTokenPositionDescriptor {
    address public immutable WETH9;
    bytes32 public immutable nativeCurrencyLabelBytes;

    constructor(address _WETH9, bytes32 _nativeCurrencyLabelBytes) {
        WETH9 = _WETH9;
        nativeCurrencyLabelBytes = _nativeCurrencyLabelBytes;
    }

    /// @inheritdoc INonfungibleTokenPositionDescriptor
    function tokenURI(
        INonfungiblePositionManager positionManager,
        uint256 tokenId
    ) external view override returns (string memory) {
        // Simple mock implementation that returns a basic JSON metadata
        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                _base64Encode(
                    bytes(
                        string(
                            abi.encodePacked(
                                '{"name":"Uniswap V3 Position #',
                                _toString(tokenId),
                                '","description":"Mock Uniswap V3 position NFT","image":"data:image/svg+xml;base64,',
                                _base64Encode(bytes(_generateSVG(tokenId))),
                                '"}'
                            )
                        )
                    )
                )
            )
        );
    }

    function _generateSVG(uint256 tokenId) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="290" height="500" viewBox="0 0 290 500">',
                '<rect width="290" height="500" fill="#1f2937"/>',
                '<text x="145" y="250" text-anchor="middle" fill="white" font-family="Arial" font-size="16">',
                'Uniswap V3 Position #',
                _toString(tokenId),
                '</text>',
                '</svg>'
            )
        );
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _base64Encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return '';

        string memory table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        string memory result = new string(4 * ((data.length + 2) / 3));
        
        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            
            for {
                let dataPtr := data
                let endPtr := add(dataPtr, mload(data))
            } lt(dataPtr, endPtr) {
            
            } {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                
                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }
            
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 2), 0x3d)
                mstore8(sub(resultPtr, 1), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }
        
        return result;
    }
}
