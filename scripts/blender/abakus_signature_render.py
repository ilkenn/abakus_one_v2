import bpy
import bmesh
import math
import os
from mathutils import Vector

# Phase 3 assumes Phase 1 (abakus_signature_geometry.py) and Phase 2
# (abakus_signature_materials.py) have already been run in this session.
# This script only adds scene-level elements (backdrop, lights, camera,
# render settings) and renders/saves output -- it never touches the
# Frame/Rods/Beads mesh data, object transforms, UVs, existing modifiers,
# or material node graphs created by Phases 1-2.

COLLECTION_FRAME = "Frame"
COLLECTION_RODS = "Rods"
COLLECTION_BEADS = "Beads"

OUTPUT_DIR = r"c:\Projects\abakus_one_v2\scripts\blender\output"
PNG_PATH = os.path.join(OUTPUT_DIR, "abakus_signature_review_v1.png")
BLEND_PATH = os.path.join(OUTPUT_DIR, "abakus_signature_master_v1.blend")

# ============================================================
# CONSTANTS
# ============================================================

# -- Cyclorama (floor -> smooth arc -> wall, seamless) --
BACKDROP_WIDTH = 0.9
BACKDROP_NEAR_Y = -0.55        # floor edge closest to camera
BACKDROP_ARC_START_Y = 0.15    # where the floor ends and the bend begins
BACKDROP_ARC_RADIUS = 0.35
BACKDROP_FLOOR_Z = -0.19       # just below the frame's outer bottom edge
BACKDROP_WALL_TOP_Z = 1.0
BACKDROP_ARC_SEGMENTS = 24
BACKDROP_WIDTH_SEGMENTS = 24
BACKDROP_COLOR = (0.93, 0.88, 0.78)
BACKDROP_ROUGHNESS = 0.75

# -- Lighting --
KEY_LIGHT_AZIMUTH_DEG = 45     # upper-left
KEY_LIGHT_ELEVATION_DEG = 45
KEY_LIGHT_DISTANCE = 0.9
KEY_LIGHT_SIZE = 1.1
KEY_LIGHT_ENERGY = 10
KEY_LIGHT_COLOR = (1.0, 0.94, 0.85)   # gentle warm daylight, not gold/orange

FILL_LIGHT_AZIMUTH_DEG = -50   # front-right (opposite side of key)
FILL_LIGHT_ELEVATION_DEG = 12
FILL_LIGHT_DISTANCE = 0.9
FILL_LIGHT_SIZE = 1.0
FILL_LIGHT_ENERGY = 2          # soft, roughly key:fill ~5:1 -- no harsh contrast
FILL_LIGHT_COLOR = (0.96, 0.97, 1.0)

RIM_LIGHT_AZIMUTH_DEG = 165    # behind, slightly off-axis
RIM_LIGHT_ELEVATION_DEG = 35
RIM_LIGHT_DISTANCE = 0.8
RIM_LIGHT_SIZE = 0.6
RIM_LIGHT_ENERGY = 1           # very subtle, separation only
RIM_LIGHT_COLOR = (1.0, 0.98, 0.95)

# A large, very low-energy light from below-front -- a physically-plausible
# stand-in for the bounce card every real product-photography setup uses
# to lift shadowed undersides (the frame's lower inner edge, the beads'
# lower hemisphere) without adding a second visible shadow direction.
BOUNCE_LIGHT_AZIMUTH_DEG = 0
BOUNCE_LIGHT_ELEVATION_DEG = -35
BOUNCE_LIGHT_DISTANCE = 0.7
BOUNCE_LIGHT_SIZE = 1.4
BOUNCE_LIGHT_ENERGY = 0.6
BOUNCE_LIGHT_COLOR = (1.0, 0.97, 0.92)

