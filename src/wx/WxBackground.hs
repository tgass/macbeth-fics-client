module WxBackground (
  wxBackground
) where

import Api
import CommandMsg
import Move
import PGN
import WxChallenge (wxChallenge)
import WxObservedGame (createObservedGame)
import WxUtils (eventLoop)

import Control.Concurrent
import Control.Concurrent.Chan
import System.IO
import Graphics.UI.WX
import Graphics.UI.WXCore

eventId = wxID_HIGHEST + 71

wxBackground :: Handle -> String -> Chan CommandMsg -> IO ()
wxBackground h name chan = do
  vCmd <- newEmptyMVar
  vGameMoves <- newMVar []

  f <- frame [visible := False]

  evtHandlerOnMenuCommand f eventId $ takeMVar vCmd >>= \cmd -> do
    printCmdMsg cmd
    case cmd of

      Observe move -> dupChan chan >>= createObservedGame h move White

      StartGame id move -> dupChan chan >>= createObservedGame h move (playerColor name move)

      AcceptChallenge move -> dupChan chan >>= createObservedGame h move (playerColor name move)

      c@(Challenge {}) -> wxChallenge h c

      GameMove move' -> when (relation move' == MyMove || relation move' == OponentsMove) $ do
                          modifyMVar_ vGameMoves (\mx -> return $ addMove move' mx)
                          return ()

      GameResult id reason result -> do
                            moves <- takeMVar vGameMoves
                            putMVar vGameMoves []
                            PGN.saveAsPGN (reverse moves) result
                            hPutStrLn h "4 iset seekinfo 1"

      _ -> return ()


  threadId <- forkIO $ eventLoop eventId chan vCmd f
  windowOnDestroy f $ killThread threadId


{- Add new moves in the front, so you can check for duplicates. -}
addMove :: Move -> [Move] -> [Move]
addMove m [] = [m]
addMove m moves@(m':_)
           | areEqual m m' = moves
           | otherwise = [m] ++ moves


areEqual :: Move -> Move -> Bool
areEqual m1 m2 = (movePretty m1 == movePretty m2) && (turn m1 == turn m2)


printCmdMsg :: CommandMsg -> IO ()
printCmdMsg Prompt = return ()
printCmdMsg cmd = print cmd
