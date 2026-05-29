const sealSystems = ['Intuseal', 'Dunamenti', 'Fischer', 'Hilti', 'Protecta'];

const systemMaterials = <String, List<String>>{
  'Intuseal': [
    'INTU FR',
    'UNICOAT',
    'MAST IC',
    'GRAPHITE',
    'WRAP',
    'WRAPL',
    'COAT I',
    'COAT A',
    'BOARD A',
    'UNI BOARD',
    'COLLAR',
    'COLLAR SLIM',
    'EJ SEAL',
    'DISC',
    'FOAM 2K',
    'BANDAGE',
    'GRILLE',
    'INSU ROPE',
    'Jiný',
  ],
  'Dunamenti': [
    'Polylack F/K',
    'Dunafoam 1K',
    'PS',
    'PS 25',
    'Polylack KG',
    'Polylack Elastic',
    'Jiný',
  ],
  'Fischer': [
    'FiAM',
    'FiGM',
    'FPG',
    'FPC',
    'FPP',
    'Jiný',
  ],
  'Hilti': [
    'CFS B',
    'CP 670/CFS CT',
    'CP 648E',
    'CP 611A',
    'CP 644/3',
    'CFS CID 110',
    'CFS CID 150',
    'CFS-F-FX',
    'CFS S-ACR',
    'Jiný',
  ],
  'Protecta': [
    'FR ACRYLIC',
    'FR GRAPHITE',
    'Jiný',
  ],
};

const constructions = ['Beton/Cihla', 'SDK/PUR'];
const locations = ['Stěna', 'Strop', 'Podlaha', 'Šachta'];
const fireRatings = ['60 min', '90 min', '120 min'];
const entryTypes = ['EL.V.', 'PVC', 'VZT', 'PROSTUP', 'OCEL'];
const dimensions = ['Ø50', 'Ø100', '100x100', '150x150', 'Vlastní'];
const insulations = ['žádná', 'hořlavá', 'nehořlavá'];
