"""Rough Pi 4B + 4.3" DSI display blocks for preview renders only (not printed).

Placement matches lid.py (PI_X0, PI_Y0, USB_TOP); update both together.
Usage: pi_proxy.py out.stl
"""
import sys

import trimesh

PI_X0, PI_Y0, USB_TOP = 47.5, 27.0, 30.0
Z = USB_TOP - 15.6 - 1.4      # Pi board bottom
top = Z + 1.4
parts = [trimesh.creation.box(bounds=[(27, 21, 0), (133, 89, 6)]),                  # display
         trimesh.creation.box(bounds=[(PI_X0, PI_Y0, Z), (PI_X0 + 85, PI_Y0 + 56, top)])]
for w, width, h, over in ((9.0, 13.3, 15.6, 2.0), (27.0, 13.3, 15.6, 2.0), (45.75, 15.9, 13.5, 3.0)):
    parts.append(trimesh.creation.box(bounds=[(PI_X0 + 85 - 17.5, PI_Y0 + w - width / 2, top),
                                              (PI_X0 + 85 + over, PI_Y0 + w + width / 2, top + h)]))
parts.append(trimesh.creation.box(bounds=[(PI_X0 + 11.2 - 4.5, PI_Y0 - 1.0, top),
                                          (PI_X0 + 11.2 + 4.5, PI_Y0 + 6.5, top + 3.2)]))   # USB-C
trimesh.util.concatenate(parts).export(sys.argv[1])
