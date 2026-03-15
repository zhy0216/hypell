module Main (main) where

import Test.Tasty

import qualified Test.Hypell.TypesTest
import qualified Test.Hypell.RiskTest
import qualified Test.Hypell.StrategyTest
import qualified Test.Hypell.AlgoTest

main :: IO ()
main = defaultMain $ testGroup "hypell"
  [ Test.Hypell.TypesTest.tests
  , Test.Hypell.RiskTest.tests
  , Test.Hypell.StrategyTest.tests
  , Test.Hypell.AlgoTest.tests
  ]
