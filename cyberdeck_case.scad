// Cyberdeck case: Raspberry Pi 4 + Waveshare 4.3" DSI + Rii mini X1 + power bank
// Clamshell, footprint ~158 x 106 mm. All sizes in mm.
// MEASURE YOUR PARTS WITH CALIPERS and fix the parameters below before printing.
//
// Export one part at a time:
//   openscad -D 'part="base"'  -o base.stl  cyberdeck_case.scad
//   parts: "base", "deck", "lid", "lid_cover", "assembly" (preview only)

part = "assembly";

/* ---------- outer size ---------- */
W = 158;            // width (left-right)
D = 106;            // depth (front-back)
t = 2.4;            // wall thickness
floor_t = 2;        // base floor thickness
$fn = 48;

/* ---------- parts ---------- */
// Rii mini X1 (~151 x 59 x 12.5 by listings)
kb = [151, 59, 12.5];
// power bank (you said 100 x 40; thickness unknown -> measure!)
pb = [40, 100, 22];           // x = width, y = length, z = thickness
pb_port_cut = [30, 14];       // cutout in back wall for charging cable (w, h)
// Raspberry Pi 4
pi_board = [56, 85, 1.4];     // rotated: port edge (USB-C/HDMI) faces +x, USB/Ethernet faces back
pi_standoff = 5;
pi_jack_h = 16.5;             // USB/Ethernet height above board
pi_jack_over = 2.5;           // how far USB/Ethernet stick out past the board
usbc_gap = 16;                // room for a right-angle USB-C plug between Pi and power bank
// Waveshare 4.3" DSI 800x480
scr_board = [106, 68];        // board outline
scr_view  = [96, 55];         // visible area -> window in lid
scr_stack = 8;                // board + glass + parts on the back
scr_center_y = 49;            // window center, from front edge of lid
// fan
fan = 25;                     // 25 or 30 mm (30 needs pb[2] >= 27 or so)
fan_hole_pitch = (fan == 30) ? 24 : 20;
fan_center_y = 50;
// DSI ribbon slot (deck and lid)
dsi_slot = [22, 4];
dsi_slot_c = [70, 92];        // center x, y
// hinge
hinge_r = 4.5;
hinge_pin = 3.4;              // M3 bolt
hinge_w = 12;                 // knuckle width
hinge_gap = 0.4;

/* ---------- derived ---------- */
e_h     = max(pb[2], pi_standoff + pi_board[2] + pi_jack_h) + 2.5; // electronics bay height
deck_t  = 2;
deck_z  = floor_t + e_h;
pocket  = kb[2] + 0.5;
H       = deck_z + deck_t + pocket;     // base height
lid_h   = 2 + scr_stack + 2;
hinge_y = D + hinge_r + 0.5;

pb_x0 = W - t - pb[0];
pi_x1 = pb_x0 - usbc_gap;               // Pi port edge
pi_x0 = pi_x1 - pi_board[0];
pi_y1 = D - t - pi_jack_over - 0.5;     // Pi USB end
pi_y0 = pi_y1 - pi_board[1];
pi_z  = floor_t + pi_standoff;

// Pi mounting holes: 3.5 / 52.5 from port edge, 3.5 / 61.5 from SD end
pi_holes = [for (a = [3.5, 61.5], b = [3.5, 52.5]) [pi_x1 - b, pi_y0 + a]];
deck_bosses = [[t + 7, t + 7], [t + 7, D - t - 7]];

echo(str("Base height H = ", H, " mm, lid = ", lid_h, " mm, closed = ", H + lid_h, " mm"));

