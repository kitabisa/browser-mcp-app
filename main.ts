/**
 * @file Entry point. Runs the MCP server over Streamable HTTP (default) or
 * stdio (`--stdio`, for Claude Desktop). The Playwright browser is a module
 * singleton (see browser.ts), shared across the per-request HTTP servers.
 *
 *   tsx main.ts            # HTTP on :3001
 *   tsx main.ts --stdio    # stdio transport
 *   node dist/main.js      # compiled build (npm run build:server), used in the image
 */
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import cors from "cors";
import express from "express";
import { timingSafeEqual } from "node:crypto";
import { browserManager } from "./browser.js";
import { createServer } from "./server.js";

async function startHttp(): Promise<void> {
  const port = parseInt(process.env.PORT ?? "3001", 10);
  // Path prefix for when a gateway routes to us without stripping it,
  // e.g. BASE_PATH=/browser-mcp-app serves the endpoint at /browser-mcp-app/mcp.
  const basePath = (process.env.BASE_PATH ?? "").replace(/\/+$/, "");
  const authToken = process.env.MCP_AUTH_TOKEN;
  const app = express();
  app.use(cors());
  app.use(express.json({ limit: "8mb" }));

  // Optional shared-secret gate: this server hands out a real browser, so
  // anything reachable beyond localhost should set MCP_AUTH_TOKEN.
  const requireAuth: express.RequestHandler = (req, res, next) => {
    if (!authToken || req.method === "OPTIONS") return next();
    // Either static header works, whichever the MCP host can be configured to send:
    //   Authorization: Bearer <token>   or   X-API-Key: <token>
    const matches = (given: string | string[] | undefined, expected: string) => {
      const a = Buffer.from(typeof given === "string" ? given : "");
      const b = Buffer.from(expected);
      return a.length === b.length && timingSafeEqual(a, b);
    };
    if (
      matches(req.headers.authorization, `Bearer ${authToken}`) ||
      matches(req.headers["x-api-key"], authToken)
    ) {
      return next();
    }
    res.status(401).json({
      jsonrpc: "2.0",
      error: { code: -32001, message: "Unauthorized" },
      id: null,
    });
  };

  // Stateless: a fresh McpServer per request, all sharing the one browser.
  app.post(`${basePath}/mcp`, requireAuth, async (req, res) => {
    const server = createServer();
    const transport = new StreamableHTTPServerTransport({ sessionIdGenerator: undefined });
    res.on("close", () => {
      transport.close().catch(() => {});
      server.close().catch(() => {});
    });
    try {
      await server.connect(transport);
      await transport.handleRequest(req, res, req.body);
    } catch (error) {
      console.error("MCP error:", error);
      if (!res.headersSent) {
        res.status(500).json({
          jsonrpc: "2.0",
          error: { code: -32603, message: "Internal server error" },
          id: null,
        });
      }
    }
  });

  // No sessions means no server-initiated stream to GET and nothing to DELETE.
  // Saying so (405) stops clients from holding open an SSE stream that never
  // carries anything and that a gateway would cut at its request timeout.
  app.all(`${basePath}/mcp`, requireAuth, (_req, res) => {
    res.status(405).set("Allow", "POST").json({
      jsonrpc: "2.0",
      error: { code: -32000, message: "Method not allowed." },
      id: null,
    });
  });

  app.get("/health", (_req, res) => res.json({ ok: true }));

  const httpServer = app.listen(port, () => {
    console.log(
      `Playwright MCP App on http://localhost:${port}${basePath}/mcp  (headless=${browserManager.headless}, auth=${authToken ? "on" : "off"}, allowed=${browserManager.allowedDomains.join(",") || "any"})`,
    );
  });

  const shutdown = async () => {
    console.log("\nShutting down...");
    await browserManager.close();
    httpServer.close(() => process.exit(0));
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

async function startStdio(): Promise<void> {
  // IMPORTANT: never write to stdout in stdio mode — it carries JSON-RPC.
  const server = createServer();
  await server.connect(new StdioServerTransport());
  const shutdown = async () => {
    await browserManager.close();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

const run = process.argv.includes("--stdio") ? startStdio() : startHttp();
run.catch((e) => {
  console.error(e);
  process.exit(1);
});
