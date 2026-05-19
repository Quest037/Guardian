# Cursor Build Prompt: Procedural Terrain Heightmaps for Gazebo Sims

## Goal

Build **Version 1** of a procedural terrain system for our simulation app.

The app already creates flat Gazebo maps with these base sizes:

| App size | World dimensions | Area |
|---|---:|---:|
| `small` | `1000 m x 1000 m` | `1 km²` |
| `medium` | `2000 m x 2000 m` | `4 km² footprint, 2 km side length` |
| `large` | `4000 m x 4000 m` | `16 km² footprint, 4 km side length` |

Note: the product language may currently call these `1km2 / 2km2 / 4km2`. For implementation, use the **side length in meters** as the source of truth. If the existing app means area instead of side length, add a conversion layer but keep the terrain generator API based on `world_size_m`.

Version 1 must generate terrain procedurally from a compact JSON request such as:

```json
{
  "type": "canyon",
  "size": "medium",
  "seed": 42,
  "resolution": 2049,
  "params": {
    "depth_m": 80,
    "width_m": 180,
    "sinuosity": 0.7,
    "rim_height_m": 15,
    "roughness": 0.35
  }
}
```

The generator must output:

```text
generated_terrain/
  model.config
  model.sdf
  materials/
    textures/
      heightmap.png
      albedo.png              # optional v1 placeholder
      normal.png              # optional v1 placeholder
  metadata.json
  preview.png                 # optional but recommended
```

The generated terrain must work in Gazebo as:

1. A visible terrain surface.
2. A collision surface for UGVs, UAVs, sensors, wheels, landing gear, and physics.
3. A queryable terrain model for our app/autonomy stack:
   - `height_at(x, y)`
   - `normal_at(x, y)`
   - `slope_at(x, y)`
   - `is_traversable(x, y, vehicle_profile)`
   - `min_safe_altitude(x, y, min_agl)`

Do **not** build a general terrain editor in v1. Build a deterministic preset-based generator that supports:

```text
flat
rugged
low_hills
high_hills
mountain
valley
canyon
crater
```

---

## Hard Requirements

### R1. Use heightmaps for v1

Use a single-valued terrain surface:

```text
z = f(x, y)
```

Use Gazebo / SDFormat `<heightmap>` geometry for both:

```text
visual geometry
collision geometry
```

Do not use arbitrary mesh terrain in v1.

Reason: heightmaps are enough for flat terrain, hills, mountains, valleys, canyons, and craters. Meshes are only required for caves, overhangs, bridges, vertical walls, tunnels, or manually authored art terrain.

### R2. Deterministic seeding

Every generated terrain must be reproducible.

The same request must produce the same:

```text
heightmap.png
model.sdf
metadata.json
```

Seed rules:

```text
if request.seed exists:
  use request.seed
else:
  generate a random uint32 seed
  store it in metadata.json
```

Use a local RNG object. Do not use global random state.

### R3. Use 16-bit grayscale heightmap

Export `heightmap.png` as 16-bit grayscale.

The image maps:

```text
black pixel   -> min_z_m
white pixel   -> max_z_m
gray pixel    -> linear interpolation between min_z_m and max_z_m
```

Do not export 8-bit heightmaps for v1 because banding becomes visible at large terrain scale.

### R4. Same heightmap parameters for collision and visual

The `<visual>` and `<collision>` heightmaps must use the same:

```text
uri
size
pos
sampling
```

Visual/collision mismatch is a failure.

### R5. Terrain metadata is required

Write `metadata.json` with all data needed to query the terrain outside Gazebo.

Minimum metadata:

```json
{
  "schema_version": 1,
  "type": "canyon",
  "size": "medium",
  "world_size_m": 2000,
  "resolution": 2049,
  "seed": 42,
  "min_z_m": -82.4,
  "max_z_m": 21.7,
  "height_range_m": 104.1,
  "heightmap_uri": "model://generated_terrain/materials/textures/heightmap.png",
  "sdf_path": "model.sdf",
  "params": {},
  "coordinate_frame": {
    "origin": "center",
    "x_range_m": [-1000, 1000],
    "y_range_m": [-1000, 1000],
    "z_units": "meters"
  }
}
```

### R6. Coordinate convention

Use this convention everywhere:

```text
terrain center is at world origin
x range = [-world_size_m / 2, world_size_m / 2]
y range = [-world_size_m / 2, world_size_m / 2]
z is meters above/below local terrain zero
```

Image indexing:

```text
heightmap[row, col]
row maps to y
col maps to x
```

For v1, use a simple mapping:

```python
x = -half + col / (resolution - 1) * world_size_m
y = -half + row / (resolution - 1) * world_size_m
```

### R7. Clamp and smooth terrain

After generating the terrain:

1. Apply optional smoothing.
2. Clamp to configured min/max if needed.
3. Normalize for 16-bit PNG.
4. Store real `min_z_m` and `max_z_m` in metadata.

Do not normalize early. Generate in meters first.

### R8. Spawn robots above terrain

When spawning any robot:

```text
spawn_z = height_at(spawn_x, spawn_y) + clearance_m
```

Recommended default clearances:

