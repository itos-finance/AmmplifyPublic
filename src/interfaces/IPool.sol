// SPDX-License-Identifier: BUSL-1.1-or-later
pragma solidity ^0.8.26;

import { IUnlockCallback } from "v4-core/interfaces/callback/IUnlockCallback.sol";

interface IPool is IUnlockCallback {
    // Errors
    error UnauthorizedUnlock(address expected, address actual);
}
