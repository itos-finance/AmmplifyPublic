export const IMakerAbi = [
  {
    "type": "function",
    "name": "addPermission",
    "inputs": [
      {
        "name": "opener",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "adjustMaker",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "assetId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "targetLiq",
        "type": "uint128",
        "internalType": "uint128"
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
        "name": "delta0",
        "type": "int256",
        "internalType": "int256"
      },
      {
        "name": "delta1",
        "type": "int256",
        "internalType": "int256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "collectFees",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "internalType": "address"
      },
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
        "name": "fees0",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "fees1",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "newMaker",
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
        "name": "lowTick",
        "type": "int24",
        "internalType": "int24"
      },
      {
        "name": "highTick",
        "type": "int24",
        "internalType": "int24"
      },
      {
        "name": "liq",
        "type": "uint128",
        "internalType": "uint128"
      },
      {
        "name": "isCompounding",
        "type": "bool",
        "internalType": "bool"
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
        "name": "_assetId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "removeMaker",
    "inputs": [
      {
        "name": "recipient",
        "type": "address",
        "internalType": "address"
      },
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
        "name": "removedX",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "removedY",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "removePermission",
    "inputs": [
      {
        "name": "opener",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "FeesCollected",
    "inputs": [
      {
        "name": "recipient",
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
        "name": "fees0",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "fees1",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "MakerAdjusted",
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
        "name": "targetLiq",
        "type": "uint128",
        "indexed": false,
        "internalType": "uint128"
      },
      {
        "name": "delta0",
        "type": "int256",
        "indexed": false,
        "internalType": "int256"
      },
      {
        "name": "delta1",
        "type": "int256",
        "indexed": false,
        "internalType": "int256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "MakerCreated",
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
        "name": "isCompounding",
        "type": "bool",
        "indexed": false,
        "internalType": "bool"
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
    "type": "event",
    "name": "MakerRemoved",
    "inputs": [
      {
        "name": "recipient",
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
        "name": "removedX",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "removedY",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "DeMinimusMaker",
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
    "name": "NotMaker",
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
    "name": "NotMakerOwner",
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
