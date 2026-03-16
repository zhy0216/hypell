# Hypell

A Haskell trading execution framework for [Hyperliquid](https://hyperliquid.xyz) spot markets.

## Features

- **Effect system architecture** — built on [effectful](https://github.com/haskell-effectful/effectful) with swappable pure/IO interpreters
- **Algorithmic execution** — TWAP and Iceberg order algorithms
- **Risk management** — order size limits, position limits, daily volume caps
- **Pluggable strategies** — implement the `Strategy` typeclass for custom logic
- **WebSocket + REST** — real-time market data and order management
- **EIP-712 signing** — native Hyperliquid L1 transaction signing

## Quick start

```bash
# Build
cabal build all

# Run tests
cabal test

# Run the example grid strategy
export HYPELL_PRIVATE_KEY="your-private-key"
cabal run simple-grid -- --config config/example.yaml
```

## Configuration

See [`config/example.yaml`](config/example.yaml) for a full example:

```yaml
network: testnet
apiUrl: "https://api.hyperliquid-testnet.xyz"
wsUrl: "wss://api.hyperliquid-testnet.xyz/ws"
risk:
  maxOrderSize: 1000
  maxDailyVolume: 50000
  cooldownMs: 500
logging:
  level: info
```

The private key is read from the `HYPELL_PRIVATE_KEY` environment variable.

## Project structure

```
src/
  Hypell.hs                  -- Public re-export module
  Hypell/
    Types.hs                 -- Core domain types
    Config.hs                -- YAML configuration
    Engine.hs                -- Event loop and action execution
    Risk.hs                  -- Pure risk evaluation
    Strategy.hs              -- Strategy typeclass
    Algo/                    -- TWAP, Iceberg algorithms
    Api/                     -- REST, WebSocket, Signing
    Effect/                  -- Typed effects (Exchange, MarketData, etc.)
    Interpreter/             -- Pure and IO interpreters
examples/
  SimpleGrid.hs              -- Example grid trading strategy
test/                        -- Unit tests
```

## License

MIT
