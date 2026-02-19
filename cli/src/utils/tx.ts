import chalk from "chalk";
import ora from "ora";
import prompts from "prompts";
import { type Hash, type TransactionReceipt } from "viem";
import { getPublicClient, getWalletClient } from "../clients/chain.js";

interface TxOptions {
  address: `0x${string}`;
  abi: readonly unknown[];
  functionName: string;
  args: unknown[];
  noConfirm?: boolean;
  description?: string;
}

/**
 * Execute a write transaction with the standard flow:
 * 1. Simulate to catch reverts
 * 2. Prompt for confirmation
 * 3. Submit and wait for receipt
 */
export async function executeTx(
  options: TxOptions
): Promise<TransactionReceipt> {
  const { address, abi, functionName, args, noConfirm, description } = options;
  const publicClient = getPublicClient();
  const walletClient = getWalletClient();

  // Simulate
  const simSpinner = ora("Simulating transaction...").start();
  let request: unknown;
  try {
    const sim = await publicClient.simulateContract({
      account: walletClient.account,
      address,
      abi: abi as any,
      functionName,
      args: args as any,
    });
    request = sim.request;
    simSpinner.succeed("Simulation successful");
  } catch (err: any) {
    simSpinner.fail("Simulation failed");
    const msg = err?.shortMessage || err?.message || String(err);
    throw new Error(`Transaction would revert: ${msg}`);
  }

  // Confirm
  if (!noConfirm) {
    console.log(
      chalk.yellow(
        `\n${description || `Call ${functionName} on ${address}`}\n`
      )
    );
    const { confirmed } = await prompts({
      type: "confirm",
      name: "confirmed",
      message: "Proceed with transaction?",
      initial: true,
    });
    if (!confirmed) {
      throw new Error("Transaction cancelled by user");
    }
  }

  // Submit
  const txSpinner = ora("Submitting transaction...").start();
  let hash: Hash;
  try {
    hash = await walletClient.writeContract(request as any);
    txSpinner.text = `Waiting for confirmation... (${hash})`;
  } catch (err: any) {
    txSpinner.fail("Transaction submission failed");
    throw err;
  }

  // Wait for receipt
  try {
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    if (receipt.status === "reverted") {
      txSpinner.fail("Transaction reverted");
      throw new Error(`Transaction reverted: ${hash}`);
    }
    txSpinner.succeed(`Transaction confirmed in block ${receipt.blockNumber}`);
    console.log(chalk.gray(`  Hash: ${hash}`));
    console.log(chalk.gray(`  Gas used: ${receipt.gasUsed}`));
    return receipt;
  } catch (err: any) {
    txSpinner.fail("Failed waiting for receipt");
    throw err;
  }
}
