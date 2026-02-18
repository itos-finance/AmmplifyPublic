import { describe, it, expect, vi, beforeEach } from "vitest";
import { handleError, withErrorHandler } from "./error.js";

beforeEach(() => {
  vi.restoreAllMocks();
  vi.spyOn(console, "error").mockImplementation(() => {});
  vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
});

describe("handleError", () => {
  it("handles contract revert errors", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    handleError(new Error("execution revert: insufficient balance"));
    expect(spy).toHaveBeenCalledWith(
      expect.stringContaining("Contract Error"),
      "execution revert: insufficient balance"
    );
  });

  it("handles cancelled errors", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    handleError(new Error("Operation cancelled"));
    expect(spy).toHaveBeenCalledWith(
      expect.stringContaining("cancelled")
    );
  });

  it("handles config errors (required)", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    handleError(new Error("AMMPLIFY_RPC_URL is required"));
    expect(spy).toHaveBeenCalledWith(
      expect.stringContaining("Config Error"),
      "AMMPLIFY_RPC_URL is required"
    );
  });

  it("handles config errors (AMMPLIFY_ prefix)", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    handleError(new Error("AMMPLIFY_PRIVATE_KEY not set"));
    expect(spy).toHaveBeenCalledWith(
      expect.stringContaining("Config Error"),
      "AMMPLIFY_PRIVATE_KEY not set"
    );
  });

  it("handles generic errors", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    handleError(new Error("something went wrong"));
    expect(spy).toHaveBeenCalledWith(
      expect.stringContaining("Error"),
      "something went wrong"
    );
  });

  it("handles non-Error objects", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    handleError("string error");
    expect(spy).toHaveBeenCalledWith(
      expect.stringContaining("Error"),
      "string error"
    );
  });

  it("calls process.exit(1)", () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    handleError(new Error("any error"));
    expect(exitSpy).toHaveBeenCalledWith(1);
  });
});

describe("withErrorHandler", () => {
  it("calls the wrapped function", async () => {
    const fn = vi.fn().mockResolvedValue(undefined);
    const wrapped = withErrorHandler(fn);
    await wrapped("arg1", "arg2");
    expect(fn).toHaveBeenCalledWith("arg1", "arg2");
  });

  it("catches errors and calls process.exit", async () => {
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    const fn = vi.fn().mockRejectedValue(new Error("test failure"));
    const wrapped = withErrorHandler(fn);
    await wrapped();
    expect(exitSpy).toHaveBeenCalledWith(1);
  });
});