# -- Camera --
CAMERA_LENS_MM = 50
CAMERA_SENSOR_HEIGHT_MM = 24
CAMERA_DISTANCE = 1.05
CAMERA_AZIMUTH_DEG = 15        # three-quarter angle
CAMERA_ELEVATION_DEG = 9       # slightly above object center
CAMERA_TARGET = Vector((0, 0, 0.01))
# A mild aperture -- enough to add a whisper of background falloff (the
# cyclorama's far wall softens slightly) for "product photography" depth,
# never enough to blur the object itself, which sits at the focus distance.
CAMERA_APERTURE_FSTOP = 5.6

# -- Render --
RENDER_WIDTH = 1440
RENDER_HEIGHT = 2560
CYCLES_SAMPLES = 512


# ============================================================
# VERIFICATION SNAPSHOT (before touching anything)
# ============================================================

def snapshot_locked_state():
    frame_obj = bpy.data.collections[COLLECTION_FRAME].objects[0]
    rod_objs = list(bpy.data.collections[COLLECTION_RODS].objects)
    bead_objs = list(bpy.data.collections[COLLECTION_BEADS].objects)
    return {
        "frame_verts": [tuple(v.co) for v in frame_obj.data.vertices],
        "rod_verts": {o.name: [tuple(v.co) for v in o.data.vertices] for o in rod_objs},
        "bead_verts": {o.name: [tuple(v.co) for v in o.data.vertices] for o in bead_objs},
        # Phase 1/2 material names -- Phase 3 is explicitly allowed to add
        # its own new backdrop material, so this is a "still present and
        # unchanged" check, not a "set is identical" check.
        "material_names": sorted(m.name for m in bpy.data.materials),
        "object_locations": {o.name: tuple(o.location) for o in bpy.data.objects},
    }


def verify_locked_state_unchanged(before):
    frame_obj = bpy.data.collections[COLLECTION_FRAME].objects[0]
    rod_objs = list(bpy.data.collections[COLLECTION_RODS].objects)
    bead_objs = list(bpy.data.collections[COLLECTION_BEADS].objects)

    verts_ok = (
        [tuple(v.co) for v in frame_obj.data.vertices] == before["frame_verts"]
        and {o.name: [tuple(v.co) for v in o.data.vertices] for o in rod_objs}
        == before["rod_verts"]
        and {o.name: [tuple(v.co) for v in o.data.vertices] for o in bead_objs}
        == before["bead_verts"]
    )

    after_materials = set(m.name for m in bpy.data.materials)
    materials_ok = set(before["material_names"]).issubset(after_materials)

    locations_ok = all(
        tuple(bpy.data.objects[name].location) == loc
        for name, loc in before["object_locations"].items()
        if name in bpy.data.objects
    )

    return verts_ok and materials_ok and locations_ok


# ============================================================
# CYCLORAMA (smooth floor -> arc -> wall, no seam)
# ============================================================

def backdrop_profile_points():
    """Ordered (y, z) points: horizontal floor, a quarter-circle arc with
    matching tangents at both ends (C1-continuous -- no visible seam), then
    a vertical wall."""
    points = [(BACKDROP_NEAR_Y, BACKDROP_FLOOR_Z),
              (BACKDROP_ARC_START_Y, BACKDROP_FLOOR_Z)]

    for i in range(1, BACKDROP_ARC_SEGMENTS + 1):
        t = i / BACKDROP_ARC_SEGMENTS
        angle = t * math.pi / 2
        y = BACKDROP_ARC_START_Y + BACKDROP_ARC_RADIUS * math.sin(angle)
        z = BACKDROP_FLOOR_Z + BACKDROP_ARC_RADIUS * (1 - math.cos(angle))
        points.append((y, z))

    wall_y = BACKDROP_ARC_START_Y + BACKDROP_ARC_RADIUS
    wall_bottom_z = BACKDROP_FLOOR_Z + BACKDROP_ARC_RADIUS
    points.append((wall_y, BACKDROP_WALL_TOP_Z))
    del wall_bottom_z
    return points