```text
UGV: 0.25 m to 0.75 m depending on wheel radius
UAV on ground: landing gear height + 0.05 m
UAV in air: requested AGL altitude + terrain.height_at(x, y)
```

---

## Recommended Project Structure

Create a new module/package in the app:

```text
terrain/
  __init__.py
  models.py
  presets.py
  noise.py
  generator.py
  export_heightmap.py
  export_sdf.py
  terrain_query.py
  gazebo_spawn.py
  tests/
    test_determinism.py
    test_height_queries.py
    test_sdf_generation.py
    test_presets.py
```

If the app is TypeScript/Node rather than Python, use the same structure conceptually:

```text
terrain/
  models.ts
  presets.ts
  noise.ts
  generator.ts
  exportHeightmap.ts
  exportSdf.ts
  terrainQuery.ts
  gazeboSpawn.ts
```

The implementation examples below are Python-like pseudocode, but the logic is mandatory.

---

## Terrain Request Schema

Define this request object.

```ts
type TerrainType =
  | "flat"
  | "rugged"
  | "low_hills"
  | "high_hills"
  | "mountain"
  | "valley"
  | "canyon"
  | "crater";

type TerrainSize = "small" | "medium" | "large";

interface TerrainRequest {
  type: TerrainType;
  size: TerrainSize;
  seed?: number;
  resolution?: number;
  params?: Record<string, number | boolean | string>;
}
```

Default size mapping:

```ts
const SIZE_TO_WORLD_METERS = {
  small: 1000,
  medium: 2000,
  large: 4000
};
```

Default resolution:

```ts
const SIZE_TO_DEFAULT_RESOLUTION = {
  small: 1025,
  medium: 2049,
  large: 2049
};
```

Allow override:

```text
resolution may be 513, 1025, 2049, or 4097
```

Validation:

```text
resolution must be odd
resolution must be >= 257
resolution must be <= 4097 for v1
```

---

## Terrain Presets and Inputs

Each type has required inputs, optional inputs, and defaults.

The app can expose only `type`, `size`, and `seed` in the UI at first. All other inputs get defaults.

### 1. `flat`

Purpose:

```text
Completely flat baseline terrain.
```

Inputs:

| Input | Required | Default | Meaning |
|---|---:|---:|---|
| `elevation_m` | no | `0` | Constant terrain elevation |
| `micro_noise_m` | no | `0` | Optional tiny texture-like elevation variation |

Build logic:

```python
Z = full_grid(elevation_m)

if micro_noise_m > 0:
    Z += smooth_noise(seed) * micro_noise_m
```

Default params:

```json
{
  "elevation_m": 0,
  "micro_noise_m": 0
}
```

Expected result:

```text
All vehicles behave as they do today.
```

---

### 2. `rugged`

Purpose:

```text
Uneven off-road terrain with roughness but no single dominant mountain/valley feature.
```

Inputs:

| Input | Required | Default | Meaning |
|---|---:|---:|---|
| `amplitude_m` | no | `25` | Maximum broad elevation swing |
| `roughness` | no | `0.7` | Noise intensity |
| `feature_scale_m` | no | `180` | Approximate horizontal size of large bumps |
| `detail_scale_m` | no | `35` | Approximate horizontal size of small bumps |
| `smoothing_passes` | no | `2` | Post smoothing |

Build logic:

```python
large = fbm_noise(scale=feature_scale_m, octaves=4)
small = fbm_noise(scale=detail_scale_m, octaves=3)

Z = amplitude_m * (
    0.75 * large +
    0.25 * roughness * small
)

Z = smooth(Z, smoothing_passes)
Z -= mean(Z)
```

Default params:

```json
{
  "amplitude_m": 25,
  "roughness": 0.7,
  "feature_scale_m": 180,
  "detail_scale_m": 35,
  "smoothing_passes": 2
}
```

---

### 3. `low_hills`

Purpose:

```text
Gentle rolling terrain suitable for most UGVs.
```

Inputs:

| Input | Required | Default | Meaning |
|---|---:|---:|---|
| `amplitude_m` | no | `18` | Hill height |
| `hill_scale_m` | no | `300` | Average hill width |
| `roughness` | no | `0.25` | Minor irregularity |
| `smoothing_passes` | no | `4` | Smooth terrain |

Build logic:

```python
base = fbm_noise(scale=hill_scale_m, octaves=4)
detail = fbm_noise(scale=hill_scale_m / 4, octaves=2)

Z = amplitude_m * (0.9 * base + 0.1 * roughness * detail)
Z = smooth(Z, smoothing_passes)
Z -= mean(Z)
```

Default params:

```json
{
  "amplitude_m": 18,
  "hill_scale_m": 300,
  "roughness": 0.25,
  "smoothing_passes": 4
}
```

---

### 4. `high_hills`

Purpose:

```text
Large hills with meaningful slopes and line-of-sight variation.
```

Inputs:

| Input | Required | Default | Meaning |
|---|---:|---:|---|
| `amplitude_m` | no | `55` | Hill height |
| `hill_scale_m` | no | `450` | Average hill width |
| `roughness` | no | `0.4` | Surface irregularity |
| `ridge_bias` | no | `0.25` | How ridge-like the hills become |
| `smoothing_passes` | no | `3` | Smooth terrain |

