"""Place footprints for the fall-detector board and write the .kicad_pcb.

Run with KiCad's bundled Python:
    "%LOCALAPPDATA%/Programs/KiCad/10.0/bin/python.exe" scripts/build_pcb.py <netlist.net>

The netlist comes from `kicad-cli sch export netlist --format kicadsexpr`.
Board coordinates below are relative to the board's top-left corner (ORIGIN).
"""
import json
import os
import re
import sys

import pcbnew

PRJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOARD = os.path.join(PRJ, "fall_detector.kicad_pcb")
KICAD_FP = os.environ.get("KICAD10_FOOTPRINT_DIR") or \
    os.path.join(os.path.dirname(sys.executable), "..", "share", "kicad", "footprints")
LIBS = {"fall_detector": os.path.join(PRJ, "lib", "fall_detector.pretty")}

W, H = 60.0, 50.0          # board size (mm)
ORIGIN = (100.0, 100.0)    # page position of the board's top-left corner
CORNER_R = 2.0

# ref: (x, y, rotation_deg) -- position of pad 1 in board coordinates
PLACEMENT = {
    "U1": (9.0, 3.5, 0),      # ESP32-S3 SuperMini, USB-C at top edge
    "U2": (30.5, 6.04, 270),  # GY-521: header vertical (VCC at top, rows level with U1), body to the right
    "U3": (56.0, 24.0, 180),  # TTP223: header at bottom, module body upward
    "C2": (30.5, 2.3, 0),     # right above GY-521 VCC/GND
    "C3": (50.5, 28.5, 0),
    "C1": (22.5, 37.0, 0),    # metal can kept away from the SuperMini's chip antenna
    "J1": (4.0, 30.0, 0),
    "SW1": (13.5, 30.5, 0),
    "D2": (18.5, 35.5, 180),
    "R4": (6.5, 39.5, 0),
    "R5": (9.0, 43.0, 0),
    "C4": (19.5, 43.0, 0),
    "D1": (30.0, 32.4, 0),
    "BZ1": (30.0, 40.5, 0),
    "R2": (40.5, 32.5, 0),
    "Q1": (42.0, 38.0, 0),
    "R1": (42.0, 44.0, 0),
    "D3": (51.5, 37.0, 0),
    "R3": (58.0, 41.5, 90),
    "H1": (3.5, 3.5, 0),
    "H2": (W - 3.5, 3.5, 0),
    "H3": (3.5, H - 3.5, 0),
    "H4": (W - 3.5, H - 3.5, 0),
}

# Reference designator positions (board coords, text angle); refs not listed
# keep the library default, mounting holes are hidden.
REF_POS = {
    "U1": (15.62, 13.0, 0),
    "J1": (5.0, 26.6, 0),
    "SW1": (10.0, 27.6, 0),
    "C1": (21.6, 33.4, 0),
    "C2": (27.9, 2.3, 0),
    "C3": (53.0, 28.5, 0),
    "C4": (22.0, 43.0, 0),
    "D1": (33.81, 32.4, 0),
    "D2": (13.42, 35.5, 0),
    "D3": (52.77, 33.2, 0),
    "BZ1": (33.8, 44.6, 0),
    "Q1": (44.54, 41.1, 0),
    "R1": (45.81, 44.0, 0),
    "R2": (44.31, 32.5, 0),
    "R3": (58.0, 37.69, 90),
    "R4": (10.31, 39.5, 0),
    "R5": (12.81, 43.0, 0),
}


def mm(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(ORIGIN[0] + x), pcbnew.FromMM(ORIGIN[1] + y))


def parse_netlist(path):
    text = open(path, encoding="utf8").read()
    comps = {}
    for blk in re.split(r"\n\t\t\(comp\b", text.split("(libparts")[0])[1:]:
        ref = re.search(r'\(ref "([^"]+)"\)', blk).group(1)
        desc = re.search(r'\(description "([^"]*)"\)', blk)
        comps[ref] = {
            "value": re.search(r'\(value "([^"]*)"\)', blk).group(1),
            "footprint": re.search(r'\(footprint "([^"]*)"\)', blk).group(1),
            "uuid": re.search(r'\(tstamps "([^"]+)"\)', blk).group(1),
            "description": desc.group(1) if desc else "",
            "datasheet": (re.search(r'\(name "Datasheet"\) "([^"]*)"\)', blk) or [None, ""])[1],
        }
    nets = {}
    for blk in re.split(r"\n\t\t\(net\n", text[text.find("(nets"):])[1:]:
        name = re.search(r'\(name "([^"]*)"', blk).group(1)
        nets[name] = re.findall(r'\(ref "([^"]+)"\)\s*\(pin "([^"]+)"\)', blk)
    return comps, nets


def lib_path(nick):
    return LIBS.get(nick) or os.path.join(KICAD_FP, nick + ".pretty")


def add_outline(board):
    r = CORNER_R
    segs = [((r, 0), (W - r, 0)), ((W, r), (W, H - r)), ((W - r, H), (r, H)), ((0, H - r), (0, r))]
    for a, b in segs:
        s = pcbnew.PCB_SHAPE(board, pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(mm(*a))
        s.SetEnd(mm(*b))
        s.SetLayer(pcbnew.Edge_Cuts)
        s.SetWidth(pcbnew.FromMM(0.1))
        board.Add(s)
    # corner arcs: centre, start point (arc drawn clockwise 90 deg on screen)
    for cx, cy, sx, sy in [(r, r, 0, r), (W - r, r, W - r, 0), (W - r, H - r, W, H - r), (r, H - r, r, H)]:
        a = pcbnew.PCB_SHAPE(board, pcbnew.SHAPE_T_ARC)
        a.SetCenter(mm(cx, cy))
        a.SetStart(mm(sx, sy))
        a.SetArcAngleAndEnd(pcbnew.EDA_ANGLE(90, pcbnew.DEGREES_T), True)
        a.SetLayer(pcbnew.Edge_Cuts)
        a.SetWidth(pcbnew.FromMM(0.1))
        board.Add(a)


def add_text(board, s, x, y, layer, size=1.0, mirror=False, bold=False):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(s)
    t.SetPosition(mm(x, y))
    t.SetLayer(layer)
    t.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(size), pcbnew.FromMM(size)))
    t.SetTextThickness(pcbnew.FromMM(max(0.15, size * 0.15)))
    t.SetBold(bold)
    if mirror:
        t.SetMirrored(True)
    board.Add(t)