def build_cyclorama():
    profile = backdrop_profile_points()
    xs = [-BACKDROP_WIDTH / 2 + BACKDROP_WIDTH * i / BACKDROP_WIDTH_SEGMENTS
          for i in range(BACKDROP_WIDTH_SEGMENTS + 1)]

    bm = bmesh.new()
    grid = []
    for x in xs:
        column = [bm.verts.new((x, y, z)) for y, z in profile]
        grid.append(column)

    for xi in range(len(xs) - 1):
        for pi in range(len(profile) - 1):
            v1 = grid[xi][pi]
            v2 = grid[xi + 1][pi]
            v3 = grid[xi + 1][pi + 1]
            v4 = grid[xi][pi + 1]
            bm.faces.new((v1, v2, v3, v4))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    mesh = bpy.data.meshes.new("Cyclorama")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new("Cyclorama", mesh)
    bpy.context.scene.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(40))
    except AttributeError:
        bpy.ops.object.shade_smooth()
    bpy.ops.object.select_all(action='DESELECT')

    mat = bpy.data.materials.new("Backdrop_WarmCream")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*BACKDROP_COLOR, 1.0)
    bsdf.inputs["Roughness"].default_value = BACKDROP_ROUGHNESS
    bsdf.inputs["Metallic"].default_value = 0.0
    obj.data.materials.append(mat)

    return obj


# ============================================================
# LIGHTING
# ============================================================

def _polar_position(distance, azimuth_deg, elevation_deg):
    az = math.radians(azimuth_deg)
    el = math.radians(elevation_deg)
    x = distance * math.sin(az) * math.cos(el)
    y = -distance * math.cos(az) * math.cos(el)
    z = distance * math.sin(el)
    return Vector((x, y, z))


def _add_area_light(name, distance, azimuth_deg, elevation_deg, size, energy, color):
    location = _polar_position(distance, azimuth_deg, elevation_deg)
    bpy.ops.object.light_add(type='AREA', location=location)
    light = bpy.context.active_object
    light.name = name
    light.data.size = size
    light.data.energy = energy
    light.data.color = color
    direction = Vector((0, 0, 0)) - location
    light.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()
    return light


def build_lighting():
    key = _add_area_light(
        "Light_Key", KEY_LIGHT_DISTANCE, KEY_LIGHT_AZIMUTH_DEG,
        KEY_LIGHT_ELEVATION_DEG, KEY_LIGHT_SIZE, KEY_LIGHT_ENERGY, KEY_LIGHT_COLOR,
    )
    fill = _add_area_light(
        "Light_Fill", FILL_LIGHT_DISTANCE, FILL_LIGHT_AZIMUTH_DEG,
        FILL_LIGHT_ELEVATION_DEG, FILL_LIGHT_SIZE, FILL_LIGHT_ENERGY, FILL_LIGHT_COLOR,
    )
    rim = _add_area_light(
        "Light_Rim", RIM_LIGHT_DISTANCE, RIM_LIGHT_AZIMUTH_DEG,
        RIM_LIGHT_ELEVATION_DEG, RIM_LIGHT_SIZE, RIM_LIGHT_ENERGY, RIM_LIGHT_COLOR,
    )
    bounce = _add_area_light(
        "Light_Bounce", BOUNCE_LIGHT_DISTANCE, BOUNCE_LIGHT_AZIMUTH_DEG,
        BOUNCE_LIGHT_ELEVATION_DEG, BOUNCE_LIGHT_SIZE, BOUNCE_LIGHT_ENERGY,
        BOUNCE_LIGHT_COLOR,
    )
    return [key, fill, rim, bounce]


# ============================================================
# CAMERA
# ============================================================

def build_camera():
    location = CAMERA_TARGET + _polar_position(
        CAMERA_DISTANCE, CAMERA_AZIMUTH_DEG, CAMERA_ELEVATION_DEG,
    )
    bpy.ops.object.camera_add(location=location)
    camera = bpy.context.active_object
    camera.name = "Camera_Review"
    camera.data.lens = CAMERA_LENS_MM
    camera.data.sensor_fit = 'VERTICAL'
    camera.data.sensor_height = CAMERA_SENSOR_HEIGHT_MM

    direction = CAMERA_TARGET - location
    camera.rotation_euler = direction.to_track_quat('-Z', 'Y').to_euler()

    camera.data.dof.use_dof = True
    camera.data.dof.focus_distance = CAMERA_DISTANCE
    camera.data.dof.aperture_fstop = CAMERA_APERTURE_FSTOP
    camera.data.dof.aperture_blades = 6

    bpy.context.scene.camera = camera
    return camera


