export const ITakerAbi = [
  {
    "type": "function",
    "name": "collateralize",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "data",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "newTaker",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "poolAddr",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "ticks",
        "type": "int24[2]",
        "internalType": "int24[2]"
      },
      {
        "name": "liq",
        "type": "uint128",
        "internalType": "uint128"
      },
      {
        "name": "vaultIndices",
        "type": "uint8[2]",
        "internalType": "uint8[2]"
      },
      {
        "name": "sqrtPriceLimitsX96",
        "type": "uint160[2]",
        "internalType": "uint160[2]"
      },
      {
        "name": "freezeSqrtPriceX96",
        "type": "uint160",
        "internalType": "uint160"
      },
      {
        "name": "rftData",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "_assetId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "removeTaker",
    "inputs": [
      {
        "name": "assetId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "minSqrtPriceX96",
        "type": "uint160",
        "internalType": "uint160"
      },
      {
        "name": "maxSqrtPriceX96",
        "type": "uint160",
        "internalType": "uint160"
      },
      {
        "name": "rftData",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [
      {
        "name": "token0",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "token1",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "balance0",
        "type": "int256",
        "internalType": "int256"
      },
      {
        "name": "balance1",
        "type": "int256",
        "internalType": "int256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "withdrawCollateral",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "data",
        "type": "bytes",
        "internalType": "bytes"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "CollateralAdded",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "token",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CollateralWithdrawn",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "token",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TakerCreated",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "poolAddr",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "assetId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "lowTick",
        "type": "int24",
        "indexed": false,
        "internalType": "int24"
      },
      {
        "name": "highTick",
        "type": "int24",
        "indexed": false,
        "internalType": "int24"
      },
      {
        "name": "liq",
        "type": "uint128",
        "indexed": false,
        "internalType": "uint128"
      },
      {
        "name": "xVaultIndex",
        "type": "uint8",
        "indexed": false,
        "internalType": "uint8"
      },
      {
        "name": "yVaultIndex",
        "type": "uint8",
        "indexed": false,
        "internalType": "uint8"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TakerRemoved",
    "inputs": [
      {
        "name": "owner",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "assetId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "poolAddr",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "balance0",
        "type": "int256",
        "indexed": false,
        "internalType": "int256"
      },
      {
        "name": "balance1",
        "type": "int256",
        "indexed": false,
        "internalType": "int256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "DeMinimusTaker",
    "inputs": [
      {
        "name": "liq",
        "type": "uint128",
        "internalType": "uint128"
      }
    ]
  },
  {
    "type": "error",
    "name": "NotTaker",
    "inputs": [
      {
        "name": "assetId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "NotTakerOwner",
    "inputs": [
      {
        "name": "owner",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "sender",
        "type": "address",
        "internalType": "address"
      }
    ]
  }
] as const;
