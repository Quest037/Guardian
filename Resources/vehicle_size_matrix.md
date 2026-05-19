# Vehicle Size Matrix by Class

**Units:** centimetres (cm)  
**Dimensions:** width × length × height  
**Purpose:** draft sizing envelopes for simulation, scene-building, asset tagging, dataset labeling, and coarse vehicle taxonomy.

These ranges are **practical bounding-box envelopes**, not regulatory standards. They are intended to keep vehicle assets internally consistent across classes and size bands.

## Size Bands

| Size | Intended Meaning |
|---|---|
| Micro | Palm-sized / very compact systems |
| Mini | Backpack-portable or hand-launchable systems |
| Small | One-person portable or compact field systems |
| Medium | Team-portable / light vehicle class |
| Large | Vehicle-sized or heavy tactical systems |
| XLarge | Large fielded vehicles / large maritime or undersea systems |
| XXLarge | Strategic / full-scale aircraft, vessel, or major platform class |

## Notes on Anchor Examples

- The uploaded tracked UGV with turret is treated as **UGV-T XLarge**.
- Predator / Bayraktar-class UAVs are treated as **UAV-F Fixed Wing XXLarge**.
- Values are approximate bounding boxes and should be interpreted as `min–max` envelopes.
- Height for aircraft includes landing gear, rotor mast, or VTOL lift hardware where applicable.
- Width for fixed-wing aircraft is wingspan.
- Width for copters is rotor-disc diameter or maximum rotor-to-rotor span.
- Length for USV/UUV is hull length.

---

# Master Matrix

## UAV-C — Copter

| Size | Width cm | Length cm | Height cm | Typical Examples |
|---|---:|---:|---:|---|
| Micro | 5–20 | 5–20 | 2–10 | Nano quadcopter, palm drone |
| Mini | 20–50 | 20–50 | 5–25 | Small consumer quadcopter |
| Small | 50–120 | 50–120 | 15–60 | Mapping quadcopter, inspection drone |
| Medium | 120–250 | 120–250 | 40–120 | Heavy-lift multirotor, larger ISR copter |
| Large | 250–500 | 250–600 | 80–200 | Cargo multirotor, large unmanned helicopter |
| XLarge | 500–1,000 | 500–1,200 | 150–350 | Full-scale unmanned helicopter |
| XXLarge | 1,000–2,500 | 1,000–3,000 | 250–700 | Large rotorcraft UAV / optionally piloted helicopter class |

## UAV-F — Fixed Wing

| Size | Width cm | Length cm | Height cm | Typical Examples |
|---|---:|---:|---:|---|
| Micro | 20–80 | 20–70 | 5–20 | Micro fixed-wing flyer |
| Mini | 80–200 | 70–150 | 10–40 | Hand-launched fixed-wing UAV |
| Small | 200–400 | 150–300 | 30–100 | Small tactical fixed-wing UAV |
| Medium | 400–800 | 300–600 | 80–180 | Catapult-launched ISR UAV |
| Large | 800–1,400 | 600–1,000 | 150–300 | Large tactical fixed-wing UAV |
| XLarge | 1,400–2,000 | 1,000–1,400 | 250–450 | MALE-like smaller aircraft class |
| XXLarge | 2,000–4,000 | 1,400–2,700 | 350–800 | Predator / Bayraktar-class and larger MALE UAVs |

## UAV-F — VTOL

| Size | Width cm | Length cm | Height cm | Typical Examples |
|---|---:|---:|---:|---|
| Micro | 20–80 | 20–70 | 5–25 | Micro tail-sitter / micro lift-wing UAV |
| Mini | 80–200 | 70–170 | 15–50 | Backpack VTOL fixed-wing UAV |
| Small | 200–450 | 150–350 | 30–100 | Small quadplane or tilt-rotor UAV |
| Medium | 450–900 | 300–700 | 80–200 | Tactical VTOL fixed-wing UAV |
| Large | 900–1,500 | 600–1,100 | 150–350 | Large hybrid VTOL ISR UAV |
| XLarge | 1,500–2,500 | 1,000–1,800 | 250–600 | Large cargo / surveillance VTOL UAV |
| XXLarge | 2,500–5,000 | 1,800–3,500 | 400–1,000 | Full-scale autonomous tiltrotor / large VTOL aircraft |

