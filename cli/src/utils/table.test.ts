import { describe, it, expect, vi } from "vitest";
import { createTable, printJson } from "./table.js";

describe("createTable", () => {
  it("returns a table instance with correct headers", () => {
    const table = createTable(["Name", "Value"]);
    // cli-table3 Table objects have an options property
    expect(table.options.head).toEqual(["Name", "Value"]);
  });

  it("accepts optional column widths", () => {
    const table = createTable(["Name", "Value"], [20, 40]);
    expect(table.options.colWidths).toEqual([20, 40]);
  });

  it("renders to a non-empty string", () => {
    const table = createTable(["Col1", "Col2"]);
    table.push(["a", "b"]);
    const output = table.toString();
    expect(output).toContain("Col1");
    expect(output).toContain("Col2");
    expect(output).toContain("a");
    expect(output).toContain("b");
  });
});

describe("printJson", () => {
  it("outputs valid JSON to stdout", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const data = { foo: "bar", count: 42 };
    printJson(data);
    expect(spy).toHaveBeenCalledWith(JSON.stringify(data, null, 2));
    spy.mockRestore();
  });

  it("handles arrays", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    const data = [1, 2, 3];
    printJson(data);
    expect(spy).toHaveBeenCalledWith(JSON.stringify(data, null, 2));
    spy.mockRestore();
  });
});
