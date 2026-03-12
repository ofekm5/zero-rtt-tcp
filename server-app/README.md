# Server App

Standard TCP server for the 0-RTT demo. Listens for connections arriving through the ServerNIC → ClientNIC middleware chain.

The server is **completely unmodified** — it has no awareness of the 0-RTT optimization. It speaks plain TCP and sends an HTTP-like response.

## Usage

```bash
# Start with defaults (0.0.0.0:8080)
python server.py

# Custom port with verbose logging
python server.py --port 9090 --verbose

# Echo mode with artificial delay (simulates a slow server)
python server.py --echo --delay 200
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--host` | `0.0.0.0` | Bind address |
| `--port` | `8080` | Listen port |
| `--delay` | `0` | Artificial response delay in ms |
| `--response-size` | `0` | Send N-byte body (default: `"OK"`) |
| `--echo` | off | Echo client data back as response body |
| `--verbose` | off | Log each connection and byte counts |

## Response Format

```
HTTP/1.0 200 OK
Content-Length: <n>

<body>
```

Each connection is handled in a dedicated daemon thread, so the server handles concurrent clients naturally.

## Tests

```bash
pytest tests/
```