## UGV-W — Wheeled

| Size | Width cm | Length cm | Height cm | Typical Examples |
|---|---:|---:|---:|---|
| Micro | 5–25 | 5–30 | 3–20 | Tiny rover, inspection crawler |
| Mini | 25–60 | 30–90 | 10–45 | Small indoor rover |
| Small | 60–120 | 90–180 | 30–100 | Outdoor scout rover |
| Medium | 120–200 | 180–350 | 70–180 | ATV-sized UGV |
| Large | 200–300 | 350–600 | 120–250 | Light vehicle-sized UGV |
| XLarge | 300–450 | 600–900 | 180–350 | Heavy truck / large tactical wheeled UGV |
| XXLarge | 450–700 | 900–1,500 | 250–500 | Very large logistics or specialized unmanned ground platform |

## UGV-T — Tracked

| Size | Width cm | Length cm | Height cm | Typical Examples |
|---|---:|---:|---:|---|
| Micro | 5–25 | 5–35 | 3–20 | Micro tracked inspection robot |
| Mini | 25–70 | 40–100 | 10–50 | Backpack tracked robot |
| Small | 70–130 | 100–220 | 30–100 | EOD / scout tracked UGV |
| Medium | 130–220 | 220–400 | 70–180 | Team-transported tactical tracked UGV |
| Large | 220–320 | 400–650 | 120–260 | Light armored tracked UGV |
| XLarge | 320–450 | 650–900 | 180–400 | Uploaded image class: large tracked combat/support UGV |
| XXLarge | 450–700 | 900–1,500 | 250–550 | Tank-sized or very heavy tracked unmanned platform |

## UGV-L — Legged

| Size | Width cm | Length cm | Height cm | Typical Examples |
|---|---:|---:|---:|---|
| Micro | 5–20 | 5–25 | 5–20 | Micro hexapod / crawler |
| Mini | 20–50 | 25–70 | 15–50 | Small quadruped robot |
| Small | 50–100 | 70–140 | 40–100 | Dog-sized legged robot |
| Medium | 100–180 | 140–250 | 80–180 | Large quadruped payload carrier |
| Large | 180–300 | 250–450 | 140–300 | Mule-sized legged robot |
| XLarge | 300–500 | 450–800 | 250–500 | Very large cargo legged platform |
| XXLarge | 500–800 | 800–1,400 | 400–800 | Experimental heavy walking vehicle class |

## USV — Uncrewed Surface Vessel

| Size | Width cm | Length cm | Height cm | Typical Examples |
|---|---:|---:|---:|---|
| Micro | 10–40 | 20–80 | 5–30 | Small test boat, pool-scale USV |
| Mini | 40–100 | 80–200 | 20–80 | Portable survey USV |
| Small | 100–250 | 200–500 | 50–180 | Harbor survey or inspection USV |
| Medium | 250–450 | 500–1,000 | 100–300 | RHIB-sized USV |
| Large | 450–800 | 1,000–2,000 | 200–600 | Patrol or logistics USV |
| XLarge | 800–1,500 | 2,000–5,000 | 400–1,200 | Large naval or cargo USV |
| XXLarge | 1,500–4,000 | 5,000–15,000 | 800–3,000 | Ship-scale uncrewed surface vessel |

## UUV — Uncrewed Underwater Vehicle

| Size | Width cm | Length cm | Height cm | Typical Examples |
|---|---:|---:|---:|---|
| Micro | 3–15 | 10–50 | 3–15 | Micro AUV / inspection probe |
| Mini | 15–40 | 50–150 | 15–40 | Portable torpedo-style UUV |
| Small | 40–100 | 150–400 | 40–100 | Small survey AUV |
| Medium | 100–200 | 400–800 | 80–200 | Medium survey or mine-countermeasure UUV |
| Large | 200–350 | 800–1,500 | 150–350 | Large-displacement UUV |
| XLarge | 350–700 | 1,500–3,000 | 250–700 | Extra-large UUV / subsea payload carrier |
| XXLarge | 700–1,500 | 3,000–10,000 | 500–1,500 | Submarine-scale autonomous underwater platform |

---

# Compact CSV-Style Matrix

