"""Route the fall-detector board with fixed tracks, then add the GND pours.

    python.exe scripts/route_manual.py

Run after build_pcb.py; needs no Java/Freerouting. Coordinates are board mm
relative to the top-left corner (same as build_pcb.py). Widths follow the net
classes that build_pcb.py writes: Power 0.5 mm, Default 0.3 mm.
"""
import os

import pcbnew

PRJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOARD = os.path.join(PRJ, "fall_detector.kicad_pcb")
BOARD_W, BOARD_H, ORIGIN = 60.0, 50.0, (100.0, 100.0)
POWER_NETS = {"/GND", "/+3V3", "/+5V", "/VBAT", "/VSW", "/BUZ_N"}

# The SuperMini's chip antenna is at the end away from USB-C, ~11 mm above this
# board (x 10.7-17.7, y 23.1-25.4). Keep pour, tracks and vias out from under it,
# and keep the top-layer pour off the rest of the module's lower half.
ANTENNA_KEEPOUT = (10.0, 21.8, 18.0, 26.6)  # x1, y1, x2, y2
TOP_POUR_KEEPOUT = (10.0, 17.7, 29.6, 26.8)

F, B = "F.Cu", "B.Cu"

# net: [(layer, (x1, y1), (x2, y2)), ...]
TRACKS = {
    "/VBAT": [  # J1.1 -> SW1.1
        (B, (4.0, 30.0), (5.378, 31.378)),
        (B, (5.378, 31.378), (8.75, 31.378)),
        (B, (8.75, 31.378), (9.628, 30.5)),
        (B, (9.628, 30.5), (11.23, 30.5)),
    ],
    "/VSW": [  # SW1.2 -> D2 anode -> R4.1
        (B, (13.5, 30.5), (8.5, 35.5)),
        (B, (8.5, 35.5), (8.34, 35.5)),
        (F, (8.34, 35.5), (8.34, 37.66)),
        (F, (8.34, 37.66), (6.5, 39.5)),
    ],
    "/+5V": [  # D2 cathode -> SuperMini 5V (= its USB VBUS / LDO input)
        (B, (24.24, 3.5), (18.5, 9.24)),
        (B, (18.5, 9.24), (18.5, 35.5)),
    ],
    "/+3V3": [
        (F, (24.24, 8.58), (26.78, 6.04)),  # U1 3V3 -> GY-521 VCC
        (F, (26.78, 6.04), (30.5, 6.04)),
        (F, (30.5, 6.04), (30.5, 2.3)),  # -> C2
        (B, (30.5, 6.04), (48.4, 6.04)),  # -> TTP223 VCC, C3
        (B, (48.4, 6.04), (50.92, 8.56)),
        (B, (50.92, 8.56), (50.92, 24.0)),
        (B, (50.92, 24.0), (50.92, 28.08)),
        (B, (50.92, 28.08), (50.5, 28.5)),
        (B, (24.24, 8.58), (21.5, 11.32)),  # U1 3V3 -> C1 -> D1 -> buzzer
        (B, (21.5, 11.32), (21.5, 36.0)),
        (B, (21.5, 36.0), (22.5, 37.0)),
        (F, (22.5, 37.0), (27.1, 32.4)),
        (F, (27.1, 32.4), (30.0, 32.4)),
        (B, (30.0, 32.4), (30.0, 40.5)),
    ],
    "/GND": [  # the pours carry most of GND; these tie the pad clusters together
        (B, (24.24, 6.04), (26.78, 8.58)),  # U1 GND -> GY-521 GND
        (B, (26.78, 8.58), (30.5, 8.58)),
        (B, (56.0, 24.0), (56.0, 28.0)),  # TTP223 GND -> C3
        (B, (56.0, 28.0), (55.5, 28.5)),
        (B, (42.0, 38.0), (43.3, 39.3)),  # Q1 E -> D3 K -> R2
        (B, (43.3, 39.3), (47.74, 39.3)),
        (B, (47.74, 39.3), (50.04, 37.0)),
        (B, (50.04, 37.0), (51.5, 37.0)),
        (B, (50.04, 37.0), (50.04, 34.42)),
        (B, (50.04, 34.42), (48.12, 32.5)),
        (B, (24.5, 43.0), (25.0, 42.5)),  # C4 -> C1
        (B, (25.0, 42.5), (25.0, 37.0)),
        (F, (16.62, 43.0), (17.94, 44.32)),  # R5 -> C4
        (F, (17.94, 44.32), (23.18, 44.32)),
        (F, (23.18, 44.32), (24.5, 43.0)),
    ],
    "/VBAT_ADC": [  # GPIO1 -> R4/R5 divider and C4
        (B, (9.0, 8.58), (2.956, 14.624)),
        (B, (2.956, 14.624), (2.956, 34.256)),
        (B, (2.956, 34.256), (9.0, 40.3)),
        (B, (9.0, 40.3), (9.0, 43.0)),
        (F, (9.0, 43.0), (12.5, 39.5)),
        (F, (12.5, 39.5), (14.12, 39.5)),
        (F, (14.12, 39.5), (16.0, 39.5)),
        (F, (16.0, 39.5), (19.5, 43.0)),
    ],
    "/I2C_SCL": [  # GPIO9 -> SCL, bottom-layer lane between the U1 and U2 headers
        (B, (24.24, 21.28), (26.4, 21.28)),
        (B, (26.4, 21.28), (26.4, 12.4)),
        (B, (26.4, 12.4), (27.68, 11.12)),
        (B, (27.68, 11.12), (30.5, 11.12)),
    ],
    "/I2C_SDA": [  # GPIO8 -> SDA, second lane
        (B, (24.24, 23.82), (27.9, 23.82)),
        (B, (27.9, 23.82), (27.9, 15.0)),
        (B, (27.9, 15.0), (29.24, 13.66)),
        (B, (29.24, 13.66), (30.5, 13.66)),
    ],
    "/MPU_INT": [  # GPIO7 -> INT, below the antenna keep-out
        (F, (9.0, 23.82), (7.9, 24.92)),
        (F, (7.9, 24.92), (7.9, 26.0)),
        (F, (7.9, 26.0), (8.85, 26.95)),
        (F, (8.85, 26.95), (27.37, 26.95)),
        (F, (27.37, 26.95), (30.5, 23.82)),
    ],
    "/TOUCH": [  # GPIO4 -> TTP223 I/O, between unused header pins (U1 14/15, U2 SDA/XDA)
        (F, (9.0, 16.2), (10.27, 14.93)),
        (F, (10.27, 14.93), (44.39, 14.93)),
        (F, (44.39, 14.93), (53.46, 24.0)),
    ],
    "/LED_CTRL": [  # GPIO6 -> R3, above the antenna, between unused header pins (U1 15/16, U2 XDA/XCL)
        (F, (9.0, 21.28), (12.81, 17.47)),
        (F, (12.81, 17.47), (38.5, 17.47)),
        (F, (38.5, 17.47), (38.5, 26.81)),
        (F, (38.5, 26.81), (53.19, 41.5)),
        (F, (53.19, 41.5), (58.0, 41.5)),
    ],
    "/LED_A": [
        (B, (54.04, 37.0), (54.88, 37.0)),
        (B, (54.88, 37.0), (58.0, 33.88)),
    ],
    "/BUZ_CTRL": [  # GPIO5 -> R1
        (F, (9.0, 18.74), (2.928, 24.812)),
        (F, (2.928, 24.812), (2.928, 30.908)),
        (F, (2.928, 30.908), (6.019, 33.998)),
        (F, (6.019, 33.998), (13.833, 33.998)),
        (F, (13.833, 33.998), (21.45, 41.616)),
        (F, (21.45, 41.616), (28.548, 41.616)),
        (F, (28.548, 41.616), (30.932, 44.0)),
        (F, (30.932, 44.0), (42.0, 44.0)),
    ],
    "/BUZ_B": [
        (F, (44.54, 38.0), (45.718, 36.822)),
        (F, (45.718, 36.822), (47.543, 36.822)),
        (F, (47.543, 36.822), (49.62, 38.9)),
        (F, (49.62, 38.9), (49.62, 44.0)),
        (B, (44.54, 38.0), (44.54, 36.54)),
        (B, (44.54, 36.54), (40.5, 32.5)),
    ],
    "/BUZ_N": [
        (F, (47.08, 38.0), (44.58, 40.5)),
        (F, (44.58, 40.5), (37.6, 40.5)),
        (B, (37.6, 40.5), (37.62, 32.4)),
    ],
}


