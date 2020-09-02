module Macbeth.Wx.Game.Board (
  draw,
  onMouseEvent
) where


import           Control.Monad.Reader
import           Control.Monad.Trans.Maybe
import           Control.Concurrent.STM
import           Data.Maybe
import           Graphics.UI.WX hiding (position, update, resize, when, pt, size, value, style, color)
import           Graphics.UI.WXCore hiding (Row, Column, when, pt)
import           Macbeth.Fics.Api.Api
import           Macbeth.Fics.Api.Move
import           Macbeth.Utils.BoardUtils
import           Macbeth.Wx.Config.BoardConfig
import           Macbeth.Wx.Game.BoardState
import           Macbeth.Wx.RuntimeEnv
import           System.IO

type BoardT a = ReaderT (DC a, BoardState) IO ()

draw :: TVar BoardState -> DC a -> t -> IO ()
draw vState dc _ = do
  state <- readTVarIO vState
  flip runReaderT (dc, state) $ do
    drawBoard
    drawHighlightLastMove
    drawHighlightPreMove
    drawPieces
    drawSelectedSquare
    drawLabels
    drawDraggedPiece

drawBoard :: BoardT a
drawBoard = do
  (dc, state) <- ask
  let squares = [Square c r  | c <- [A .. H], r <- [One .. Eight]]
  lift $ do
    set dc [ pen := penTransparent ]
    forM_ squares $ \square -> case squareColor square of
      White -> drawTile dc state (whiteTile $ boardConfig state) square
      Black -> drawTile dc state (blackTile $ boardConfig state) square
  where
    drawTile :: DC a -> BoardState -> Tile -> Square -> IO ()
    drawTile dc state (BitmapTile b) square = do
      bitmapSetSize b $ Size (squareSizePx state) (squareSizePx state)
      drawBitmap dc b (toPos' (squareSizePx state) square (perspective state)) True []
    drawTile dc state (ColorTile c) square = dcWithBrushStyle dc (brushSolid c) $ paintSquare dc state square


drawHighlightLastMove :: BoardT a
drawHighlightLastMove = do
  (dc, state) <- ask
  liftIO $ when (showHighlightMove state) $ do
    sequence_ $ paintHighlight dc state moveColor <$> pieceMove state
    when (showHighlightCheck state) $ paintHighlightCheck dc state $ kingSq (lastMove state)
  where
    showHighlightMove :: BoardState -> Bool
    showHighlightMove state = 
      let move = lastMove state 
      in (isJust $ moveVerbose move) && ((wasOponentMove move && isWaiting state) || relation move == Observing)

    showHighlightCheck :: BoardState -> Bool
    showHighlightCheck state = ((isCheck $ lastMove state) || (isCheckmate $ lastMove state)) && maybe True (not . isDraggedKing) (draggedPiece state)


drawHighlightPreMove :: BoardT a
drawHighlightPreMove = do
  (dc, state) <- ask
  liftIO $ sequence_ $ paintHighlight dc state preMoveColor <$> preMoves state


drawPieces :: BoardT a
drawPieces = do
  (dc, state) <- ask
  liftIO $ sequence_ $ drawPiece dc state <$> virtualPosition state
  where
    drawPiece :: DC a -> BoardState -> (Square, Piece) -> IO ()
    drawPiece dc state (sq, piece) = do
      let b = pieceToBitmap (runtimeEnv state) (pieceSet $ boardConfig state) piece (pieceImgSize state)
      bitmapSetSize b $ Size (squareSizePx state) (squareSizePx state)
      drawBitmap dc b (toPos' (squareSizePx state) sq (perspective state)) True []


drawSelectedSquare :: BoardT a
drawSelectedSquare = do
  (dc, state) <- ask
  let color = mouseColor $ highlightConfig $ boardConfig state
  liftIO $ when (isGameUser state && isNothing (gameResult state) && isJust color)  $
    withBrushStyle brushTransparent $ \transparent -> do
      dcSetBrush dc transparent
      set dc [pen := penColored (convertColorRGB $ fromJust color) 1]
      void $ runMaybeT $ do
        square <- MaybeT $ return $ pointToSquare state $ mousePt state
        liftIO $ paintSquare dc state square


drawDraggedPiece :: BoardT a
drawDraggedPiece = do
  (dc, state) <- ask
  case draggedPiece state of
    Just dp@(DraggedPiece pt _ source) -> liftIO $ do
      when (isSolidStyle $ highlightConfig $ boardConfig state) $ 
        mapM_ (paintHighlightSolid dc state $ if isWaiting state then moveColor else preMoveColor) $ fromMaybe [] $ sequence [pointToSquare state pt, sourceSquare source]
      drawDraggedPiece'' state dc dp
    _ -> return ()


drawDraggedPiece'' :: BoardState -> DC a -> DraggedPiece -> IO ()
drawDraggedPiece'' state dc (DraggedPiece pt piece _) = drawBitmap dc (pieceToBitmap (runtimeEnv state) (pieceSet $ boardConfig state) piece size) scalePoint True []
  where
    scale' = pieceScale state
    size = pieceImgSize state
    scalePoint = point (scaleValue $ pointX pt) (scaleValue $ pointY pt)
    scaleValue value = round $ (fromIntegral value - fromIntegral size / 2 * scale') / scale'

drawLabels :: BoardT a
drawLabels = do
  (dc, state) <- ask
  when (showLabels $ boardConfig $ state) $ liftIO $ do
    mapM_ (paintLabelsRow dc state) [One .. Eight]
    mapM_ (paintLabelsCol dc state) [A .. H]


paintHighlight :: DC a -> BoardState -> (HighlightConfig -> ColorRGB) -> PieceMove -> IO ()
paintHighlight dc state highlightType move = case style $ highlightConfig $ boardConfig state of
  Hatched -> paintHighlightHatched dc state highlightType move 
  Solid -> mapM_ (paintHighlightSolid dc state highlightType) (squares move)
    where 
      squares (PieceMove _ s1 s2) = [s1, s2]
      squares (DropMove _ s1) = [s1]

paintHighlightCheck :: DC a -> BoardState -> Square -> IO ()
paintHighlightCheck dc state square = case style $ highlightConfig $ boardConfig state of
  Hatched -> paintHighlightCheckHatched dc state square  
  Solid -> paintHighlightSolid dc state checkColor square


paintHighlightHatched :: DC a -> BoardState -> (HighlightConfig -> ColorRGB) -> PieceMove -> IO ()
paintHighlightHatched dc state highlightType (PieceMove _ s1 s2) = do
  let color = convertColorRGB $ highlightType $ highlightConfig $ boardConfig state
  set dc [pen := penColored color 1]
  withBrushStyle (BrushStyle (BrushHatch HatchBDiagonal) color) $ \brushBg -> do
    dcSetBrush dc brushBg
    mapM_ (paintSquare dc state) [s1, s2]
  withBrushStyle (BrushStyle BrushSolid color) $ \brushArrow -> do
    dcSetBrush dc brushArrow
    drawArrow dc (squareSizePx state) s1 s2 (perspective state)
paintHighlightHatched dc state highlightType (DropMove _ s1) = do
  let color = convertColorRGB $ highlightType $ highlightConfig $ boardConfig state
  set dc [pen := penColored color 1]
  withBrushStyle (BrushStyle (BrushHatch HatchBDiagonal) color) $ \brushBg -> do
    dcSetBrush dc brushBg
    paintSquare dc state s1

paintHighlightSolid :: DC a -> BoardState -> (HighlightConfig -> ColorRGB) -> Square -> IO ()
paintHighlightSolid dc state highlightType square = do
  let color = toSolidColor square $ highlightType $ highlightConfig $ boardConfig state
  set dc [ pen := penTransparent ]
  withBrushStyle (BrushStyle BrushSolid color) $ \brushHL -> do
    dcSetBrush dc brushHL
    paintSquare dc state square

paintHighlightCheckHatched :: DC a -> BoardState -> Square -> IO ()
paintHighlightCheckHatched dc state square = do
  let color = convertColorRGB $ checkColor $ highlightConfig $ boardConfig state
  set dc [pen := penColored color 1]
  withBrushStyle (BrushStyle BrushTransparent color) $ \checkBrush -> do
    dcSetBrush dc checkBrush
    mapM_ (paintCircle dc state square) [0.97 - x * 0.1 | x <- [0..5]]

paintSquare :: DC a -> BoardState -> Square -> IO ()
paintSquare dc state sq = drawRect dc (squareToRect' (squareSizePx state) sq (perspective state)) []

paintCircle :: DC a -> BoardState -> Square -> Double -> IO ()
paintCircle dc state sq scale = circle dc pt (floor $ scale * fromIntegral (squareSizePx state) / (2 :: Double)) []
  where pt = squareToPoint (squareSizePx state) sq (perspective state)

paintLabelsRow :: DC a -> BoardState -> Row -> IO ()
paintLabelsRow dc state row = 
  dcWithFontStyle dc fontSmall $ do
    let square = Square H row
        color = toSolidColorReverse square $ moveColor $ highlightConfig $ boardConfig state
        pt = toPosLabelRow (squareSizePx state) square (perspective state)
        text = show $ succ $ fromEnum row
    dcSetTextForeground dc color
    drawText dc text pt []

paintLabelsCol :: DC a -> BoardState -> Column -> IO ()
paintLabelsCol dc state col = 
  dcWithFontStyle dc fontSmall $ do
    let square = Square col One
        color = toSolidColorReverse square $ moveColor $ highlightConfig $ boardConfig state
        pt = toPosLabelCol (squareSizePx state) square (perspective state)
        text = show col
    dcSetTextForeground dc color
    drawText dc text pt []


onMouseEvent :: Handle -> Var BoardState -> EventMouse -> IO ()
onMouseEvent h vState = \case

    MouseMotion pt _ -> updateMousePosition vState pt

    MouseLeftDown pt _ -> do
      dp <- draggedPiece <$> readTVarIO vState
      case dp of
        (Just _) -> dropDraggedPiece vState h pt -- if draggedPiece is from holding
        Nothing -> pickUpPieceFromBoard vState pt

    MouseLeftUp click_pt _ -> dropDraggedPiece vState h click_pt

    MouseLeftDrag pt _ -> updateMousePosition vState pt

    _ -> return ()

