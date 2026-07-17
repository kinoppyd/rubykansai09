/*
 * Raspberry Pi Pico 2 W + MPU-6050 wheel speed sensor enclosure
 *
 * The electronic assembly envelope is 51 x 21 x 19 mm.
 * The enclosure and hub saddle are separate so the saddle can be changed for
 * another hub diameter without redesigning the electronics enclosure.
 *
 * Export one part at a time by changing `part`:
 *   "body", "lid", "gasket", "saddle", or "assembly"
 */

$fn = 72;
part = "assembly";

// Measured electronics envelope (universal PCB, Pico, MPU-6050, battery).
assembly_x = 51.0;
assembly_y = 21.0;
assembly_z = 19.0;

// FDM fit allowances. Increase xy_clearance to 0.7 for a rough printer.
xy_clearance = 0.5;
top_clearance = 0.8;
wall = 2.4;
bottom = 3.2;
support_rail_h = 0.8;
end_zone = 5.5;

cavity_x = assembly_x + 2 * xy_clearance;
cavity_y = assembly_y + 2 * xy_clearance;
body_x = cavity_x + 2 * end_zone;
body_y = cavity_y + 2 * wall;
body_z = bottom + support_rail_h + assembly_z + top_clearance;
body_r = 4.0;

// Lid and seal.
lid_roof = 2.4;
lid_skirt_h = 1.6;
lid_fit = 0.35;
lid_skirt_wall = 1.2;
gasket_h = 0.8;
gasket_band = 1.6;
lid_screw_d = 3.4;
body_pilot_d = 2.8; // M3 thread-forming screw pilot; tune for material.
screw_x = cavity_x / 2 + end_zone / 2;
lid_inner_x = body_x + 2 * lid_fit;
lid_inner_y = body_y + 2 * lid_fit;
lid_outer_x = lid_inner_x + 2 * lid_skirt_wall;
lid_outer_y = lid_inner_y + 2 * lid_skirt_wall;

// Replaceable hub saddle.
// The 32 mm diameter is provisional for the Mavic Ksyrium Elite S front hub.
// Mavic's product sheet does not dimension the outer hub shell; measure the
// actual straight center barrel before the final print.
hub_diameter = 32.0;
saddle_x = 38.0;
saddle_y = 34.0;
saddle_h = 8.0;
saddle_r = 3.0;
hub_contact_depth = 3.0;
strap_width = 4.5;
strap_slot_y = 3.2;
strap_x = 12.0;
strap_y = 14.0;
mount_x = 10.0;
mount_clearance_d = 3.4;
insert_hole_d = 4.2; // Typical M3 heat-set insert; measure the actual insert.
insert_depth = 5.0;

module rounded_box(size, radius, center_xy = true) {
  x = size[0];
  y = size[1];
  z = size[2];
  translate(center_xy ? [0, 0, 0] : [x / 2, y / 2, 0])
    hull()
      for (sx = [-1, 1], sy = [-1, 1])
        translate([sx * (x / 2 - radius), sy * (y / 2 - radius), 0])
          cylinder(h = z, r = radius);
}

module rounded_ring_2d(outer_size, outer_r, band) {
  difference() {
    offset(r = outer_r)
      square([outer_size[0] - 2 * outer_r,
              outer_size[1] - 2 * outer_r], center = true);
    offset(r = max(outer_r - band, 0.2))
      square([outer_size[0] - 2 * outer_r - 2 * band,
              outer_size[1] - 2 * outer_r - 2 * band], center = true);
  }
}

module countersunk_mount_hole() {
  translate([0, 0, -0.1]) cylinder(h = bottom + 0.2, d = mount_clearance_d);
  translate([0, 0, bottom - 1.9])
    cylinder(h = 2.0, d1 = mount_clearance_d, d2 = 6.4);
}

module enclosure_body() {
  difference() {
    rounded_box([body_x, body_y, body_z], body_r);

    // Main electronics cavity. It is open through the top.
    translate([0, 0, bottom])
      rounded_box([cavity_x, cavity_y, body_z - bottom + 0.2], 2.0);

    // Two pilot holes in the solid end zones for the lid screws.
    for (sx = [-1, 1])
      translate([sx * screw_x, 0, body_z - 10.0])
        cylinder(h = 10.2, d = body_pilot_d);

    // Flush M3 holes used to attach the replaceable saddle.
    for (sx = [-1, 1])
      translate([sx * mount_x, 0, 0]) countersunk_mount_hole();
  }

