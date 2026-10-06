# Browser MCP App

An MCP App that drives a real Chromium browser with Playwright and renders a live,
clickable view of the page inside an MCP host such as [Archestra]. The agent can browse
for you, and you can take over in the panel — click, type, scroll, navigate.

## How it works

Browser tools (`browser_navigate`, `browser_click`, `browser_type`, `browser_press`,
`browser_scroll`, `browser_back`/`forward`/`reload`, `browser_read_page`) drive one
shared Playwright page. The UI panel polls an app-only `browser_screenshot` tool (~1/s),
maps your clicks back to viewport pixels, and forwards your keystrokes — so the model
and you drive the same page.

## Setup

```bash
npm install
npm run browsers   # one-time: download Chromium
npm run build      # bundle the UI into dist/mcp-app.html
```

## Run

```bash
npm run serve         # HTTP transport on :3001  (npm run dev = watch mode)
npm run serve:stdio   # stdio transport
```

To use it from an MCP host (e.g. Archestra), build first and point the host's MCP config
at the stdio entry:

```json
{
  "mcpServers": {
    "browser": {
      "command": "npx",
      "args": ["-y", "tsx", "/absolute/path/to/browser-mcp-app/main.ts", "--stdio"]
    }
  }
}
```

## Configuration

| Env var | Default | Meaning |
| --- | --- | --- |
| `HEADLESS` | unset → headed | `1`/`true` runs Chromium headless. |
| `PORT` | `3001` | HTTP port. |
| `SCREENSHOT_QUALITY` | `60` | JPEG quality for the live view. |
| `BASE_PATH` | unset | Path prefix for the HTTP endpoint, e.g. `/browser-mcp-app` → `/browser-mcp-app/mcp`. |
| `MCP_AUTH_TOKEN` | unset → no auth | When set, `/mcp` requires `Authorization: Bearer <token>`. |
| `ALLOWED_DOMAINS` | unset → any site | Comma-separated sites the browser may open, e.g. `kitabisa.com,*.kitabisa.com`. |

### Domain allowlist

With `ALLOWED_DOMAINS` set, the browser only opens pages on those hosts. `kitabisa.com`
matches exactly that host; `*.kitabisa.com` matches any subdomain but not the apex, so
list both. The rule covers every top-level navigation — `browser_navigate`, link
clicks, form posts, redirects and popups — and non-web URLs such as `file://`. What an
allowed page embeds (images, scripts, API calls, iframes) still loads from anywhere.

## Deploy to Kubernetes

The image runs the compiled server (`node dist/main.js`) with headless Chromium, as
uid 1000, on port 8080. Deployment follows the usual kitabisa layout:

| Path | Purpose |
| --- | --- |
| `.github/workflows/build-push-deploy-prod.yml` | On push to `main`: `make package`, then `make deploy`. |
| `Makefile` | `package` builds and pushes the image; `deploy` runs `helmfile apply`. |
| `.infra/helm/helmfile.yaml` | Two releases in the `browser-mcp-app` namespace: `config` and `server`. |
| `.infra/helm/prod/config.yaml` | Environment for the pod, including `ALLOWED_DOMAINS`. |
| `.infra/helm/prod/server.yaml` | Values for the [`app` chart][charts]: probes, resources, scaling, egress policy. |
| `.infra/helm/volume.yaml` | Config wiring and the `/tmp` and `/dev/shm` volumes. |

The server is served on the private gateway at
`https://gate.prod.kt.bs/browser-mcp-app/mcp`.

To change the allowed sites, edit `ALLOWED_DOMAINS` in `.infra/helm/prod/config.yaml`
and merge; the pod restarts with the new list.

To require a bearer token, create `.infra/helm/prod/secret.yaml`, encrypt it with
`sops`, and uncomment the two `secrets` blocks in `helmfile.yaml` and `volume.yaml`:

```yaml
secret:
  enabled: true
  data:
    MCP_AUTH_TOKEN: <openssl rand -hex 32>
```

Things the values set on purpose:

- **Exactly one pod.** The browser is a single in-process page, so autoscaling is off
  and a rollout stops the old pod before starting the new one. A restart resets the
  browser (open page, cookies, logins).
- **Egress limited to DNS + public internet** by a NetworkPolicy, as a backstop to the
  allowlist: the pod cannot reach in-cluster services, VPC addresses or the cloud
  metadata endpoint. This only takes effect on clusters that enforce NetworkPolicy.
- **Writable `/tmp` and a memory-backed `/dev/shm`**, since the root filesystem is
  read-only and Chromium needs both.

## Development

Built with the **`create-mcp-app`** Agent Skill, which covers the MCP Apps SDK patterns
used here (tool + UI-resource registration, app lifecycle, host context, polling). Use
it when extending the server — invoke `/create-mcp-app`.

## Notes

- One shared browser page; actions are serialized so calls don't race.
- The live view is a screenshot stream — page pixels never go to the model; only
  `browser_read_page` returns text, on request.
- It's a real browser: it can log in and submit forms. Don't point it at sites where an
  unintended click would be costly.

[Archestra]: https://archestra.ai
[charts]: https://github.com/kitabisa/charts
[Playwright]: https://playwright.dev
