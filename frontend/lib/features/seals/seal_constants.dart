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
const insulations = ['žádná', 'hořlavá', 'nehořlavá'];

const dimensionPresetsElV = [
  'Ø20',
  'Ø30',
  'Ø40',
  'Ø50',
  '100/100',
  '150/100',
  '200/100',
  '300/100',
  '300/200',
  '500/300',
];

const dimensionPresetsPvc = [
  'Ø40',
  'Ø50',
  'Ø75',
  'Ø90',
  'Ø110',
  'Ø125',
  'Ø160',
];

const dimensionPresetsVzt = [
  'Ø100',
  'Ø125',
  'Ø160',
  'Ø200',
  'Ø220',
  'Ø250',
  'Ø300',
];

/// OC + OC nehořlavá izolace (PROSTUP + nehořlavá).
const dimensionPresetsOcNonFlammable = [
  'Ø20-100',
  'Ø110-150',
  'Ø160-200',
  'Ø210-250',
];

/// OC, hořlavá izolace (PROSTUP + hořlavá).
const dimensionPresetsOcFlammable = [
  'Ø40',
  'Ø50',
  'Ø75',
  'Ø90',
  'Ø100',
  'Ø125',
  'Ø150',
];

/// Presety rozměrů podle typu prostupu a izolace.
List<String> dimensionPresetsForEntry(String entryType, String insulation) {
  switch (entryType) {
    case 'EL.V.':
      return dimensionPresetsElV;
    case 'PVC':
      return dimensionPresetsPvc;
    case 'VZT':
      return dimensionPresetsVzt;
    case 'PROSTUP':
      if (insulation == 'hořlavá') return dimensionPresetsOcFlammable;
      if (insulation == 'nehořlavá') return dimensionPresetsOcNonFlammable;
      return dimensionPresetsOcNonFlammable;
    case 'OCEL':
      return const [];
    default:
      return const ['Vlastní'];
  }
}

String defaultDimensionForEntry(String entryType, String insulation) {
  if (entryType == 'OCEL') return '';
  final presets = dimensionPresetsForEntry(entryType, insulation);
  return presets.isNotEmpty ? presets.first : '';
}
