"""Autoroute the fall-detector board with Freerouting, then add GND pours.

    python.exe scripts/route_pcb.py <java.exe> <freerouting.jar> <work_dir>

Alternative to route_manual.py (which produced the committed board).

Track widths/clearances come from the net classes that build_pcb.py writes
into fall_detector.kicad_pro (Default 0.3 mm, Power 0.5 mm, 0.25 mm clearance).
"""
import os
import subprocess
import sys

import pcbnew

from route_manual import BOARD, add_antenna_keepout, add_zones


def main(java, jar, work):
    dsn = os.path.join(work, "fall_detector.dsn")
    ses = os.path.join(work, "fall_detector.ses")

    board = pcbnew.LoadBoard(BOARD)
    for t in list(board.GetTracks()):
        board.Remove(t)
    for z in list(board.Zones()):
        board.Remove(z)
    add_antenna_keepout(board)  # exported to the DSN as a keepout, so the router avoids it
    if not pcbnew.ExportSpecctraDSN(board, dsn):
        raise SystemExit("DSN export failed")

    if os.path.exists(ses):
        os.remove(ses)
    subprocess.run([java, "-jar", jar, "-de", dsn, "-do", ses, "-mp", "30", "-mt", "1"],
                   check=True, cwd=work)
    if not pcbnew.ImportSpecctraSES(board, ses):
        raise SystemExit("SES import failed")

    add_zones(board)
    board.Save(BOARD)
    print("routed tracks/vias:", len(board.GetTracks()))


if __name__ == "__main__":
    main(*sys.argv[1:4])