  // Narrow rails support the universal PCB without loading the battery area.
  for (sy = [-1, 1])
    translate([0,
               sy * (cavity_y / 2 - 0.75),
               bottom + support_rail_h / 2])
      cube([assembly_x - 4.0, 1.5, support_rail_h], center = true);
}

module enclosure_lid() {
  difference() {
    union() {
      // Roof.
      rounded_box([lid_outer_x,
                   lid_outer_y,
                   lid_roof], body_r + lid_fit + lid_skirt_wall);

      // External rain skirt; it overlaps the enclosure rather than entering
      // the electronics cavity.
      translate([0, 0, -lid_skirt_h])
        linear_extrude(height = lid_skirt_h)
          difference() {
            offset(r = body_r + lid_fit + lid_skirt_wall)
              square([lid_outer_x - 2 * (body_r + lid_fit + lid_skirt_wall),
                      lid_outer_y - 2 * (body_r + lid_fit + lid_skirt_wall)], center = true);
            offset(r = body_r + lid_fit)
              square([lid_inner_x - 2 * (body_r + lid_fit),
                      lid_inner_y - 2 * (body_r + lid_fit)], center = true);
          }
    }

    for (sx = [-1, 1])
      translate([sx * screw_x, 0, -lid_skirt_h - 0.1])
        cylinder(h = lid_skirt_h + lid_roof + 0.2, d = lid_screw_d);

    // Shallow guides keep optional external safety straps from migrating.
    for (sx = [-1, 1])
      translate([sx * strap_x, 0, lid_roof - 0.55])
        cube([strap_width, lid_outer_y + 1.0, 0.7], center = true);
  }
}

module lid_gasket() {
  difference() {
    linear_extrude(height = gasket_h)
      rounded_ring_2d([body_x - 0.8, body_y - 0.8], body_r - 0.4, gasket_band);
    for (sx = [-1, 1])
      translate([sx * screw_x, 0, -0.1]) cylinder(h = gasket_h + 0.2, d = lid_screw_d + 0.6);
  }
}

module hub_saddle() {
  hub_r = hub_diameter / 2;
  difference() {
    rounded_box([saddle_x, saddle_y, saddle_h], saddle_r);

    // Concave face. The case long axis and the hub axle are both X.
    translate([0, 0, hub_contact_depth - hub_r])
      rotate([0, 90, 0])
        cylinder(h = saddle_x + 2.0, r = hub_r, center = true);

    // Four slots: each pair accepts one 4 mm zip tie or elastic strap.
    for (sx = [-1, 1], sy = [-1, 1])
      translate([sx * strap_x, sy * strap_y, saddle_h / 2])
        cube([strap_width, strap_slot_y, saddle_h + 0.4], center = true);

    // Insert pockets open from the top. Screws are installed from inside the
    // enclosure before the electronics assembly is inserted.
    for (sx = [-1, 1])
      translate([sx * mount_x, 0, saddle_h - insert_depth])
        cylinder(h = insert_depth + 0.2, d = insert_hole_d);
  }
}

module electronics_dummy() {
  color([0.10, 0.45, 0.18, 0.75])
    translate([0, 0, bottom + support_rail_h])
      cube([assembly_x, assembly_y, assembly_z], center = false);
}

module assembled_preview() {
  color("DarkSlateGray") translate([0, 0, saddle_h]) hub_saddle();
  color([0.18, 0.42, 0.55]) translate([0, 0, saddle_h]) enclosure_body();
  color([0.10, 0.45, 0.18, 0.55])
    translate([-assembly_x / 2, -assembly_y / 2, saddle_h]) electronics_dummy();
  color("Orange")
    translate([0, 0, saddle_h + body_z]) lid_gasket();
  color([0.25, 0.55, 0.68, 0.72])
    translate([0, 0, saddle_h + body_z + gasket_h]) enclosure_lid();
}

if (part == "body") {
  enclosure_body();
} else if (part == "lid") {
  // Print the broad roof face on the build plate, with the skirt upward.
  translate([0, 0, lid_roof]) rotate([180, 0, 0]) enclosure_lid();
} else if (part == "gasket") {
  lid_gasket();
} else if (part == "saddle") {
  // Print the flat case-contact face on the build plate.
  translate([0, 0, saddle_h]) rotate([180, 0, 0]) hub_saddle();
} else {
  assembled_preview();
}
