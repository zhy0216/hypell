module Hypell.Effect.RiskControl
  ( RiskControl(..)
  , checkOrder
  , getRiskLimits
  , updateRiskLimits
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data RiskControl :: Effect where
  CheckOrder       :: OrderRequest -> RiskControl m RiskResult
  GetRiskLimits    :: RiskControl m RiskLimits
  UpdateRiskLimits :: RiskLimits -> RiskControl m ()

makeEffect ''RiskControl
