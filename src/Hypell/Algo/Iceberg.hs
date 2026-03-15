module Hypell.Algo.Iceberg
  ( computeIcebergOrder
  ) where

import Data.Scientific (Scientific)
import Hypell.Types

-- | Compute next visible order for iceberg execution.
-- Caps the visible size at the remaining quantity to fill.
computeIcebergOrder :: IcebergParams -> Scientific -> OrderRequest
computeIcebergOrder params filledSoFar =
  let remaining = iceTotalSize params - filledSoFar
      sz = min (iceShowSize params) remaining
  in OrderRequest
    { orCoin      = iceCoin params
    , orSide      = iceSide params
    , orSize      = sz
    , orOrderType = Limit (iceLimitPrice params) GTC
    , orClientId  = Nothing
    }
