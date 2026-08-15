import bpy
import bmesh
import math

# ============================================================
# CONSTANTS (mm, converted to meters for Blender)
# ============================================================

MM = 0.001

FRAME_OUTER_WIDTH = 210 * MM
FRAME_OUTER_HEIGHT = 280 * MM
# Phase 4: reduced from 22mm (~-18%) -- external dimensions, corner radii,
# and depth are unchanged; only the border width narrows, which widens the
# inner opening automatically (both derive inner_width/inner_height as
# FRAME_OUTER_* - 2*FRAME_THICKNESS below, nothing else to update).
FRAME_THICKNESS = 18 * MM      # border width (outer edge -> inner opening)
FRAME_DEPTH = 28 * MM          # front-to-back extrusion depth
FRAME_OUTER_CORNER_RADIUS = 26 * MM
FRAME_INNER_CORNER_RADIUS = 12 * MM
FRAME_CORNER_SEGMENTS = 12     # per corner, arc smoothness

ROD_COUNT = 7
ROD_DIAMETER = 4 * MM
ROD_RADIUS = ROD_DIAMETER / 2
ROD_SEGMENTS = 24

BEAD_ROWS = 7
BEADS_PER_ROW = 7
# Phase 4: increased from 14mm. build_rods()/build_beads() both derive
# their span from inner_width, which itself already reflects the updated
# FRAME_THICKNESS above -- rod length and bead centering/margins follow
# automatically, no other constant needs to change.
BEAD_DIAMETER = 18 * MM
BEAD_RADIUS = BEAD_DIAMETER / 2
BEAD_FLATTEN_Z = 0.9
BEAD_SEGMENTS = 32
BEAD_RINGS = 16

COLLECTION_ROOT = "ABAKUS_SIGNATURE_OBJECT"
COLLECTION_FRAME = "Frame"
COLLECTION_RODS = "Rods"
COLLECTION_BEADS = "Beads"


# ============================================================
# COLLECTIONS
# ============================================================

def get_or_create_collection(name, parent):
    if name in bpy.data.collections:
        col = bpy.data.collections[name]
    else:
        col = bpy.data.collections.new(name)
    if col.name not in parent.children:
        parent.children.link(col)
    return col


def build_collection_hierarchy():
    root = get_or_create_collection(COLLECTION_ROOT, bpy.context.scene.collection)
    frame_col = get_or_create_collection(COLLECTION_FRAME, root)
    rods_col = get_or_create_collection(COLLECTION_RODS, root)
    beads_col = get_or_create_collection(COLLECTION_BEADS, root)
    return root, frame_col, rods_col, beads_col


def move_to_collection(obj, collection):
    for col in list(obj.users_collection):
        col.objects.unlink(obj)
    collection.objects.link(obj)


# ============================================================
# GEOMETRY HELPERS
# ============================================================

def rounded_rect_loop(width, height, radius, segments_per_corner):
    """CCW list of (x, z) points tracing a rounded rectangle, centered at origin."""
    hw, hh = width / 2, height / 2
    radius = min(radius, hw, hh)
    corners = [
        (hw - radius, hh - radius, 0.0),
        (-hw + radius, hh - radius, 90.0),
        (-hw + radius, -hh + radius, 180.0),
        (hw - radius, -hh + radius, 270.0),
    ]
    points = []
    for cx, cz, start_deg in corners:
        for i in range(segments_per_corner):
            angle = math.radians(start_deg + 90.0 * i / segments_per_corner)
            points.append((cx + radius * math.cos(angle),
                            cz + radius * math.sin(angle)))
    return points


def new_object_from_bmesh(bm, name):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


# ============================================================
# FRAME (built as a manifold quad ring -- no booleans)
# ============================================================

