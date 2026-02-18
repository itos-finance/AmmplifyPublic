import Table from "cli-table3";

export function createTable(head: string[], colWidths?: number[]): Table.Table {
  return new Table({
    head,
    ...(colWidths ? { colWidths } : {}),
    style: { head: ["cyan"], border: ["gray"] },
  });
}

export function printTable(table: Table.Table): void {
  console.log(table.toString());
}

export function printJson(data: unknown): void {
  console.log(JSON.stringify(data, null, 2));
}
