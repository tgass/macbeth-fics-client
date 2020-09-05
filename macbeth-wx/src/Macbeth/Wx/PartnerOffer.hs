module Macbeth.Wx.PartnerOffer (
  wxPartnerOffer
) where

import           Control.Concurrent
import           Graphics.UI.WX
import           Macbeth.Fics.Message
import           Macbeth.Fics.Api.Player
import           Macbeth.Wx.Utils
import qualified Macbeth.Wx.Commands as Cmds
import           System.IO


wxPartnerOffer :: Handle -> UserHandle -> Chan Message  -> IO ()
wxPartnerOffer h userHandle chan = do
  f <- frame []
  p <- panel f []

  b_accept  <- button p [text := "Accept", on command := Cmds.accept h >> close f]
  b_decline <- button p [text := "Decline", on command := Cmds.decline h >> close f]
  st_params <- staticText p [ text := name userHandle ++ " offers to be your bughouse partner."
                            , fontFace := "Avenir Next Medium"
                            , fontSize := 16
                            , fontWeight := WeightBold]

  set f [ defaultButton := b_accept
        , layout := container p $ margin 10 $
            column 5 [boxed "Bughouse" (
              grid 5 5 [
                [ hfill $ widget st_params]]
            )
            , floatBottomRight $ row 5 [widget b_accept, widget b_decline]]
        ]

  dupChan chan >>= registerWxCloseEventListener f