/* ---------- helpers ---------- */
module rbox(s, r = 3) {
    hull() for (x = [r, s[0] - r], y = [r, s[1] - r]) translate([x, y, 0]) cylinder(r = r, h = s[2]);
}
module slots(n, len, w, pitch) {
    for (i = [0 : n - 1]) translate([i * pitch, 0, 0]) hull() {
        translate([w/2, w/2, 0]) cylinder(d = w, h = 20, center = true);
        translate([w/2, len - w/2, 0]) cylinder(d = w, h = 20, center = true);
    }
}
module knuckle(x0, z_dir) {   // z_dir = -1 for base (block below axis), +1 for lid
    difference() {
        hull() {
            translate([x0, hinge_y, 0]) rotate([0, 90, 0]) cylinder(r = hinge_r, h = hinge_w);
            translate([x0, D - 2, z_dir > 0 ? 0 : -9]) cube([hinge_w, 2, 9]);
        }
        translate([x0 - 1, hinge_y, 0]) rotate([0, 90, 0]) cylinder(d = hinge_pin, h = hinge_w + 2);
    }
}
base_kn = [6, W - 6 - hinge_w];
lid_kn  = [6 + hinge_w + hinge_gap, W - 6 - 2 * hinge_w - hinge_gap];

/* ---------- base ---------- */
module base() {
    difference() {
        union() {
            difference() {
                rbox([W, D, H]);
                translate([t, t, floor_t]) cube([W - 2 * t, D - 2 * t, H]);
            }
            // deck ledge with 45deg chamfer underneath
            difference() {
                translate([t, t, deck_z - 3.5]) cube([W - 2 * t, D - 2 * t, 3.5]);
                hull() {
                    translate([t + 1.5, t + 1.5, deck_z - 3.5 - 0.01]) cube([W - 2 * t - 3, D - 2 * t - 3, 3.6]);
                    translate([t, t, deck_z - 3.5 - 0.01]) cube([W - 2 * t, D - 2 * t, 0.01]);
                }
            }
            // Pi standoffs
            for (p = pi_holes) translate([p[0], p[1], 0]) cylinder(d = 6, h = pi_z);
            // deck screw bosses
            for (p = deck_bosses) translate([p[0], p[1], 0]) cylinder(d = 8, h = deck_z);
            // hinge
            for (x = base_kn) translate([0, 0, H]) knuckle(x, -1);
        }
        // Pi screw holes (M2.5 self-tapping)
        for (p = pi_holes) translate([p[0], p[1], 1]) cylinder(d = 2.2, h = 20);
        for (p = deck_bosses) translate([p[0], p[1], 5]) cylinder(d = 2.5, h = 50);
        // back wall: Pi USB + Ethernet
        translate([pi_x1 - 55, D - t - 1, pi_z + pi_board[2] - 0.5]) cube([54, t + 2, pi_jack_h + 1.5]);
        // back wall: power bank port
        translate([pb_x0 + pb[0] / 2 - pb_port_cut[0] / 2, D - t - 1, floor_t + pb[2] / 2 - pb_port_cut[1] / 2])
            cube([pb_port_cut[0], t + 2, pb_port_cut[1]]);
        // left wall: fan + screw holes
        translate([-1, fan_center_y, floor_t + e_h / 2]) rotate([0, 90, 0]) {
            cylinder(d = fan - 2, h = t + 2);
            for (i = [-1, 1], j = [-1, 1]) translate([i * fan_hole_pitch / 2, j * fan_hole_pitch / 2, 0]) cylinder(d = 3.2, h = t + 2);
        }
        // right wall: intake slots next to power bank
        translate([W + 1, 15, floor_t + 4]) rotate([90, 0, 90]) rotate([0, 0, 0])
            for (i = [0 : 7]) translate([i * 9, 0, -5]) hull() {
                translate([0, 0, 0]) cylinder(d = 3, h = 10);
                translate([0, e_h - 9, 0]) cylinder(d = 3, h = 10);
            }
        // floor vents under the Pi
        translate([pi_x0 + 6, pi_y0 + 10, floor_t / 2]) slots(8, 60, 3, 5.5);
        // no ledge where the fan sits
        translate([t, fan_center_y - fan / 2 - 0.5, floor_t]) cube([2, fan + 1, e_h]);
        // finger notch in front wall to lift the keyboard
        translate([W / 2, -1, H]) rotate([-90, 0, 0]) scale([1, 0.35, 1]) cylinder(d = 45, h = t + 2);
    }
}

