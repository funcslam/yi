module Yi.Keymap.Vim2.TextObject
  ( TextObject(..)
  , OperandDetectResult(..)
  , StyledRegion(..)
  , parseTextObject
  , regionOfTextObjectB
  , changeTextObjectCount
  ) where

import Prelude ()
import Yi.Prelude

import Control.Monad (replicateM_)

import Data.Maybe (isJust, fromJust)

import Yi.Buffer
import Yi.Keymap.Vim2.EventUtils
import Yi.Keymap.Vim2.Motion
import Yi.Keymap.Vim2.StyledRegion

data TextObject = TextObject !Int !RegionStyle TextUnit

data OperandDetectResult = JustTextObject !TextObject
                         | JustMove !CountedMove
                         | Partial
                         | Fail

parseTextObject :: String -> OperandDetectResult
parseTextObject s = setOperandCount count (parseCommand commandString)
    where (count, commandString) = splitCountedCommand s

changeTextObjectCount :: Int -> TextObject -> TextObject
changeTextObjectCount count (TextObject _c s u) = TextObject count s u

setOperandCount :: Int -> OperandDetectResult -> OperandDetectResult
setOperandCount n (JustTextObject (TextObject _ s u)) = JustTextObject (TextObject n s u)
setOperandCount n (JustMove (CountedMove _ m)) = JustMove (CountedMove n m)
setOperandCount _ o = o

parseCommand :: String -> OperandDetectResult
parseCommand "" = Partial
parseCommand s | isJust (stringToMove s) = JustMove $ CountedMove 1 $ fromJust $ stringToMove s
parseCommand "V" = Partial
parseCommand "Vl" = JustTextObject $ TextObject 1 LineWise VLine
parseCommand _ = Fail

regionOfTextObjectB :: TextObject -> BufferM StyledRegion
regionOfTextObjectB to = do
    result@(StyledRegion style reg) <- textObjectRegionB' to
    -- from vim help:
    --
    -- 1. If the motion is exclusive and the end of the motion is in column 1, the
    --    end of the motion is moved to the end of the previous line and the motion
    --    becomes inclusive.  Example: "}" moves to the first line after a paragraph,
    --    but "d}" will not include that line.
    -- 						*exclusive-linewise*
    -- 2. If the motion is exclusive, the end of the motion is in column 1 and the
    --    start of the motion was at or before the first non-blank in the line, the
    --    motion becomes linewise.  Example: If a paragraph begins with some blanks
    --    and you do "d}" while standing on the first non-blank, all the lines of
    --    the paragraph are deleted, including the blanks.  If you do a put now, the
    --    deleted lines will be inserted below the cursor position.
    --
    -- TODO: case 2
    if style == Exclusive
    then do
        let end = regionEnd reg
        (_, endColumn) <- getLineAndColOfPoint end
        if endColumn == 0
        then return $ StyledRegion Inclusive $ reg { regionEnd = end -~ 1 }
        else return result
    else return result

textObjectRegionB' :: TextObject -> BufferM StyledRegion
textObjectRegionB' (TextObject count style unit) =
    fmap (StyledRegion style) $ regionWithTwoMovesB
        (maybeMoveB unit Backward)
        (replicateM_ count $ maybeMoveB unit Forward)