def pt(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(ORIGIN[0] + x), pcbnew.FromMM(ORIGIN[1] + y))


def rect_outline(zone, x1, y1, x2, y2):
    ol = zone.Outline()
    ol.NewOutline()
    for x, y in [(x1, y1), (x2, y1), (x2, y2), (x1, y2)]:
        ol.Append(pcbnew.FromMM(ORIGIN[0] + x), pcbnew.FromMM(ORIGIN[1] + y))


def add_gnd_zone(board, layer, net):
    z = pcbnew.ZONE(board)
    z.SetLayer(layer)
    z.SetNetCode(net.GetNetCode())
    z.SetLocalClearance(pcbnew.FromMM(0.3))
    z.SetMinThickness(pcbnew.FromMM(0.25))
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_THERMAL)
    z.SetThermalReliefGap(pcbnew.FromMM(0.4))
    z.SetThermalReliefSpokeWidth(pcbnew.FromMM(0.5))
    rect_outline(z, 0, 0, BOARD_W, BOARD_H)
    board.Add(z)


def add_rule_area(board, name, layers, rect, tracks):
    z = pcbnew.ZONE(board)
    z.SetIsRuleArea(True)
    z.SetZoneName(name)
    z.SetLayerSet(layers)
    z.SetDoNotAllowZoneFills(True)
    z.SetDoNotAllowTracks(tracks)
    z.SetDoNotAllowVias(True)
    z.SetDoNotAllowPads(False)
    z.SetDoNotAllowFootprints(False)
    rect_outline(z, *rect)
    board.Add(z)