```csv
class,size,width_cm,length_cm,height_cm
UAV-C Copter,micro,5-20,5-20,2-10
UAV-C Copter,mini,20-50,20-50,5-25
UAV-C Copter,small,50-120,50-120,15-60
UAV-C Copter,medium,120-250,120-250,40-120
UAV-C Copter,large,250-500,250-600,80-200
UAV-C Copter,xlarge,500-1000,500-1200,150-350
UAV-C Copter,xxlarge,1000-2500,1000-3000,250-700
UAV-F Fixed Wing,micro,20-80,20-70,5-20
UAV-F Fixed Wing,mini,80-200,70-150,10-40
UAV-F Fixed Wing,small,200-400,150-300,30-100
UAV-F Fixed Wing,medium,400-800,300-600,80-180
UAV-F Fixed Wing,large,800-1400,600-1000,150-300
UAV-F Fixed Wing,xlarge,1400-2000,1000-1400,250-450
UAV-F Fixed Wing,xxlarge,2000-4000,1400-2700,350-800
UAV-F VTOL,micro,20-80,20-70,5-25
UAV-F VTOL,mini,80-200,70-170,15-50
UAV-F VTOL,small,200-450,150-350,30-100
UAV-F VTOL,medium,450-900,300-700,80-200
UAV-F VTOL,large,900-1500,600-1100,150-350
UAV-F VTOL,xlarge,1500-2500,1000-1800,250-600
UAV-F VTOL,xxlarge,2500-5000,1800-3500,400-1000
UGV-W Wheeled,micro,5-25,5-30,3-20
UGV-W Wheeled,mini,25-60,30-90,10-45
UGV-W Wheeled,small,60-120,90-180,30-100
UGV-W Wheeled,medium,120-200,180-350,70-180
UGV-W Wheeled,large,200-300,350-600,120-250
UGV-W Wheeled,xlarge,300-450,600-900,180-350
UGV-W Wheeled,xxlarge,450-700,900-1500,250-500
UGV-T Tracked,micro,5-25,5-35,3-20
UGV-T Tracked,mini,25-70,40-100,10-50
UGV-T Tracked,small,70-130,100-220,30-100
UGV-T Tracked,medium,130-220,220-400,70-180
UGV-T Tracked,large,220-320,400-650,120-260
UGV-T Tracked,xlarge,320-450,650-900,180-400
UGV-T Tracked,xxlarge,450-700,900-1500,250-550
UGV-L Legged,micro,5-20,5-25,5-20
UGV-L Legged,mini,20-50,25-70,15-50
UGV-L Legged,small,50-100,70-140,40-100
UGV-L Legged,medium,100-180,140-250,80-180
UGV-L Legged,large,180-300,250-450,140-300
UGV-L Legged,xlarge,300-500,450-800,250-500
UGV-L Legged,xxlarge,500-800,800-1400,400-800
USV,micro,10-40,20-80,5-30
USV,mini,40-100,80-200,20-80
USV,small,100-250,200-500,50-180
USV,medium,250-450,500-1000,100-300
USV,large,450-800,1000-2000,200-600
USV,xlarge,800-1500,2000-5000,400-1200
USV,xxlarge,1500-4000,5000-15000,800-3000
UUV,micro,3-15,10-50,3-15
UUV,mini,15-40,50-150,15-40
UUV,small,40-100,150-400,40-100
UUV,medium,100-200,400-800,80-200
UUV,large,200-350,800-1500,150-350
UUV,xlarge,350-700,1500-3000,250-700
UUV,xxlarge,700-1500,3000-10000,500-1500
```

---

# Suggested Classification Rule

Classify an asset by its **largest bounding-box dimension first**, then sanity-check by class-specific expectations:

1. Measure width, length, and height in centimetres.
2. Find the size band where most dimensions fit.
3. If one dimension is dramatically larger because of wingspan, rotor span, mast, antenna, turret, or sensor payload, allow the vehicle to move up one band.
4. For fixed-wing UAVs, wingspan usually dominates classification.
5. For copters, rotor diameter or rotor-to-rotor span usually dominates classification.
6. For USVs and UUVs, hull length usually dominates classification.
7. For UGVs, length and width should dominate; height may vary heavily depending on turret, mast, manipulator arm, or sensor package.

