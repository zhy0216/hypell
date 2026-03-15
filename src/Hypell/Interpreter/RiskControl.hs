module Hypell.Interpreter.RiskControl
  ( runRiskControlPure
  , runRiskControlIO
  ) where

import Control.Concurrent.STM
import Data.Map.Strict qualified as Map
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Effect.RiskControl
import Hypell.Risk (evaluateRisk)

runRiskControlPure
  :: (State RiskLimits :> es, State DailyStats :> es, State (Map.Map Coin TokenBalance) :> es)
  => Eff (RiskControl : es) a -> Eff es a
runRiskControlPure = interpret_ $ \case
  CheckOrder req -> do
    limits    <- get
    stats     <- get
    positions <- get
    pure $ evaluateRisk limits stats positions req
  GetRiskLimits -> get
  UpdateRiskLimits newLimits -> put newLimits

-- | IO interpreter for RiskControl, backed by TVars.
runRiskControlIO
  :: (IOE :> es)
  => TVar RiskLimits -> TVar DailyStats -> TVar (Map.Map Coin TokenBalance)
  -> Eff (RiskControl : es) a -> Eff es a
runRiskControlIO limitsVar statsVar posVar = interpret_ $ \case
  CheckOrder req -> liftIO $ atomically $ do
    limits    <- readTVar limitsVar
    stats     <- readTVar statsVar
    positions <- readTVar posVar
    pure $ evaluateRisk limits stats positions req
  GetRiskLimits ->
    liftIO $ atomically $ readTVar limitsVar
  UpdateRiskLimits newLimits ->
    liftIO $ atomically $ writeTVar limitsVar newLimits
