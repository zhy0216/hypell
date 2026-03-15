module Hypell.Algo.TWAP
  ( computeSlices
  ) where

import Data.Scientific (Scientific, coefficient, base10Exponent, scientific)
import Hypell.Types

-- | Compute slice sizes for TWAP execution.
-- Uses integer division to avoid repeating decimals in Scientific.
computeSlices :: TWAPParams -> [Scientific]
computeSlices params =
  let n     = toInteger (twapNumSlices params)
      total = twapTotalSize params
      -- Convert Scientific to integer representation:
      -- total = c * 10^e where e may be negative
      c = coefficient total
      e = base10Exponent total
      -- Scale: totalScaled = c * 10^max(0,e) if e>=0, or c with e digits after decimal
      -- We want: base = floor(total / n), remainder = total - base*n
      -- Work with integers: total = c * 10^e
      -- If e >= 0: totalInt = c * 10^e, base = totalInt `div` n, remainder in units
      -- If e < 0: totalInt = c, base = c `div` n, remainder in units of 10^e
      baseInt = c `div` n
      remInt  = c - baseInt * n
      -- base and remainder as Scientific with the same exponent
      baseSci = scientific baseInt e
      remSci  = scientific remInt e
      slices  = replicate (fromInteger n - 1) baseSci ++ [baseSci + remSci]
  in slices