Build logic:

```python
base = fbm_noise(scale=hill_scale_m, octaves=5)
ridge = 1.0 - abs(fbm_noise(scale=hill_scale_m * 0.8, octaves=4))

Z = amplitude_m * (
    (1.0 - ridge_bias) * base +
    ridge_bias * ridge
)

Z += amplitude_m * 0.1 * roughness * fbm_noise(scale=80, octaves=2)
Z = smooth(Z, smoothing_passes)
Z -= mean(Z)
```

Default params:

```json
{
  "amplitude_m": 55,
  "hill_scale_m": 450,
  "roughness": 0.4,
  "ridge_bias": 0.25,
  "smoothing_passes": 3
}
```

---

### 5. `mountain`

Purpose:

```text
One or more dominant peaks, ridges, steep slopes, and rough high terrain.
```

Inputs:

| Input | Required | Default | Meaning |
|---|---:|---:|---|
| `peak_height_m` | no | `220` | Height of main mountain |
| `base_radius_m` | no | `world_size_m * 0.32` | Mountain footprint radius |
| `peak_count` | no | `1` | Number of primary peaks |
| `ridge_strength` | no | `0.45` | Ridge contribution |
| `roughness` | no | `0.5` | Rockiness |
| `smoothing_passes` | no | `2` | Smooth terrain |

Build logic:

```python
Z = zeros()

for each peak:
    cx, cy = seeded random location near center
    r = distance((X, Y), (cx, cy))
    cone = peak_height_m * exp(-(r / base_radius_m) ** 2)
    Z += cone

ridge = 1.0 - abs(fbm_noise(scale=world_size_m * 0.18, octaves=5))
Z += ridge_strength * peak_height_m * ridge

rough = fbm_noise(scale=70, octaves=4)
Z += roughness * 25 * rough

Z = smooth(Z, smoothing_passes)
Z -= percentile(Z, 5)
```

Default params:

```json
{
  "peak_height_m": 220,
  "base_radius_m": null,
  "peak_count": 1,
  "ridge_strength": 0.45,
  "roughness": 0.5,
  "smoothing_passes": 2
}
```

Validation:

```text
peak_count min = 1
peak_count max = 5
```

---

### 6. `valley`

Purpose:

```text
A broad valley through the map, suitable for UGV traversal and UAV low-altitude route testing.
```

Inputs:

| Input | Required | Default | Meaning |
|---|---:|---:|---|
| `depth_m` | no | `45` | Valley depth below surrounding terrain |
| `width_m` | no | `world_size_m * 0.22` | Valley width |
| `sinuosity` | no | `0.35` | How much the valley winds |
| `floor_width_m` | no | `world_size_m * 0.08` | Flatter center floor |
| `side_roughness` | no | `0.25` | Slope irregularity |
| `orientation_deg` | no | `0` | Valley direction |

Build logic:

```python
# Rotate X/Y by orientation.
Xr, Yr = rotate(X, Y, orientation_deg)

# Create winding centerline.
centerline = sinuosity * width_m * sin(2*pi*Xr/world_size_m * 1.3 + phase)

d = abs(Yr - centerline)

# Smooth U-shaped valley.
valley_cut = -depth_m * exp(-(d / width_m) ** 2)

# Flatten valley floor.
floor_mask = smoothstep(floor_width_m, floor_width_m * 1.6, d)
Z = valley_cut * floor_mask + (-depth_m) * (1 - floor_mask)

# Add gentle outside terrain.
Z += side_roughness * 10 * fbm_noise(scale=220, octaves=3)
Z = smooth(Z, 3)
```

Default params:

```json
{
  "depth_m": 45,
  "width_m": null,
  "sinuosity": 0.35,
  "floor_width_m": null,
  "side_roughness": 0.25,
  "orientation_deg": 0
}
```

---

### 7. `canyon`

Purpose:

```text
A narrower, deeper valley with steeper sides and raised rims.
```

Inputs:

| Input | Required | Default | Meaning |
|---|---:|---:|---|
| `depth_m` | no | `90` | Canyon depth |
| `width_m` | no | `world_size_m * 0.09` | Canyon half-width-ish |
| `sinuosity` | no | `0.65` | Canyon winding |
| `rim_height_m` | no | `18` | Raised rims along both sides |
| `floor_width_m` | no | `world_size_m * 0.025` | Bottom channel width |
| `wall_steepness` | no | `2.6` | Larger means steeper walls |
| `roughness` | no | `0.35` | Wall noise |
| `orientation_deg` | no | `0` | Canyon direction |

Build logic:

