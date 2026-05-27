const sealSystems = ['Intuseal', 'Hilti', 'Fischer', 'Protecta', 'Dunamenti'];

const systemMaterials = <String, List<String>>{
  'Intuseal': ['Intumescentní páska', 'Pěna', 'Těsnění', 'Jiný'],
  'Hilti': ['CP 606', 'CP 637', 'FS-ONE', 'Jiný'],
  'Fischer': ['Firoblok', 'Firofill', 'Firojoint', 'Jiný'],
  'Protecta': ['FR Acrylic', 'FR Board', 'Jiný'],
  'Dunamenti': ['Dunafoam', 'Dunaseal', 'Jiný'],
};

const constructions = ['Beton/Cihla', 'SDK/PUR'];
const locations = ['Stěna', 'Strop', 'Podlaha', 'Šachta'];
const fireRatings = ['60 min', '90 min', '120 min'];
const entryTypes = ['EL.V.', 'PVC', 'VZT', 'PROSTUP', 'OCEL'];
const dimensions = ['Ø50', 'Ø100', '100x100', '150x150', 'Vlastní'];
const insulations = ['žádná', 'hořlavá', 'nehořlavá'];
