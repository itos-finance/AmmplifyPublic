export const IAdminAbi = [
  {
    "type": "function",
    "name": "addVault",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "vaultIdx",
        "type": "uint8",
        "internalType": "uint8"
      },
      {
        "name": "vault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "vType",
        "type": "uint8",
        "internalType": "enum VaultType"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getDefaultFeeConfig",
    "inputs": [],
    "outputs": [
      {
        "name": "feeCurve",
        "type": "tuple",
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      },
      {
        "name": "splitCurve",
        "type": "tuple",
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      },
      {
        "name": "compoundThreshold",
        "type": "uint128",
        "internalType": "uint128"
      },
      {
        "name": "jitLifetime",
        "type": "uint64",
        "internalType": "uint64"
      },
      {
        "name": "jitPenaltyX64",
        "type": "uint64",
        "internalType": "uint64"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getFeeConfig",
    "inputs": [
      {
        "name": "pool",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "feeCurve",
        "type": "tuple",
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      },
      {
        "name": "splitCurve",
        "type": "tuple",
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      },
      {
        "name": "compoundThreshold",
        "type": "uint128",
        "internalType": "uint128"
      },
      {
        "name": "twapInterval",
        "type": "uint32",
        "internalType": "uint32"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "removeVault",
    "inputs": [
      {
        "name": "vault",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setCompoundThreshold",
    "inputs": [
      {
        "name": "pool",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "threshold",
        "type": "uint128",
        "internalType": "uint128"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setDefaultCompoundThreshold",
    "inputs": [
      {
        "name": "threshold",
        "type": "uint128",
        "internalType": "uint128"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setDefaultFeeCurve",
    "inputs": [
      {
        "name": "feeCurve",
        "type": "tuple",
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setDefaultSplitCurve",
    "inputs": [
      {
        "name": "splitCurve",
        "type": "tuple",
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setFeeCurve",
    "inputs": [
      {
        "name": "pool",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "feeCurve",
        "type": "tuple",
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setJITPenalties",
    "inputs": [
      {
        "name": "lifetime",
        "type": "uint64",
        "internalType": "uint64"
      },
      {
        "name": "penaltyX64",
        "type": "uint64",
        "internalType": "uint64"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setSplitCurve",
    "inputs": [
      {
        "name": "pool",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "splitCurve",
        "type": "tuple",
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "swapVault",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "vaultId",
        "type": "uint8",
        "internalType": "uint8"
      }
    ],
    "outputs": [
      {
        "name": "oldVault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "newVault",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "transferVaultBalance",
    "inputs": [
      {
        "name": "fromVault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "toVault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "viewVaults",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "vaultIdx",
        "type": "uint8",
        "internalType": "uint8"
      }
    ],
    "outputs": [
      {
        "name": "vault",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "backup",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "CompoundThresholdSet",
    "inputs": [
      {
        "name": "pool",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "threshold",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "DefaultCompoundThresholdSet",
    "inputs": [
      {
        "name": "threshold",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "DefaultFeeCurveSet",
    "inputs": [
      {
        "name": "feeCurve",
        "type": "tuple",
        "indexed": false,
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "DefaultSplitCurveSet",
    "inputs": [
      {
        "name": "splitCurve",
        "type": "tuple",
        "indexed": false,
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "FeeCurveSet",
    "inputs": [
      {
        "name": "pool",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "feeCurve",
        "type": "tuple",
        "indexed": false,
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "JITPenaltySet",
    "inputs": [
      {
        "name": "lifetime",
        "type": "uint64",
        "indexed": false,
        "internalType": "uint64"
      },
      {
        "name": "penaltyX64",
        "type": "uint64",
        "indexed": false,
        "internalType": "uint64"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "SplitCurveSet",
    "inputs": [
      {
        "name": "pool",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "splitCurve",
        "type": "tuple",
        "indexed": false,
        "internalType": "struct SmoothRateCurveConfig",
        "components": [
          {
            "name": "invAlphaX128",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "betaX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxUtilX64",
            "type": "uint128",
            "internalType": "uint128"
          },
          {
            "name": "maxRateX64",
            "type": "uint128",
            "internalType": "uint128"
          }
        ]
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "VaultAdded",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "vaultIdx",
        "type": "uint8",
        "indexed": true,
        "internalType": "uint8"
      },
      {
        "name": "vault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "vType",
        "type": "uint8",
        "indexed": false,
        "internalType": "enum VaultType"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "VaultBalanceTransferred",
    "inputs": [
      {
        "name": "fromVault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "toVault",
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
    "name": "VaultRemoved",
    "inputs": [
      {
        "name": "vault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "VaultSwapped",
    "inputs": [
      {
        "name": "token",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "vaultId",
        "type": "uint8",
        "indexed": true,
        "internalType": "uint8"
      },
      {
        "name": "oldVault",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "newVault",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  }
] as const;