```python
Xr, Yr = rotate(X, Y, orientation_deg)

phase = rng.uniform(0, 2*pi)
centerline = (
    sinuosity * width_m * sin(2*pi*Xr/world_size_m * 1.2 + phase)
    + 0.35 * sinuosity * width_m * sin(2*pi*Xr/world_size_m * 2.7 + phase * 0.7)
)

d = abs(Yr - centerline)

# Deep cut.
cut = -depth_m * exp(-((d / width_m) ** wall_steepness))

# Flatten bottom channel.
floor_mask = smoothstep(floor_width_m, floor_width_m * 1.8, d)
Z = cut * floor_mask + (-depth_m) * (1 - floor_mask)

# Raised rims.
rim_center = width_m * 1.15
rim_sigma = width_m * 0.22
rims = rim_height_m * exp(-((d - rim_center) / rim_sigma) ** 2)
Z += rims

# Wall / floor roughness.
wall_weight = smoothstep(floor_width_m, width_m * 1.5, d)
Z += roughness * 12 * wall_weight * fbm_noise(scale=55, octaves=3)

# Gentle surrounding plateau variation.
Z += 5 * fbm_noise(scale=350, octaves=2)

Z = smooth(Z, 1)
```

Default params:

```json
{
  "depth_m": 90,
  "width_m": null,
  "sinuosity": 0.65,
  "rim_height_m": 18,
  "floor_width_m": null,
  "wall_steepness": 2.6,
  "roughness": 0.35,
  "orientation_deg": 0
}
```

Important v1 limitation:

```text
A heightmap canyon cannot have overhangs or vertical walls.
```

Do not attempt true vertical canyon walls in v1.

---

### 8. `crater`

Purpose:

```text
Circular depression with raised rim.
```

Inputs:

| Input | Required | Default | Meaning |
|---|---:|---:|---|
| `radius_m` | no | `world_size_m * 0.22` | Crater radius |
| `depth_m` | no | `70` | Crater depth |
| `rim_height_m` | no | `22` | Rim height |
| `rim_width_m` | no | `radius_m * 0.18` | Rim thickness |
| `center_offset_x_m` | no | `0` | Crater center x offset |
| `center_offset_y_m` | no | `0` | Crater center y offset |
| `roughness` | no | `0.25` | Noise |

Build logic:

```python
cx = center_offset_x_m
cy = center_offset_y_m
r = sqrt((X - cx)**2 + (Y - cy)**2)

# Bowl depression.
bowl = -depth_m * exp(-(r / (radius_m * 0.72)) ** 2)

# Raised rim near radius.
rim = rim_height_m * exp(-((r - radius_m) / rim_width_m) ** 2)

# Exterior terrain.
exterior = 6 * fbm_noise(scale=300, octaves=2)

# Small interior roughness.
interior_mask = 1 - smoothstep(radius_m * 0.7, radius_m * 1.2, r)
interior_noise = roughness * 10 * interior_mask * fbm_noise(scale=60, octaves=3)

Z = bowl + rim + exterior + interior_noise
Z = smooth(Z, 2)
```

Default params:

```json
{
  "radius_m": null,
  "depth_m": 70,
  "rim_height_m": 22,
  "rim_width_m": null,
  "center_offset_x_m": 0,
  "center_offset_y_m": 0,
  "roughness": 0.25
}
```

---

## Required Utility Functions

Implement these utilities.

### `make_grid(world_size_m, resolution)`

```python
def make_grid(world_size_m: float, resolution: int):
    half = world_size_m / 2.0
    axis = np.linspace(-half, half, resolution)
    X, Y = np.meshgrid(axis, axis)
    return X, Y
```

### `smoothstep(edge0, edge1, x)`

```python
def smoothstep(edge0, edge1, x):
    t = clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)
```

### `rotate(X, Y, degrees)`

```python
def rotate(X, Y, degrees):
    theta = radians(degrees)
    Xr = X * cos(theta) - Y * sin(theta)
    Yr = X * sin(theta) + Y * cos(theta)
    return Xr, Yr
```

### `fbm_noise(...)`

Implement deterministic fractal Brownian motion noise.

V1 acceptable implementation:

1. Generate low-resolution random grids from seeded RNG.
2. Upsample them to full resolution.
3. Sum octaves with decreasing amplitude.
4. Normalize to `[-1, 1]`.

Pseudocode:

```python
def fbm_noise(rng, resolution, world_size_m, scale_m, octaves, persistence=0.5):
    result = zeros((resolution, resolution))
    amplitude = 1.0
    total_amp = 0.0

    for octave in range(octaves):
        octave_scale = max(scale_m / (2 ** octave), 4.0)
        cells = max(4, int(world_size_m / octave_scale))
        grid = rng.normal(0, 1, (cells + 2, cells + 2))
        upsampled = bicubic_resize(grid, (resolution, resolution))
        result += amplitude * upsampled
        total_amp += amplitude
        amplitude *= persistence

    result /= max(total_amp, 1e-6)
    result -= mean(result)
    result /= max(abs(result).max(), 1e-6)
    return result
```

Use a real interpolation library if available. If not, bilinear interpolation is acceptable for v1.

### `smooth(Z, passes)`

```python
def smooth(Z, passes):
    out = Z.copy()
    for _ in range(passes):
        out = (
          out
          + roll(out, 1, axis=0)
          + roll(out, -1, axis=0)
          + roll(out, 1, axis=1)
          + roll(out, -1, axis=1)
        ) / 5.0
    return out
```

For v1, edge behavior can wrap or clamp. Prefer clamp/edge padding if simple.

---

## Heightmap Export

Required function:

