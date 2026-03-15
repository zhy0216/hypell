module Hypell.Interpreter.AlgoExec
  ( runAlgoExecPure
  ) where

import Control.Concurrent.Async (async)
import Control.Concurrent.STM (newTVarIO)
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