def build_frame():
    outer_pts = rounded_rect_loop(
        FRAME_OUTER_WIDTH, FRAME_OUTER_HEIGHT,
        FRAME_OUTER_CORNER_RADIUS, FRAME_CORNER_SEGMENTS,
    )
    inner_width = FRAME_OUTER_WIDTH - 2 * FRAME_THICKNESS
    inner_height = FRAME_OUTER_HEIGHT - 2 * FRAME_THICKNESS
    inner_pts = rounded_rect_loop(
        inner_width, inner_height,
        FRAME_INNER_CORNER_RADIUS, FRAME_CORNER_SEGMENTS,
    )

    n = len(outer_pts)
    half_depth = FRAME_DEPTH / 2

    bm = bmesh.new()

    outer_front = [bm.verts.new((x, -half_depth, z)) for x, z in outer_pts]
    inner_front = [bm.verts.new((x, -half_depth, z)) for x, z in inner_pts]
    outer_back = [bm.verts.new((x, half_depth, z)) for x, z in outer_pts]
    inner_back = [bm.verts.new((x, half_depth, z)) for x, z in inner_pts]

    def ring_quads(loop_a, loop_b, flip=False):
        for i in range(n):
            j = (i + 1) % n
            verts = [loop_a[i], loop_b[i], loop_b[j], loop_a[j]]
            if flip:
                verts.reverse()
            bm.faces.new(verts)

    # Flat front face (between outer and inner boundary, facing -Y).
    ring_quads(outer_front, inner_front, flip=True)
    # Flat back face (facing +Y).
    ring_quads(outer_back, inner_back, flip=False)
    # Outer side wall.
    ring_quads(outer_front, outer_back, flip=False)
    # Inner side wall (the opening's inner surface).
    ring_quads(inner_front, inner_back, flip=True)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-8)

    obj = new_object_from_bmesh(bm, "ABAKUS_Frame")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.shade_smooth()
    bpy.ops.object.select_all(action='DESELECT')
    return obj


# ============================================================
# RODS
# ============================================================

def build_rods():
    inner_width = FRAME_OUTER_WIDTH - 2 * FRAME_THICKNESS
    inner_height = FRAME_OUTER_HEIGHT - 2 * FRAME_THICKNESS
    row_spacing = inner_height / (ROD_COUNT + 1)
    top = inner_height / 2

    rods = []
    for i in range(ROD_COUNT):
        z = top - row_spacing * (i + 1)
        bpy.ops.mesh.primitive_cylinder_add(
            radius=ROD_RADIUS,
            depth=inner_width,
            vertices=ROD_SEGMENTS,
            location=(0, 0, z),
            rotation=(0, math.radians(90), 0),
        )
        rod = bpy.context.active_object
        rod.name = f"ABAKUS_Rod_{i + 1:02d}"
        bpy.ops.object.shade_smooth()
        rods.append(rod)
    return rods


# ============================================================
# BEADS
# ============================================================

def build_beads(rods):
    inner_width = FRAME_OUTER_WIDTH - 2 * FRAME_THICKNESS
    span = inner_width - BEAD_DIAMETER
    step = span / (BEADS_PER_ROW - 1)
    start_x = -span / 2

    beads = []
    for row, rod in enumerate(rods):
        z = rod.location.z
        for col in range(BEADS_PER_ROW):
            x = start_x + step * col
            bpy.ops.mesh.primitive_uv_sphere_add(
                radius=BEAD_RADIUS,
                segments=BEAD_SEGMENTS,
                ring_count=BEAD_RINGS,
                location=(x, 0, z),
            )
            bead = bpy.context.active_object
            bead.scale.z = BEAD_FLATTEN_Z
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            bead.name = f"ABAKUS_Bead_Row{row + 1:02d}_{col + 1:02d}"
            bpy.ops.object.shade_smooth()
            beads.append(bead)
    return beads


# ============================================================
# MAIN
# ============================================================

def main():
    root, frame_col, rods_col, beads_col = build_collection_hierarchy()

    frame = build_frame()
    move_to_collection(frame, frame_col)

    rods = build_rods()
    for rod in rods:
        move_to_collection(rod, rods_col)

    beads = build_beads(rods)
    for bead in beads:
        move_to_collection(bead, beads_col)


if __name__ == "__main__":
    main()