```python
export_heightmap_png(Z, output_path) -> HeightmapStats
```

Behavior:

```python
min_z = float(Z.min())
max_z = float(Z.max())
height_range = max_z - min_z

if height_range < 0.001:
    # Avoid divide-by-zero for flat terrain.
    normalized = zeros_like(Z)
    height_range = 1.0
else:
    normalized = (Z - min_z) / height_range

img_u16 = round(normalized * 65535).astype(uint16)
save_as_16bit_grayscale_png(img_u16, output_path)
```

For flat terrain, set:

```text
min_z_m = elevation_m
max_z_m = elevation_m + 1.0
height_range_m = 1.0
```

Why: Gazebo heightmaps need a z size. A flat all-black image with `<pos>0 0 0</pos>` and `<size>... ... 1</size>` still renders flat at the bottom of the height range. If the intended elevation is `0`, keep `pos z = 0`.

---

## SDF Design

Generate a static terrain model.

### Required `model.config`

```xml
<?xml version="1.0"?>
<model>
  <name>generated_terrain</name>
  <version>1.0</version>
  <sdf version="1.12">model.sdf</sdf>
  <author>
    <name>Our App</name>
    <email>dev@example.com</email>
  </author>
  <description>Procedurally generated terrain heightmap.</description>
</model>
```

### Required `model.sdf`

Use this structure.

```xml
<?xml version="1.0" ?>
<sdf version="1.12">
  <model name="generated_terrain">
    <static>true</static>

    <link name="terrain_link">

      <collision name="terrain_collision">
        <geometry>
          <heightmap>
            <uri>model://generated_terrain/materials/textures/heightmap.png</uri>
            <size>{WORLD_SIZE_M} {WORLD_SIZE_M} {HEIGHT_RANGE_M}</size>
            <pos>0 0 {MIN_Z_M}</pos>
            <sampling>1</sampling>
          </heightmap>
        </geometry>

        <surface>
          <friction>
            <ode>
              <mu>{FRICTION_MU}</mu>
              <mu2>{FRICTION_MU2}</mu2>
            </ode>
          </friction>
        </surface>
      </collision>

      <visual name="terrain_visual">
        <geometry>
          <heightmap>
            <uri>model://generated_terrain/materials/textures/heightmap.png</uri>
            <size>{WORLD_SIZE_M} {WORLD_SIZE_M} {HEIGHT_RANGE_M}</size>
            <pos>0 0 {MIN_Z_M}</pos>
            <sampling>1</sampling>

            <texture>
              <size>25</size>
              <diffuse>model://generated_terrain/materials/textures/albedo.png</diffuse>
              <normal>model://generated_terrain/materials/textures/normal.png</normal>
            </texture>
          </heightmap>
        </geometry>
      </visual>

    </link>
  </model>
</sdf>
```

V1 friction defaults:

```json
{
  "friction_mu": 1.0,
  "friction_mu2": 1.0
}
```

If `albedo.png` and `normal.png` are not implemented yet, either:

1. Generate simple placeholder textures, or
2. Omit the `<texture>` block.

Do not reference missing texture files.

### Why `<size>` and `<pos>` matter

Use:

```xml
<size>X_SIZE_M Y_SIZE_M Z_RANGE_M</size>
<pos>0 0 MIN_Z_M</pos>
```

Interpretation:

```text
heightmap black -> MIN_Z_M
heightmap white -> MIN_Z_M + Z_RANGE_M
```

If:

```text
min_z_m = -80
max_z_m = 20
height_range_m = 100
```

then:

```xml
<size>2000 2000 100</size>
<pos>0 0 -80</pos>
```

### Gazebo collision rules

The terrain must be inside a `<collision>` element. The visual-only heightmap is not enough.

For physics correctness:

```text
collision heightmap uri == visual heightmap uri
collision size == visual size
collision pos == visual pos
collision sampling == visual sampling
```

### World inclusion

When generating a full world, include the model:

```xml
<include>
  <uri>model://generated_terrain</uri>
  <pose>0 0 0 0 0 0</pose>
</include>
```

Alternative: spawn into a running Gazebo world using the `/world/<world_name>/create` service with the generated SDF.

---

## Gazebo Spawn Flow

Implement both flows if easy. If only one is possible in v1, implement pre-launch world generation first.

### Flow A: Pre-launch world generation

```text
1. User/app requests terrain.
2. Generate model folder.
3. Add include to world.sdf.
4. Launch Gazebo with that world.
5. Spawn robots using terrain-aware spawn z.
```

### Flow B: Runtime insertion

```text
1. Gazebo world is already running.
2. User/app requests terrain.
3. Generate model folder.
4. Call Gazebo create-entity service with the generated SDF or model URI.
5. Wait for model insertion confirmation.
6. Spawn robots.
```

Pseudo-command shape:

```bash
gz service \
  -s /world/${WORLD_NAME}/create \
  --reqtype gz.msgs.EntityFactory \
  --reptype gz.msgs.Boolean \
  --timeout 3000 \
  --req 'sdf_filename: "/absolute/path/to/generated_terrain/model.sdf", name: "generated_terrain"'
```

Exact command/service wrapper may vary by Gazebo version. Encapsulate this behind:

