# Client App

Standard TCP client for the 0-RTT demo. Connects to the server through the ClientNIC → ServerNIC middleware chain and measures Time-to-First-Byte (TTFB).

The client is **completely unmodified** — it has no awareness of the 0-RTT optimization happening in the network layer.

## Usage

```bash
# Single connection
python client.py

# Repeated connections with statistics
python client.py --mode repeated --count 20 --verbose

# Concurrent connections
python client.py --mode concurrent --concurrency 10
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--host` | `10.0.0.4` | Server IP address |
| `--port` | `8080` | Server port |
| `--mode` | `single` | `single`, `repeated`, or `concurrent` |
| `--count` | `10` | Number of connections (repeated mode) |
| `--concurrency` | `5` | Parallel connections (concurrent mode) |
| `--message` | HTTP GET | Message to send |
| `--payload-size` | `0` | Generate N-byte payload (overrides `--message`) |
| `--delay` | `0` | Delay between connections in ms (repeated mode) |
| `--verbose` | off | Show per-connection TTFB details |

## Output

In `repeated` or `concurrent` mode, prints TTFB statistics (min/max/avg/median/stdev) across all successful connections.

## Tests

```bash
pytest tests/
```