def add_antenna_keepout(board):
    add_rule_area(board, "ANTENNA_KEEPOUT", pcbnew.LSET.AllCuMask(2), ANTENNA_KEEPOUT, True)
    top = pcbnew.LSET()
    top.AddLayer(pcbnew.F_Cu)
    add_rule_area(board, "TOP_POUR_KEEPOUT", top, TOP_POUR_KEEPOUT, False)


def add_zones(board):
    gnd = board.FindNet("/GND")
    add_gnd_zone(board, pcbnew.B_Cu, gnd)
    add_gnd_zone(board, pcbnew.F_Cu, gnd)
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())


def main():
    board = pcbnew.LoadBoard(BOARD)
    for t in list(board.GetTracks()):
        board.Delete(t)
    for i in reversed(range(board.GetAreaCount())):
        board.Delete(board.GetArea(i))
    add_antenna_keepout(board)

    layers = {F: pcbnew.F_Cu, B: pcbnew.B_Cu}
    count = 0
    for name, segs in TRACKS.items():
        net = board.FindNet(name)
        if net is None:
            raise SystemExit(f"net not on board: {name}")
        width = pcbnew.FromMM(0.5 if name in POWER_NETS else 0.3)
        for layer, a, b in segs:
            t = pcbnew.PCB_TRACK(board)
            t.SetLayer(layers[layer])
            t.SetStart(pt(*a))
            t.SetEnd(pt(*b))
            t.SetWidth(width)
            t.SetNet(net)
            board.Add(t)
            count += 1

    add_zones(board)
    board.Save(BOARD)
    print("tracks:", count)


if __name__ == "__main__":
    main()