```python
spawn_terrain_in_gazebo(world_name, model_sdf_path) -> bool
```

---

## Terrain Query API

The app/autonomy stack must not rely only on Gazebo physics. It must be able to query terrain heights before sending commands.

Create:

```python
class TerrainQuery:
    def __init__(self, metadata_path, heightmap_path):
        ...

    def height_at(self, x_m: float, y_m: float) -> float:
        ...

    def normal_at(self, x_m: float, y_m: float) -> tuple[float, float, float]:
        ...

    def slope_at(self, x_m: float, y_m: float) -> float:
        ...

    def min_safe_altitude(self, x_m: float, y_m: float, min_agl_m: float) -> float:
        return self.height_at(x_m, y_m) + min_agl_m
```

### `height_at(x, y)`

Use bilinear interpolation.

Pseudocode:

```python
def height_at(x, y):
    half = world_size_m / 2

    u = (x + half) / world_size_m
    v = (y + half) / world_size_m

    u = clamp(u, 0, 1)
    v = clamp(v, 0, 1)

    col = u * (resolution - 1)
    row = v * (resolution - 1)

    h01 = bilinear_sample(heightmap_normalized, row, col)

    return min_z_m + h01 * height_range_m
```

### `normal_at(x, y)`

Use local finite differences:

```python
dzdx = (height_at(x + dx, y) - height_at(x - dx, y)) / (2 * dx)
dzdy = (height_at(x, y + dy) - height_at(x, y - dy)) / (2 * dy)

normal = normalize((-dzdx, -dzdy, 1.0))
```

Use:

```text
dx = world_size_m / (resolution - 1)
dy = world_size_m / (resolution - 1)
```

### `slope_at(x, y)`

```python
normal = normal_at(x, y)
slope_rad = acos(clamp(normal.z, -1, 1))
slope_deg = degrees(slope_rad)
```

### `is_traversable(x, y, vehicle_profile)`

Basic v1 version:

```python
return slope_at(x, y) <= vehicle_profile.max_slope_deg
```

Recommended vehicle profile:

```json
{
  "name": "default_ugv",
  "max_slope_deg": 20,
  "min_ground_clearance_m": 0.15,
  "max_step_m": 0.20
}
```

V1 optional improvement:

```text
Also reject terrain where height variation inside the vehicle footprint exceeds max_step_m.
```

---

## Autonomy Stack Integration

This section is mandatory. Build the terrain system so it supports Gazebo physics and autonomy decisions.

### 1. Sims / SITL

SITL means the autopilot or autonomy software is running as software while Gazebo simulates the world, sensors, and vehicle dynamics.

For v1:

```text
Gazebo owns:
  - terrain collision
  - robot/terrain contact
  - gravity
  - sensor raycasting
  - vehicle dynamics plugins

SITL/autopilot owns:
  - vehicle control
  - mission execution
  - failsafes
  - navigation commands
```

Terrain integration requirements for SITL:

```text
1. Spawn vehicles above terrain using TerrainQuery.
2. For UAV mission commands, convert AGL requests to world z:
     world_z = terrain.height_at(x, y) + requested_agl_m
3. For terrain-following tests, publish or provide terrain height queries to the mission layer.
4. Do not allow mission waypoints below:
     terrain.height_at(x, y) + min_agl_m
5. For UGVs, reject spawn points where slope exceeds vehicle profile.
```

For ArduPilot/PX4-style SITL:

```text
- Keep terrain generation independent of autopilot.
- Gazebo provides simulated sensors and physics.
- The autopilot receives sensor/pose data through the existing bridge.
- The app validates mission feasibility before sending mission items.
```

### 2. ROS 2

ROS 2 should receive terrain-derived information through explicit topics/services.

Implement these optional-but-recommended interfaces:

```text
/terrain/metadata
  type: app-specific message or JSON string
  contains: world_size, min_z, max_z, seed, type

/terrain/height_at
  service: request x,y -> response z

/terrain/slope_at
  service: request x,y -> response slope_deg

/terrain/grid_map
  optional v2
  publishes elevation grid for terrain-aware planners
```

For v1, the minimum required ROS 2 bridge is not a full elevation map. The minimum is:

```text
- terrain-aware spawn logic
- app-side waypoint validation
- optional height query service
```

### 3. Nav2

Nav2 is fundamentally a 2D navigation stack for ground robots. It plans in SE2:

```text
x, y, yaw
```

Nav2 costmaps are 2D. They can represent obstacles and inflated zones, but they do not automatically understand a 3D terrain heightmap as drivable or non-drivable.

For v1, do this:

```text
1. Use Gazebo heightmap collision for physical UGV interaction.
2. Generate a 2D traversability costmap from the terrain.
3. Feed that into Nav2 as an occupancy/cost layer or map.
```

### Nav2 terrain-derived costmap generation

Generate a 2D grid from the same heightmap.

For each cell:

```python
slope = terrain.slope_at(x, y)
roughness = local_height_stddev(x, y, radius=vehicle_radius_m)

if slope > max_slope_deg:
    cost = LETHAL_OBSTACLE
elif roughness > max_roughness_m:
    cost = LETHAL_OBSTACLE
else:
    cost = scale_cost(slope, 0, max_slope_deg)
```

