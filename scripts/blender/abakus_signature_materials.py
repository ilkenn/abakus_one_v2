import bpy
import math

# Phase 2 assumes the Phase 1 geometry script has already been run in this
# session/file -- it looks up the existing Frame/Rods/Beads collections by
# name and only adds materials, UVs, modifiers and normals to them. No
# vertex, object-location, or dimension data is touched.

COLLECTION_FRAME = "Frame"
COLLECTION_RODS = "Rods"
COLLECTION_BEADS = "Beads"

BEAD_ROW_COLORS = {
    "WarmIvory": (0.86, 0.80, 0.68),
    "Sage": (0.61, 0.68, 0.55),
    "Olive": (0.46, 0.51, 0.27),
    "Terracotta": (0.72, 0.42, 0.27),
    "Stone": (0.66, 0.63, 0.57),
    "Forest": (0.20, 0.31, 0.22),
    "Sand": (0.80, 0.70, 0.52),
}
ROW_COLOR_ORDER = [
    "WarmIvory", "Sage", "Olive", "Terracotta", "Stone", "Forest", "Sand",
]

BEVEL_WIDTH = 0.0004
BEVEL_SEGMENTS = 3
BEVEL_ANGLE_LIMIT = math.radians(35)
SMOOTH_BY_ANGLE = math.radians(35)


# ============================================================
# MATERIALS
# ============================================================

def _bsdf_and_output(mat):
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    output = nodes.new("ShaderNodeOutputMaterial")
    output.location = (400, 0)
    mat.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return bsdf


def _set_coat(bsdf, weight, roughness, ior=1.5):
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = weight
        bsdf.inputs["Coat Roughness"].default_value = roughness
        if "Coat IOR" in bsdf.inputs:
            bsdf.inputs["Coat IOR"].default_value = ior
    elif "Clearcoat" in bsdf.inputs:
        bsdf.inputs["Clearcoat"].default_value = weight
        bsdf.inputs["Clearcoat Roughness"].default_value = roughness


def _set_subsurface(bsdf, weight, radius=(1.0, 1.0, 1.0)):
    if "Subsurface Weight" in bsdf.inputs:
        bsdf.inputs["Subsurface Weight"].default_value = weight
        if "Subsurface Radius" in bsdf.inputs:
            bsdf.inputs["Subsurface Radius"].default_value = radius
    elif "Subsurface" in bsdf.inputs:
        bsdf.inputs["Subsurface"].default_value = weight


def _set_ior(bsdf, ior):
    if "IOR" in bsdf.inputs:
        bsdf.inputs["IOR"].default_value = ior


def create_walnut_material():
    """Physically two-layered, like real finished walnut: a fairly matte
    wood body (Roughness ~0.42 -- raw wood is not glossy) underneath a
    thin, low-roughness Coat layer representing a satin lacquer/oil finish
    -- the coat is what actually reads as "premium finish," not a single
    medium-roughness surface. IOR 1.5 on both layers matches typical
    wood/lacquer dielectric reflectance."""
    mat = bpy.data.materials.new("Walnut_SmokedAmerican")
    bsdf = _bsdf_and_output(mat)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    tex_coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 34.0, 1.0)
    links.new(tex_coord.outputs["Object"], mapping.inputs["Vector"])

    # Finer, less "washy" grain than a single wave: a fine primary wave
    # (the fiber lines) with a coarser secondary wave mixed in at low
    # weight (broader tonal variation between fibers) -- real wood grain
    # reads as layered frequency detail, not one repeating stripe pitch.
    grain_wave = nodes.new("ShaderNodeTexWave")
    grain_wave.wave_type = 'BANDS'
    grain_wave.bands_direction = 'Y'
    grain_wave.inputs["Scale"].default_value = 14.0
    grain_wave.inputs["Distortion"].default_value = 2.2
    grain_wave.inputs["Detail"].default_value = 3.0
    grain_wave.inputs["Detail Scale"].default_value = 1.5
    links.new(mapping.outputs["Vector"], grain_wave.inputs["Vector"])

    broad_wave = nodes.new("ShaderNodeTexWave")
    broad_wave.wave_type = 'BANDS'
    broad_wave.bands_direction = 'Y'
    broad_wave.inputs["Scale"].default_value = 3.0
    broad_wave.inputs["Distortion"].default_value = 4.0
    broad_wave.inputs["Detail"].default_value = 2.0
    links.new(mapping.outputs["Vector"], broad_wave.inputs["Vector"])

    grain_mix = nodes.new("ShaderNodeMix")
    grain_mix.data_type = 'FLOAT'
    grain_mix.inputs["Factor"].default_value = 0.35
    links.new(grain_wave.outputs["Fac"], grain_mix.inputs[2])
    links.new(broad_wave.outputs["Fac"], grain_mix.inputs[3])

    grain_ramp = nodes.new("ShaderNodeValToRGB")
    grain_ramp.color_ramp.elements[0].color = (0.085, 0.048, 0.028, 1.0)
    grain_ramp.color_ramp.elements[1].color = (0.20, 0.115, 0.065, 1.0)
    links.new(grain_mix.outputs[0], grain_ramp.inputs["Fac"])
    links.new(grain_ramp.outputs["Color"], bsdf.inputs["Base Color"])

    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.06
    links.new(grain_mix.outputs[0], bump.inputs["Height"])
    links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])

    bsdf.inputs["Roughness"].default_value = 0.42
    bsdf.inputs["Metallic"].default_value = 0.0
    _set_ior(bsdf, 1.5)
    _set_coat(bsdf, weight=0.35, roughness=0.08, ior=1.5)
    return mat