# ============================================================
# RENDER SETTINGS
# ============================================================

def configure_render():
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.render.resolution_x = RENDER_WIDTH
    scene.render.resolution_y = RENDER_HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = 'PNG'

    scene.cycles.samples = CYCLES_SAMPLES
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.005
    scene.cycles.use_denoising = True
    scene.cycles.denoiser = 'OPENIMAGEDENOISE'
    scene.cycles.denoising_prefilter = 'ACCURATE'
    scene.cycles.denoising_use_gpu = True

    # Extra light-path depth for the reflective/coated materials (brushed
    # titanium, lacquered walnut, glazed ceramic) to resolve accurately --
    # the default bounce counts under-resolve inter-reflection between the
    # rods and the frame's inner wall.
    scene.cycles.max_bounces = 12
    scene.cycles.diffuse_bounces = 6
    scene.cycles.glossy_bounces = 6
    scene.cycles.transmission_bounces = 6
    scene.cycles.caustics_reflective = False
    scene.cycles.caustics_refractive = False
    scene.cycles.blur_glossy = 0.5

    # AgX (Blender's default view transform) desaturates warm/bright tones
    # significantly by design -- it was reading the warm-cream backdrop and
    # ceramic bead colors as flat grey rather than warm. Standard preserves
    # the actual material colors accurately for this moderate-key product
    # shot, matching "neutral and realistic material response."
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.exposure = 0.0
    scene.view_settings.look = 'None'

    try:
        prefs = bpy.context.preferences.addons['cycles'].preferences
        prefs.compute_device_type = 'OPTIX'
        prefs.get_devices()
        gpu_available = any(d.type == 'OPTIX' for d in prefs.devices)
        if gpu_available:
            for d in prefs.devices:
                d.use = (d.type == 'OPTIX')
            scene.cycles.device = 'GPU'
        else:
            scene.cycles.device = 'CPU'
    except Exception as e:
        print(f"[abakus-render] GPU setup unavailable, using CPU: {e}")
        scene.cycles.device = 'CPU'

    print(f"[abakus-render] Cycles device: {scene.cycles.device}")


def render_review_image():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.context.scene.render.filepath = PNG_PATH
    bpy.ops.render.render(write_still=True)
    return PNG_PATH


def save_master_blend():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    return BLEND_PATH


# ============================================================
# MAIN
# ============================================================

def main():
    before = snapshot_locked_state()

    build_cyclorama()
    build_lighting()
    build_camera()
    configure_render()

    png_path = render_review_image()
    blend_path = save_master_blend()

    unchanged = verify_locked_state_unchanged(before)

    camera_exists = bpy.context.scene.camera is not None
    light_names = [o.name for o in bpy.data.objects if o.type == 'LIGHT']
    render_result = bpy.data.images.get("Render Result")
    png_on_disk = os.path.isfile(png_path)

    print("=== PHASE 3 REPORT ===")
    print(f"camera exists: {camera_exists} ({bpy.context.scene.camera.name if camera_exists else None})")
    print(f"lights exist: {sorted(light_names)}")
    print(f"render completed: {png_on_disk}")
    print(f"PNG path: {png_path}")
    if png_on_disk:
        img = bpy.data.images.load(png_path)
        print(f"PNG dimensions: {img.size[0]}x{img.size[1]}")
        bpy.data.images.remove(img)
    print(f"blend path: {blend_path} (exists: {os.path.isfile(blend_path)})")
    print(f"geometry/material/location unchanged: {unchanged}")


if __name__ == "__main__":
    main()
