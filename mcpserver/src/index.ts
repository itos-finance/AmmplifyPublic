import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import express from "express";
import { randomUUID } from "node:crypto";
import { getConfig } from "./config.js";
import { registerReadTools } from "./tools/read.js";
import { registerWriteTools } from "./tools/write.js";
import { registerResources } from "./resources/protocol.js";
import { registerPrompts } from "./prompts/workflows.js";

// Map of session transports for multi-client support
const transports = new Map<string, StreamableHTTPServerTransport>();

function createServer(): McpServer {
  const server = new McpServer({
    name: "ammplify-mcp-server",
    version: "0.1.0",
  });

  registerReadTools(server);
  registerWriteTools(server);
  registerResources(server);
  registerPrompts(server);

  return server;
}

const app = express();
app.use(express.json());

app.post("/mcp", async (req, res) => {
  const sessionId = req.headers["mcp-session-id"] as string | undefined;

  if (sessionId && transports.has(sessionId)) {
    const transport = transports.get(sessionId)!;
    await transport.handleRequest(req, res, req.body);
    return;
  }

  // New session
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: () => randomUUID(),
    onsessioninitialized: (id) => {
      transports.set(id, transport);
    },
  });

  transport.onclose = () => {
    if (transport.sessionId) {
      transports.delete(transport.sessionId);
    }
  };

  const server = createServer();
  await server.connect(transport);
  await transport.handleRequest(req, res, req.body);
});

app.get("/mcp", async (req, res) => {
  const sessionId = req.headers["mcp-session-id"] as string | undefined;
  if (!sessionId || !transports.has(sessionId)) {
    res.status(400).json({ error: "Invalid or missing session ID" });
    return;
  }
  const transport = transports.get(sessionId)!;
  await transport.handleRequest(req, res);
});

app.delete("/mcp", async (req, res) => {
  const sessionId = req.headers["mcp-session-id"] as string | undefined;
  if (sessionId && transports.has(sessionId)) {
    const transport = transports.get(sessionId)!;
    await transport.handleRequest(req, res);
    transports.delete(sessionId);
  } else {
    res.status(400).json({ error: "Invalid or missing session ID" });
  }
});

const config = getConfig();
app.listen(config.port, () => {
  console.log(`Ammplify MCP server running at http://localhost:${config.port}/mcp`);
  console.log(`Network: ${config.network} (chain ${config.chainId})`);
  console.log(`RPC: ${config.rpcUrl}`);
});
