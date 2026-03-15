module Hypell.Interpreter.AlgoExec
  ( runAlgoExecPure
  , runAlgoExecIO
  , twapLoop
  , icebergLoop
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel)
import Control.Concurrent.STM
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Types
import Hypell.Effect.AlgoExec

runAlgoExecPure
  :: IOE :> es
  => Eff (AlgoExec : es) a -> Eff es a
runAlgoExecPure = interpret_ $ \case
  RunTWAP params -> liftIO $ do
    statusVar <- newTVarIO (AlgoRunning 0)
    thread <- async (pure ())
    pure AlgoHandle
      { ahId     = "mock-twap"
      , ahThread = thread
      , ahParams = AlgoTWAP params
      , ahStatus = statusVar
      }
  RunIceberg params -> liftIO $ do
    statusVar <- newTVarIO (AlgoRunning 0)
    thread <- async (pure ())
    pure AlgoHandle
      { ahId     = "mock-iceberg"
      , ahThread = thread
      , ahParams = AlgoIceberg params
      , ahStatus = statusVar
      }
  CancelAlgo _ -> pure ()

-- | IO interpreter for AlgoExec that spawns real async threads.
runAlgoExecIO
  :: (IOE :> es)
  => TBQueue TradeAction
  -> Eff (AlgoExec : es) a -> Eff es a
runAlgoExecIO actionQueue = interpret_ $ \case
  RunTWAP params -> liftIO $ do
    statusVar <- newTVarIO (AlgoRunning 0)
    thread <- async $ twapLoop params statusVar actionQueue
    pure AlgoHandle
      { ahId     = "twap-" <> unCoin (twapCoin params)
      , ahThread = thread
      , ahParams = AlgoTWAP params
      , ahStatus = statusVar
      }
  RunIceberg params -> liftIO $ do
    statusVar <- newTVarIO (AlgoRunning 0)
    thread <- async $ icebergLoop params statusVar actionQueue
    pure AlgoHandle
      { ahId     = "iceberg-" <> unCoin (iceCoin params)
      , ahThread = thread
      , ahParams = AlgoIceberg params
      , ahStatus = statusVar
      }
  CancelAlgo handle -> liftIO $ do
    cancel (ahThread handle)
    atomically $ writeTVar (ahStatus handle) (AlgoStopped "cancelled" 0)

-- | TWAP execution loop: splits total size into slices and submits them
-- at regular intervals via the action queue.
twapLoop :: TWAPParams -> TVar AlgoStatus -> TBQueue TradeAction -> IO ()
twapLoop params statusVar queue = go sliceList 0
  where
    n = twapNumSlices params
    total = twapTotalSize params
    base = total / fromIntegral n
    remainder = total - base * fromIntegral n
    sliceList = replicate (n - 1) base ++ [base + remainder]
    intervalMs = twapDurationSecs params * 1000 `div` max 1 n
    go [] filled = atomically $ writeTVar statusVar (AlgoComplete filled 0)
    go (sz:rest) filled = do
      let order = OrderRequest
            { orCoin      = twapCoin params
            , orSide      = twapSide params
            , orSize      = sz
            , orOrderType = Market
            , orClientId  = Nothing
            }
      atomically $ writeTBQueue queue (PlaceOrder order)
      atomically $ writeTVar statusVar (AlgoRunning (filled + sz))
      threadDelay (intervalMs * 1000)
      go rest (filled + sz)

-- | Iceberg execution loop: places visible-sized slices of a larger order
-- until the total size is filled.
icebergLoop :: IcebergParams -> TVar AlgoStatus -> TBQueue TradeAction -> IO ()
icebergLoop params statusVar queue = go 0
  where
    go filled
      | filled >= iceTotalSize params =
          atomically $ writeTVar statusVar (AlgoComplete filled 0)
      | otherwise = do
          let remaining = iceTotalSize params - filled
              sz = min (iceShowSize params) remaining
              order = OrderRequest
                { orCoin      = iceCoin params
                , orSide      = iceSide params
                , orSize      = sz
                , orOrderType = Limit (iceLimitPrice params) GTC
                , orClientId  = Nothing
                }
          atomically $ writeTBQueue queue (PlaceOrder order)
          atomically $ writeTVar statusVar (AlgoRunning filled)
          threadDelay 5_000_000
          go (filled + sz)
