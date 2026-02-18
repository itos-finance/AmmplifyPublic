export const IViewAbi = [
  {
    "type": "function",
    "name": "getAssetInfo",
    "inputs": [
      {
        "name": "assetId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "owner",
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
        "name": "liqType",
        "type": "uint8",
        "internalType": "enum LiqType"
      },
      {
        "name": "liq",
        "type": "uint128",
        "internalType": "uint128"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getNodes",
    "inputs": [
      {
        "name": "poolAddr",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "keys",
        "type": "uint48[]",
        "internalType": "Key[]"
      }
    ],
    "outputs": [
      {
        "name": "node",
        "type": "tuple[]",
        "internalType": "struct Node[]",
        "components": [
          {
            "name": "liq",
            "type": "tuple",
            "internalType": "struct LiqNode",
            "components": [
              {
                "name": "mLiq",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "tLiq",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "ncLiq",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "shares",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "subtreeMLiq",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "subtreeTLiq",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "borrowedX",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "borrowedY",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "subtreeBorrowedX",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "subtreeBorrowedY",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "xTLiq",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "dirty",
                "type": "uint8",
                "internalType": "uint8"
              },
              {
                "name": "initialized",
                "type": "bool",
                "internalType": "bool"
              },
              {
                "name": "feeGrowthInside0X128",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "feeGrowthInside1X128",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "borrowed",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "lent",
                "type": "uint128",
                "internalType": "uint128"
              }
            ]
          },
          {
            "name": "fees",
            "type": "tuple",
            "internalType": "struct FeeNode",
            "components": [
              {
                "name": "takerXFeesPerLiqX128",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "takerYFeesPerLiqX128",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "xTakerFeesPerLiqX128",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "yTakerFeesPerLiqX128",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "makerXFeesPerLiqX128",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "makerYFeesPerLiqX128",
                "type": "uint256",
                "internalType": "uint256"
              },
              {
                "name": "xCFees",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "yCFees",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "unclaimedMakerXFees",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "unclaimedMakerYFees",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "unpaidTakerXFees",
                "type": "uint128",
                "internalType": "uint128"
              },
              {
                "name": "unpaidTakerYFees",
                "type": "uint128",
                "internalType": "uint128"
              }
            ]
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getPoolInfo",
    "inputs": [
      {
        "name": "poolAddr",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "pInfo",
        "type": "tuple",
        "internalType": "struct PoolInfo",
        "components": [
          {
            "name": "poolAddr",
            "type": "address",
            "internalType": "address"
          },
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
            "name": "tickSpacing",
            "type": "int24",
            "internalType": "int24"
          },
          {
            "name": "fee",
            "type": "uint24",
            "internalType": "uint24"
          },
          {
            "name": "treeWidth",
            "type": "uint24",
            "internalType": "uint24"
          },
          {
            "name": "sqrtPriceX96",
            "type": "uint160",
            "internalType": "uint160"
          },
          {
            "name": "currentTick",
            "type": "int24",
            "internalType": "int24"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "queryAssetBalances",
    "inputs": [
      {
        "name": "assetId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "netBalance0",
        "type": "int256",
        "internalType": "int256"
      },
      {
        "name": "netBalance1",
        "type": "int256",
        "internalType": "int256"
      },
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
    "stateMutability": "view"
  },
  {
    "type": "error",
    "name": "LengthMismatch",
    "inputs": [
      {
        "name": "baseLength",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "widthLength",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  }
] as const;
