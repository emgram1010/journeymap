"""COP-2 story 04 - Undo over real HTTP, as TEST admin usr2-q (account 13). WRITES: undoes copilot
action 17 (a test note the copilot saved at "tell"), which removes that note.
Usage:  python cop2_undo_probe.py <magic-token|->
"""
import sys
from cop5_lib import *

T = token(sys.argv)
U = MEM + "/copilot/action_undo"
c, b = req("POST", U, {"action_id": 17}, T)
check("undo a saved note -> 200", c == 200 and b.get("undone") is True, short(b))
c, b = req("POST", U, {"action_id": 17}, T)
check("undo it again -> E-COP-072", c >= 400 and "E-COP-072" in short(b), short(b))
c, b = req("POST", U, {"action_id": 26}, T)
check("a work update -> E-COP-071 (no false Undo)", c >= 400 and "E-COP-071" in short(b), short(b))
c, b = req("POST", U, {"action_id": 999999}, T)
check("unknown -> E-COP-029", c >= 400 and "E-COP-029" in short(b), short(b))
done()
