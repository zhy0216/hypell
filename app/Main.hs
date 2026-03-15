module Main where

import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  let configPath = case args of
        (p:_) -> p
        []    -> "config/example.yaml"
  putStrLn $ "Loading config from: " <> configPath
  putStrLn "hypell: use examples/SimpleGrid.hs for now"
