# PalmQ10-v0.1.3-alpha
Plug-in tool for running PalmQ 10 microclimatic simulations from qGIS

# What PalmQ 10 is

PalmQ10 produces **urban-microclimate simulations** for a user-drawn area of interest (AOI). It orchestrates a chain of established atmospheric-science tools and turns their raw outputs into human-readable heat/comfort products (apparent temperature, MRT/UTCI, exceedance hours, etc.).

The scientific chain, in order:

AOI (polygon)

│

├─ geo4palm ────────► PALM "static driver" (terrain, buildings, land use, streets, trees)

│

└─ WRF/WPS ─► wrf4palm ─► PALM "dynamic driver" (time-varying boundary forcing from ERA5)

│

PALM ────┴───► 3D output (u,v,w,ta,rh,rtm_mrt …)

│

post ───► heat/comfort rasters + plots

- **WRF/WPS** - mesoscale weather model (coarse, ~1 km) that ingests **ERA5** reanalysis and produces the atmospheric state around the city.
- **wrf4palm** - interpolates WRF output onto the PALM grid to make the **dynamic driver** (the time-dependent lateral/top boundary conditions PALM needs).
- **geo4palm** - builds the **static driver** (the fixed geography: DEM terrain, building footprints/heights, land use, pavement, streets, tree canopy).
- **PALM** - the large-eddy-simulation core that actually resolves the urban microclimate.
- **post** - converts PALM's 3D NetCDF into biometeorological products.

Everything runs inside **Apptainer/Singularity containers** (.sif), either locally or on an HPC cluster. PalmQ10's own Python code is the _orchestration and glue_ around those containers.

# Repository layout

palmq10_plugin/ QGIS plugin - the GUI frontend gui/aoi_dialog.py main dialog; every pipeline button lives here gui/cluster_profile_dialog.py HPC profile editor gui/process_dialog.py live-log run window (QProcess)

schema/aoi_schema.py AOI_SCHEMA - declares every user-editable field

palmq10_core/

internal/ Backend pipeline (all the real logic; pure Python, no QGIS deps) setup/ AOI → base namelist

geo4palm/ static driver

wrfwrs/ WRF/WPS (weather)

wrf4palm/ dynamic driver

palm/ PALM run + p3d generation

post/ products & plots

clusters/ HPC subsystem (schedulers, storage, auth)

util/ shared helpers

external/ Container images (.sif) + WPS_GEOG data (large, not in git) jobs/ Per-project run data, created at runtime

documentation/ Cluster profiles (YAML), specs, this manual

**Two-tree rule for maintainers.** The **development** repo (this tree, …/Claude/Projects/PalmQ10/) holds palmq10*core/ \_and* palmq10_plugin/. Production is a separate copy (currently an OneDrive tree). **Edit only the dev repo; the production copy is updated by a manual file copy.** Reading production to compare is fine; never edit it.
