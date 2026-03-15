module Hypell.Effect.AlgoExec
  ( AlgoExec(..)
  , AlgoHandle(..)
  , runTWAP
  , runIceberg
  , cancelAlgo
  ) where

import Control.Concurrent.Async (Async)
import Control.Concurrent.STM (TVar)
import Data.Text (Text)
import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data AlgoHandle = AlgoHandle
  { ahId     :: Text
  , ahThread :: Async ()
  , ahParams :: AlgoParams
  , ahStatus :: TVar AlgoStatus
  }

data AlgoExec :: Effect where
  RunTWAP    :: TWAPParams -> AlgoExec m AlgoHandle
  RunIceberg :: IcebergParams -> AlgoExec m AlgoHandle
  CancelAlgo :: AlgoHandle -> AlgoExec m ()

makeEffect ''AlgoExec