/* ---------- deck (rests on the ledge, keyboard sits on top) ---------- */
module deck() {
    dx = W - 2 * t - 0.4; dy = D - 2 * t - 0.4;
    difference() {
        union() {
            cube([dx, dy, deck_t]);
            // keyboard stop rib
            translate([2, kb[1] + 0.8, 0]) cube([dx - 4, 2, deck_t + 3]);
        }
        translate([dsi_slot_c[0] - t - dsi_slot[0] / 2, dsi_slot_c[1] - t - dsi_slot[1] / 2, -1]) cube([dsi_slot[0], dsi_slot[1], 10]);
        // vents behind the keyboard
        translate([pi_x0 - t, kb[1] + 6, deck_t / 2]) slots(6, 18, 3, 6);
        translate([pb_x0 - t + 2, kb[1] + 6, deck_t / 2]) slots(6, 18, 3, 6);
        // countersunk screws into bosses
        for (p = deck_bosses) translate([p[0] - t - 0.2, p[1] - t - 0.2, -1]) {
            cylinder(d = 3.2, h = 10);
            translate([0, 0, deck_t + 1 - 1.7]) cylinder(d1 = 3.2, d2 = 6.4, h = 1.71);
        }
    }
}

/* ---------- lid (printed face down) ---------- */
lid_bosses = [for (x = [t + 4, W - t - 4], y = [t + 4, D - t - 4]) [x, y]];
module lid() {
    sx = W / 2 - scr_board[0] / 2; sy = scr_center_y - scr_board[1] / 2;
    difference() {
        union() {
            difference() {
                rbox([W, D, lid_h]);
                translate([t, t, 2]) cube([W - 2 * t, D - 2 * t, lid_h]);
            }
            // screen locating frame
            difference() {
                translate([sx - 1.5, sy - 1.5, 0]) cube([scr_board[0] + 3.6, scr_board[1] + 3.6, 2 + 4]);
                translate([sx - 0.3, sy - 0.3, 1]) cube([scr_board[0] + 0.6 + 0.6, scr_board[1] + 0.6 + 0.6, 10]);
            }
            for (p = lid_bosses) translate([p[0], p[1], 0]) cylinder(d = 7, h = lid_h - 2);
            for (x = lid_kn) knuckle(x, 1);
        }
        // window
        translate([W / 2 - scr_view[0] / 2, scr_center_y - scr_view[1] / 2, -1]) cube([scr_view[0], scr_view[1], 10]);
        // DSI ribbon slot
        translate([dsi_slot_c[0] - dsi_slot[0] / 2, dsi_slot_c[1] - dsi_slot[1] / 2, -1]) cube([dsi_slot[0], dsi_slot[1], 10]);
        for (p = lid_bosses) translate([p[0], p[1], 2.5]) cylinder(d = 2.5, h = 20);
    }
}
module lid_cover() {
    difference() {
        translate([t + 0.2, t + 0.2, 0]) cube([W - 2 * t - 0.4, D - 2 * t - 0.4, 2]);
        for (p = lid_bosses) translate([p[0], p[1], -1]) {
            cylinder(d = 3.2, h = 10);
            translate([0, 0, 3 - 1.7]) cylinder(d1 = 3.2, d2 = 6.4, h = 1.71);
        }
        // vents over the screen board
        translate([W / 2 - 40, scr_center_y - 15, 1]) slots(10, 30, 3, 8);
    }
}

/* ---------- dummies for the preview ---------- */
module dummies() {
    color("green") translate([pi_x0, pi_y0, pi_z]) cube(pi_board);
    color("silver") translate([pi_x1 - 54, pi_y1 - 21, pi_z + pi_board[2]]) cube([53, 21 + pi_jack_over, pi_jack_h]);
    color("dimgray") translate([pb_x0, t + 0.6, floor_t]) cube(pb);
    color("black") translate([W / 2 - kb[0] / 2, t + 0.5, deck_z + deck_t]) cube(kb);
}

if (part == "base") base();
else if (part == "deck") deck();
else if (part == "lid") lid();
else if (part == "lid_cover") lid_cover();
else {
    color("lightgray") base();
    color("orange") translate([t + 0.2, t + 0.2, deck_z]) deck();
    dummies();
    // lid opened to 105 degrees
    translate([0, hinge_y, H]) rotate([-105, 0, 0]) translate([0, -hinge_y, 0]) {
        color("lightgray", 0.9) lid();
        color("orange") translate([0, 0, lid_h - 2]) lid_cover();
    }
}