def create_titanium_material():
    """Grade 5 titanium's real F0 reflectance is a slightly warm silver-grey
    (not pure white like chrome/aluminium) -- base color approximates the
    published measured reflectance. Brushed = pronounced Anisotropic
    highlight elongation along the brush direction (the rod's own length,
    via the Z-stretched mapping already used to orient the noise), and a
    matte-leaning roughness range per the brief's explicit "matte finish"
    (not a mirror-polished metal)."""
    mat = bpy.data.materials.new("Titanium_Grade5_Brushed")
    bsdf = _bsdf_and_output(mat)
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links

    tex_coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1.0, 1.0, 60.0)
    links.new(tex_coord.outputs["Object"], mapping.inputs["Vector"])

    brush_noise = nodes.new("ShaderNodeTexNoise")
    brush_noise.inputs["Scale"].default_value = 60.0
    brush_noise.inputs["Detail"].default_value = 2.0
    brush_noise.inputs["Roughness"].default_value = 0.6
    links.new(mapping.outputs["Vector"], brush_noise.inputs["Vector"])

    roughness_ramp = nodes.new("ShaderNodeValToRGB")
    roughness_ramp.color_ramp.elements[0].color = (0.30, 0.30, 0.30, 1.0)
    roughness_ramp.color_ramp.elements[1].color = (0.46, 0.46, 0.46, 1.0)
    links.new(brush_noise.outputs["Fac"], roughness_ramp.inputs["Fac"])
    links.new(roughness_ramp.outputs["Color"], bsdf.inputs["Roughness"])

    bsdf.inputs["Base Color"].default_value = (0.54, 0.51, 0.475, 1.0)
    bsdf.inputs["Metallic"].default_value = 1.0
    if "Anisotropic" in bsdf.inputs:
        bsdf.inputs["Anisotropic"].default_value = 0.7
        bsdf.inputs["Anisotropic Rotation"].default_value = 0.0
    return mat


def create_ceramic_materials():
    """Matte-glazed ceramic: a fairly low-roughness body (glaze is
    genuinely smoother than raw wood -- 0.30) plus a real Coat layer
    representing the thin glaze itself (moderate weight, low roughness,
    IOR ~1.55 -- typical for a ceramic glaze), and a very slight warm-tinted
    subsurface (real ceramic glaze has faint light scatter, never zero)."""
    materials = {}
    for name, color in BEAD_ROW_COLORS.items():
        mat = bpy.data.materials.new(f"Ceramic_{name}")
        bsdf = _bsdf_and_output(mat)
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.30
        bsdf.inputs["Metallic"].default_value = 0.0
        _set_ior(bsdf, 1.55)
        _set_coat(bsdf, weight=0.22, roughness=0.09, ior=1.55)
        _set_subsurface(bsdf, weight=0.025, radius=(0.9, 0.85, 0.75))
        materials[name] = mat
    return materials


# ============================================================
# UV MAPPING
# ============================================================

def unwrap_object(obj, method):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    if method == 'CUBE':
        bpy.ops.uv.cube_project(cube_size=1.0)
    elif method == 'CYLINDER':
        bpy.ops.uv.cylinder_project()
    elif method == 'SMART':
        bpy.ops.uv.smart_project(angle_limit=math.radians(66))
    bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')


# ============================================================
# MODIFIERS
# ============================================================

def add_bevel_modifier(obj):
    mod = obj.modifiers.new(name="Bevel", type='BEVEL')
    mod.width = BEVEL_WIDTH
    mod.segments = BEVEL_SEGMENTS
    mod.limit_method = 'ANGLE'
    mod.angle_limit = BEVEL_ANGLE_LIMIT
    mod.harden_normals = True
    return mod


def add_weighted_normal_modifier(obj):
    mod = obj.modifiers.new(name="WeightedNormal", type='WEIGHTED_NORMAL')
    mod.mode = 'FACE_AREA'
    mod.weight = 50
    mod.keep_sharp = True
    return mod


def apply_smooth_by_angle(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=SMOOTH_BY_ANGLE)
    except AttributeError:
        bpy.ops.object.shade_smooth()
    bpy.ops.object.select_all(action='DESELECT')


def finish_object(obj, uv_method):
    unwrap_object(obj, uv_method)
    apply_smooth_by_angle(obj)
    add_bevel_modifier(obj)
    add_weighted_normal_modifier(obj)


# ============================================================
# MAIN
# ============================================================

def main():
    frame_col = bpy.data.collections[COLLECTION_FRAME]
    rods_col = bpy.data.collections[COLLECTION_RODS]
    beads_col = bpy.data.collections[COLLECTION_BEADS]

    walnut = create_walnut_material()
    titanium = create_titanium_material()
    ceramics = create_ceramic_materials()

    for frame_obj in frame_col.objects:
        finish_object(frame_obj, uv_method='CUBE')
        frame_obj.data.materials.clear()
        frame_obj.data.materials.append(walnut)

    for rod_obj in rods_col.objects:
        finish_object(rod_obj, uv_method='CYLINDER')
        rod_obj.data.materials.clear()
        rod_obj.data.materials.append(titanium)

    # Rows are ordered the same way Phase 1 created them -- object name
    # encodes the row index ("ABAKUS_Bead_RowNN_..."), so color assignment
    # doesn't depend on collection iteration order.
    for bead_obj in beads_col.objects:
        row_index = int(bead_obj.name.split("_Row")[1][:2]) - 1
        color_name = ROW_COLOR_ORDER[row_index % len(ROW_COLOR_ORDER)]
        finish_object(bead_obj, uv_method='SMART')
        bead_obj.data.materials.clear()
        bead_obj.data.materials.append(ceramics[color_name])


if __name__ == "__main__":
    main()