def main(netlist):
    comps, nets = parse_netlist(netlist)
    board = pcbnew.NewBoard(BOARD)  # always rebuild from scratch
    board.SetCopperLayerCount(2)
    tb = pcbnew.TITLE_BLOCK()
    tb.SetTitle("Mach phat hien te nga - ESP32-S3 SuperMini + MPU6050")
    tb.SetRevision("1.1")
    tb.SetDate("2026-09-26")
    board.SetTitleBlock(tb)
    ds = board.GetDesignSettings()
    ds.m_TrackMinWidth = pcbnew.FromMM(0.2)
    ds.m_MinClearance = pcbnew.FromMM(0.2)
    ds.m_ViasMinSize = pcbnew.FromMM(0.6)
    ds.m_MinThroughDrill = pcbnew.FromMM(0.3)
    ds.m_CopperEdgeClearance = pcbnew.FromMM(0.5)

    footprints = {}
    for ref, c in sorted(comps.items()):
        if ref.startswith("#"):
            continue
        nick, name = c["footprint"].split(":", 1)
        fp = pcbnew.FootprintLoad(lib_path(nick), name)
        if fp is None:
            raise SystemExit(f"footprint not found: {c['footprint']}")
        fp.SetFPID(pcbnew.LIB_ID(nick, name))
        fp.SetReference(ref)
        fp.SetValue(c["value"])
        fp.SetPath(pcbnew.KIID_PATH("/" + c["uuid"]))
        fp.SetSheetname("/")
        fp.SetSheetfile("fall_detector.kicad_sch")
        fp.SetField("Description", c["description"])
        fp.SetField("Datasheet", c["datasheet"])
        for field in (fp.Reference(), fp.Value()):
            field.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(1.0), pcbnew.FromMM(1.0)))
            field.SetTextThickness(pcbnew.FromMM(0.15))  # 0.15 mm = fab minimum stroke
        x, y, rot = PLACEMENT[ref]
        board.Add(fp)
        fp.SetOrientationDegrees(rot)
        fp.SetPosition(mm(x, y))
        if ref.startswith("H"):
            fp.Reference().SetVisible(False)
        elif ref in REF_POS:
            rx, ry, rang = REF_POS[ref]
            fp.Reference().SetPosition(mm(rx, ry))
            fp.Reference().SetTextAngleDegrees(rang)
        footprints[ref] = fp

    for name, nodes in sorted(nets.items()):
        net = pcbnew.NETINFO_ITEM(board, name)
        board.Add(net)
        for ref, pin in nodes:
            if ref not in footprints:
                continue
            pad = footprints[ref].FindPadByNumber(pin)
            if pad is None:
                raise SystemExit(f"pad {ref}.{pin} missing")
            pad.SetNet(net)

    add_outline(board)

    F, B = pcbnew.F_SilkS, pcbnew.B_SilkS
    add_text(board, "+", 4.0, 34.6, F, 1.2, bold=True)
    add_text(board, "-", 6.0, 34.6, F, 1.2, bold=True)
    add_text(board, "PWR", 15.0, 27.6, F)
    add_text(board, "TOUCH", 51.3, 7.2, F)
    add_text(board, "MPU6050", 42.5, 2.3, F)
    # back side: free area under the GY-521 module, clear of its header pads
    add_text(board, "Fall Detect v1.1", 44.0, 10.0, B, 1.5, mirror=True, bold=True)
    add_text(board, "Marine AIoT", 44.0, 13.0, B, 1.5, mirror=True, bold=True)

    board.Save(BOARD)
    setup_netclasses()
    print("saved", BOARD, "footprints:", len(footprints), "nets:", len(nets))


def setup_netclasses():
    """Default: 0.3 mm tracks; Power: 0.5 mm; 0.25 mm clearance; 0.8/0.4 mm vias.

    Net classes live in the .kicad_pro, so patch it after the board is saved.
    """
    pro = os.path.join(PRJ, "fall_detector.kicad_pro")
    d = json.load(open(pro, encoding="utf8"))
    ns = d["net_settings"]
    default = ns["classes"][0]
    default.update(track_width=0.3, clearance=0.25, via_diameter=0.8, via_drill=0.4)
    power = dict(default, name="Power", track_width=0.5, priority=0)
    ns["classes"] = [default, power]
    ns["netclass_patterns"] = [{"netclass": "Power", "pattern": n}
                               for n in ("/GND", "/+3V3", "/+5V", "/VBAT", "/VSW", "/BUZ_N")]
    rules = d["board"]["design_settings"]["rules"]
    rules.update(min_clearance=0.2, min_track_width=0.2, min_via_diameter=0.6,
                 min_through_hole_diameter=0.3, min_copper_edge_clearance=0.5)
    json.dump(d, open(pro, "w", encoding="utf8"), indent=2)


if __name__ == "__main__":
    main(sys.argv[1])
