import chalk from "chalk";

export function handleError(err: unknown): never {
  if (err instanceof Error) {
    // Contract revert errors
    if (err.message.includes("revert")) {
      console.error(chalk.red("Contract Error:"), err.message);
    }
    // User cancelled
    else if (err.message.includes("cancelled")) {
      console.error(chalk.yellow(err.message));
    }
    // Config errors
    else if (
      err.message.includes("required") ||
      err.message.includes("AMMPLIFY_")
    ) {
      console.error(chalk.red("Config Error:"), err.message);
    }
    // Generic
    else {
      console.error(chalk.red("Error:"), err.message);
    }
  } else {
    console.error(chalk.red("Error:"), String(err));
  }
  process.exit(1);
}

/**
 * Wrap an async command handler with error handling.
 */
export function withErrorHandler(
  fn: (...args: any[]) => Promise<void>
): (...args: any[]) => Promise<void> {
  return async (...args: any[]) => {
    try {
      await fn(...args);
    } catch (err) {
      handleError(err);
    }
  };
}