Recommended v1 constants:

```text
FREE_SPACE = 0
INSCRIBED = 253
LETHAL_OBSTACLE = 254
UNKNOWN = 255
```

Nav2 requirements:

```text
- Keep TF valid: map -> odom -> base_link or equivalent.
- Make sure the robot footprint or robot_radius matches the simulated UGV.
- Use the terrain-derived costmap as a static map or custom costmap layer.
- Do not expect Nav2 to infer slopes from Gazebo collision automatically.
```

V1 acceptable implementation:

```text
Generate nav2_terrain_map.pgm + nav2_terrain_map.yaml from terrain slope.
Use it as the static map for Nav2.
```

Better v1.5 implementation:

```text
Create a custom Nav2 costmap layer that subscribes to /terrain/traversability_grid.
```

### 4. Aerostack2

Aerostack2 is ROS 2-based and is aimed at aerial robotics. For our terrain work, treat it as the UAV autonomy layer.

For v1:

```text
Gazebo terrain collision prevents physical penetration.
Aerostack2 mission/planning should avoid invalid low-altitude commands.
```

Terrain integration requirements:

```text
1. Before sending a UAV waypoint:
     world_z must be >= terrain.height_at(x, y) + min_agl_m

2. For takeoff:
     takeoff_z = terrain.height_at(spawn_x, spawn_y) + takeoff_agl_m

3. For landing:
     landing_z = terrain.height_at(landing_x, landing_y)
     final approach target = landing_z + landing_clearance_m

4. For route validation:
     sample each segment every N meters
     reject segment if any sampled point violates min AGL

5. For geofencing:
     add a lower terrain-following geofence:
       z_min(x, y) = terrain.height_at(x, y) + min_agl_m
```

Add this app-side helper:

```python
def validate_uav_path(waypoints, terrain, min_agl_m, sample_spacing_m=5):
    for segment in pairwise(waypoints):
        for p in sample_segment(segment, sample_spacing_m):
            terrain_z = terrain.height_at(p.x, p.y)
            if p.z < terrain_z + min_agl_m:
                return Invalid(reason="below_min_agl", point=p, terrain_z=terrain_z)
    return Valid()
```

Do not rely only on collision to protect UAVs. Collision is too late; planning should prevent invalid commands.

---

## Main Generator Algorithm

Implement:

```python
def generate_terrain(request: TerrainRequest) -> TerrainArtifact:
    validate_request(request)

    terrain_type = request.type
    world_size_m = size_to_world_m(request.size)
    resolution = request.resolution or default_resolution(request.size)
    seed = request.seed if request.seed is not None else random_uint32()

    rng = np.random.default_rng(seed)

    X, Y = make_grid(world_size_m, resolution)

    params = apply_defaults(terrain_type, request.params, world_size_m)

    if terrain_type == "flat":
        Z = build_flat(X, Y, rng, params)
    elif terrain_type == "rugged":
        Z = build_rugged(X, Y, rng, params)
    elif terrain_type == "low_hills":
        Z = build_low_hills(X, Y, rng, params)
    elif terrain_type == "high_hills":
        Z = build_high_hills(X, Y, rng, params)
    elif terrain_type == "mountain":
        Z = build_mountain(X, Y, rng, params)
    elif terrain_type == "valley":
        Z = build_valley(X, Y, rng, params)
    elif terrain_type == "canyon":
        Z = build_canyon(X, Y, rng, params)
    elif terrain_type == "crater":
        Z = build_crater(X, Y, rng, params)
    else:
        raise ValueError("Unsupported terrain type")

    Z = final_postprocess(Z, params)

    stats = export_heightmap_png(Z, "materials/textures/heightmap.png")

    write_placeholder_textures_if_needed()

    write_model_config()
    write_model_sdf(
        world_size_m=world_size_m,
        min_z_m=stats.min_z_m,
        height_range_m=stats.height_range_m
    )

    write_metadata_json(
        request=request,
        seed=seed,
        world_size_m=world_size_m,
        resolution=resolution,
        stats=stats,
        params=params
    )

    write_preview_png(Z)

    return TerrainArtifact(...)
```

---

## Final Postprocessing

Mandatory:

```python
def final_postprocess(Z, params):
    Z = remove_nan_inf(Z)

    if params.get("global_smoothing_passes"):
        Z = smooth(Z, params["global_smoothing_passes"])

    if params.get("clamp_min_m") is not None:
        Z = maximum(Z, params["clamp_min_m"])

    if params.get("clamp_max_m") is not None:
        Z = minimum(Z, params["clamp_max_m"])

    return Z
```

Also add a zero-mean option for noise-based terrains:

```text
rugged, low_hills, high_hills should center around z=0 by default.
mountain, crater, valley, canyon do not need to be zero-mean.
```

---

## API Endpoint

Create an internal app API endpoint.

### `POST /api/sim/terrain/generate`

Request:

```json
{
  "type": "canyon",
  "size": "medium",
  "seed": 42,
  "resolution": 2049,
  "params": {
    "depth_m": 90,
    "width_m": 180
  }
}
```

