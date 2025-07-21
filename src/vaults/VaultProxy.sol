// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { VaultPointer } from "./VaultPointer.sol";

// An in-memory struct used by vertices to interact with vaults.
struct VaultProxy {
    VaultPointer active;
    VaultPointer backup;
}

using VaultProxyImpl for VaultProxy global;

library VaultProxyImpl {
    error VaultTypeUnrecognized(VaultType);
    error WithdrawLimited(ClosureId cid, uint256 requested, uint256 available);

    /// We simply deposit into the active vault pointer.
    function deposit(VaultProxy memory self, ClosureId cid, uint256 amount) internal {
        self.active.deposit(cid, amount);
    }

    /// Withdraw from the active vault, and then the backup if we can't fulfill it entirely.
    function withdraw(VaultProxy memory self, ClosureId cid, uint256 amount) internal {
        // We effectively don't allow withdraws beyond uint128 due to the capping in balance.
        uint128 available = self.active.balance(cid, false);
        uint256 maxWithdrawable = self.active.withdrawable();
        if (maxWithdrawable < available) available = uint128(maxWithdrawable);

        if (amount > available) {
            self.active.withdraw(cid, available);
            uint256 residual = amount - available;
            uint256 backWithdrawable = self.backup.withdrawable();
            if (backWithdrawable < residual) {
                revert WithdrawLimited(cid, amount, backWithdrawable + available);
            }
            self.backup.withdraw(cid, residual);
        } else {
            self.active.withdraw(cid, amount);
        }
    }

    /// We withdraw from the active vault regardless of what's available.
    /// If it is blocked it's okay because the expectation is that you're deposting back before
    /// the next vault commit so no funds are actually withdrawn.
    /// @return potent If the withdraw can actually be done or not.
    function nilpotentWithdraw(VaultProxy memory self, ClosureId cid, uint256 amount) internal returns (bool potent) {
        uint128 available = self.active.balance(cid, false);
        uint256 maxWithdrawable = self.active.withdrawable();
        if (maxWithdrawable < available) available = uint128(maxWithdrawable);

        potent = amount <= available;
        // This will succeed for now, but fail on commit if the funds are not returned and withdraws are limited.
        self.active.withdraw(cid, amount);
    }

    /// How much can we withdraw from the vaults right now?
    function withdrawable(VaultProxy memory self) internal view returns (uint256 _withdrawable) {
        return self.active.withdrawable() + self.backup.withdrawable();
    }

    /// Query the balance available to the given cid.
    function balance(VaultProxy memory self, ClosureId cid, bool roundUp) internal view returns (uint128 amount) {
        return self.active.balance(cid, roundUp) + self.backup.balance(cid, roundUp);
    }

    /// Query the total balance of all the given cids.
    function totalBalance(
        VaultProxy memory self,
        ClosureId[] storage cids,
        bool roundUp
    ) internal view returns (uint128 amount) {
        return self.active.totalBalance(cids, roundUp) + self.backup.totalBalance(cids, roundUp);
    }

    /// Query the total balance of everything.
    function totalBalance(VaultProxy memory self, bool roundUp) internal view returns (uint256 amount) {
        return self.active.totalBalance(roundUp) + self.backup.totalBalance(roundUp);
    }

    /// Because vaults batch operations together, they do one final operation
    /// as needed during the commit step.
    function commit(VaultProxy memory self) internal {
        self.active.commit();
        self.backup.commit();
    }

    function isValid(VaultProxy memory self) internal view returns (bool) {
        return self.active.isValid() && self.backup.isValid();
    }

    /// A convenience function that forces a commit and re-fetches from the underlying vault.
    function refresh(VaultProxy memory self) internal {
        self.active.refresh();
        self.backup.refresh();
    }
}
