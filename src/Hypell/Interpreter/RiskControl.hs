module Hypell.Interpreter.RiskControl
  ( runRiskControlPure
  ) where

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