Response:

```json
{
  "terrain_id": "terrain_canyon_medium_seed42",
  "type": "canyon",
  "size": "medium",
  "seed": 42,
  "world_size_m": 2000,
  "resolution": 2049,
  "model_uri": "model://terrain_canyon_medium_seed42",
  "sdf_path": "/absolute/path/to/model.sdf",
  "metadata_path": "/absolute/path/to/metadata.json",
  "heightmap_path": "/absolute/path/to/materials/textures/heightmap.png",
  "min_z_m": -90.8,
  "max_z_m": 22.3,
  "height_range_m": 113.1
}
```

### `GET /api/sim/terrain/:terrain_id/height?x=10&y=20`

Response:

```json
{
  "x": 10,
  "y": 20,
  "z": -34.2
}
```

### `POST /api/sim/terrain/:terrain_id/validate-uav-path`

Request:

```json
{
  "min_agl_m": 10,
  "waypoints": [
    {"x": 0, "y": 0, "z": 50},
    {"x": 100, "y": 100, "z": 60}
  ]
}
```

Response:

```json
{
  "valid": true,
  "violations": []
}
```

---

## Testing Requirements

### Determinism test

```text
Given same request with same seed:
  generated heightmap hash must match
  metadata must match except output paths/timestamps
```

### Variation test

```text
Given same request with different seed:
  generated heightmap hash should differ
```

### SDF test

Assert:

```text
model.sdf exists
contains <collision>
contains <visual>
collision heightmap URI equals visual heightmap URI
collision size equals visual size
collision pos equals visual pos
```

### Height query test

For known generated terrain:

```text
height_at(0, 0) returns finite number
height_at outside bounds clamps safely
normal_at returns normalized vector
slope_at returns between 0 and 90 degrees for normal terrain
```

### Spawn test

For each terrain type:

```text
spawn_z = height_at(x, y) + clearance
spawn_z must be greater than terrain height
```

### Nav2 traversability test

For canyon:

```text
steep canyon walls should become high cost / lethal
flat canyon floor should be traversable if slope is below threshold
```

---

## V1 Non-Goals

Do not implement these in v1:

```text
- caves
- tunnels
- overhangs
- erosion simulation that runs for many seconds/minutes
- manual terrain sculpting UI
- importing real DEM data
- texture splat mapping by biome
- runtime terrain deformation
- destructible terrain
- automatic Nav2 custom costmap plugin unless already easy
```

---

## Acceptance Criteria

Version 1 is done when:

```text
1. App can generate all terrain types:
   flat, rugged, low_hills, high_hills, mountain, valley, canyon, crater

2. Each type works with:
   size = small, medium, large

3. Each generated terrain writes:
   model.config
   model.sdf
   heightmap.png
   metadata.json

4. Gazebo can load the generated terrain.

5. UGVs collide with and drive on the terrain instead of falling through it.

6. UAVs collide with the terrain if commanded into it.

7. App-side spawn logic places robots above the terrain.

8. App-side UAV validation rejects waypoints below:
   terrain.height_at(x, y) + min_agl_m

9. Basic Nav2 terrain map generation exists:
   slope-derived static occupancy/cost map is enough for v1.

10. Same seed produces same terrain.
```

---

## Implementation Notes for Cursor

Build this in small commits:

### Commit 1: Data models and validation

```text
- TerrainRequest
- TerrainArtifact
- TerrainMetadata
- size/resolution validation
- default params per type
```

### Commit 2: Noise and grid utilities

```text
- make_grid
- smoothstep
- rotate
- fbm_noise
- smooth
```

### Commit 3: Preset builders

```text
- build_flat
- build_rugged
- build_low_hills
- build_high_hills
- build_mountain
- build_valley
- build_canyon
- build_crater
```

### Commit 4: Exporters

```text
- 16-bit heightmap PNG
- metadata.json
- model.config
- model.sdf
- optional preview.png
```

### Commit 5: TerrainQuery

```text
- height_at
- normal_at
- slope_at
- min_safe_altitude
- is_traversable
```

### Commit 6: Gazebo integration

```text
- generated model path registration
- world include
- optional runtime spawn service
```

### Commit 7: Autonomy helpers

```text
- terrain-aware robot spawn
- UAV path validation
- Nav2 slope-derived map export
```

### Commit 8: Tests

```text
- determinism
- SDF consistency
- height query
- terrain types smoke test
- Nav2 traversability smoke test
```

---

## Source Notes

This implementation relies on the current SDFormat/Gazebo model where:

```text
- <visual> and <collision> elements each contain geometry.
- <heightmap> is a supported geometry.
- <heightmap><size> defines world-unit size.
- <heightmap><pos> defines the position offset.
- Gazebo Sim can load SDF worlds and can create entities from SDF at runtime through /world/<world_name>/create.
```

Nav2 should be treated as a 2D navigation system that needs terrain-derived costs, not as a system that automatically understands Gazebo heightmap slopes.

Aerostack2 should be treated as the aerial autonomy layer. The terrain system must provide AGL validation and terrain-aware takeoff/landing helpers rather than expecting UAV collision alone to keep missions safe.
