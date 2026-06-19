const pptxgen = require("pptxgenjs");
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const FA = require("react-icons/fa");

// ---------- paleta ----------
const NAVY = "16243F";   // tmavé pozadí (titul/závěr)
const NAVY2 = "1E3358";
const BLUE = "2E5C8A";
const STEEL = "3D6FA5";
const AMBER = "E0A43B";   // akcent
const AMBER_D = "C98A22";
const LIGHT = "F3F6FA";   // pozadí obsahu
const CARD = "FFFFFF";
const INK = "1F2937";
const MUTE = "6B7280";
const WHITE = "FFFFFF";
const GREEN = "3Fae6a";
const RED = "C0563E";

// ---------- ikony ----------
async function icon(IconComponent, color = "#FFFFFF", size = 256) {
  const svg = ReactDOMServer.renderToStaticMarkup(
    React.createElement(IconComponent, { color, size: String(size) })
  );
  const png = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + png.toString("base64");
}

async function buildIcons() {
  const w = "#FFFFFF";
  const defs = {
    clipboard: FA.FaClipboardList, wifi: FA.FaWifi, map: FA.FaMapMarkedAlt,
    invoice: FA.FaFileInvoiceDollar, chart: FA.FaChartBar, hardhat: FA.FaHardHat,
    tie: FA.FaUserTie, calc: FA.FaCalculator, shield: FA.FaUserShield,
    layers: FA.FaLayerGroup, camera: FA.FaCamera, cloud: FA.FaCloudUploadAlt,
    tag: FA.FaTag, export: FA.FaFileExport, search: FA.FaSearch, bell: FA.FaBell,
    lock: FA.FaLock, mobile: FA.FaMobileAlt, desktop: FA.FaDesktop,
    check: FA.FaCheckCircle, arrow: FA.FaArrowRight, db: FA.FaDatabase,
    restore: FA.FaTrashRestore, history: FA.FaHistory, ruler: FA.FaRulerCombined,
    sync: FA.FaSyncAlt, comment: FA.FaCommentDots, users: FA.FaUsers, times: FA.FaTimes,
  };
  const out = {};
  for (const [k, comp] of Object.entries(defs)) out[k] = await icon(comp, w);
  // varianty v navy pro světlá kolečka
  out.check_g = await icon(FA.FaCheckCircle, "#3FAE6A");
  out.times_r = await icon(FA.FaTimesCircle, "#C0563E");
  out.arrow_navy = await icon(FA.FaArrowRight, "#16243F");
  return out;
}

// ---------- helpers ----------
const pres = new pptxgen();
pres.defineLayout({ name: "W", width: 13.333, height: 7.5 });
pres.layout = "W";
pres.author = "Antonín Vojtěšek";
pres.title = "UNIFAST — přehled funkcí";

const PW = 13.333, PH = 7.5, M = 0.7;

function makeShadow() {
  return { type: "outer", color: "000000", blur: 8, offset: 3, angle: 90, opacity: 0.12 };
}

// hlavička světlého obsahového slidu
function header(slide, eyebrow, title) {
  slide.background = { color: LIGHT };
  slide.addText(eyebrow.toUpperCase(), {
    x: M, y: 0.42, w: 11, h: 0.3, fontFace: "Arial", fontSize: 12, bold: true,
    color: AMBER_D, charSpacing: 2, margin: 0,
  });
  slide.addText(title, {
    x: M, y: 0.68, w: PW - 2 * M, h: 0.7, fontFace: "Arial", fontSize: 30, bold: true,
    color: NAVY, margin: 0,
  });
}

// kolečko s ikonou
function iconCircle(slide, x, y, d, fill, iconData, pad) {
  slide.addShape(pres.shapes.OVAL, { x, y, w: d, h: d, fill: { color: fill }, shadow: makeShadow() });
  const p = pad === undefined ? d * 0.26 : pad;
  slide.addImage({ data: iconData, x: x + p, y: y + p, w: d - 2 * p, h: d - 2 * p });
}

// karta s ikonou + nadpis + popis
function featureCard(slide, x, y, w, h, iconData, circleColor, title, desc) {
  slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x, y, w, h, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow(),
  });
  const d = 0.62;
  iconCircle(slide, x + 0.28, y + 0.28, d, circleColor, iconData);
  slide.addText(title, {
    x: x + 0.28, y: y + 0.28 + d + 0.12, w: w - 0.56, h: 0.34,
    fontFace: "Arial", fontSize: 15, bold: true, color: NAVY, margin: 0,
  });
  slide.addText(desc, {
    x: x + 0.28, y: y + 0.28 + d + 0.50, w: w - 0.56, h: h - (0.28 + d + 0.50) - 0.2,
    fontFace: "Arial", fontSize: 11.5, color: MUTE, margin: 0, lineSpacingMultiple: 1.05,
  });
}

function pageNum(slide, n) {
  slide.addText(String(n), {
    x: PW - 1.0, y: PH - 0.5, w: 0.5, h: 0.3, align: "right",
    fontFace: "Arial", fontSize: 10, color: MUTE, margin: 0,
  });
  slide.addText("UNIFAST", {
    x: M, y: PH - 0.5, w: 3, h: 0.3, fontFace: "Arial", fontSize: 10, bold: true,
    color: MUTE, charSpacing: 1, margin: 0,
  });
}

// ====================================================================
(async () => {
  const I = await buildIcons();
  let pn = 0;

  // ---------- SLIDE 1: titul ----------
  {
    const s = pres.addSlide();
    s.background = { color: NAVY };
    // jemné kruhy jako motiv
    s.addShape(pres.shapes.OVAL, { x: 10.6, y: -1.6, w: 4.2, h: 4.2, fill: { color: NAVY2 } });
    s.addShape(pres.shapes.OVAL, { x: 11.8, y: 4.6, w: 3.2, h: 3.2, fill: { color: NAVY2 } });
    s.addText("UNIFAST", {
      x: M, y: 2.1, w: 10, h: 1.3, fontFace: "Arial", fontSize: 76, bold: true, color: WHITE, margin: 0,
    });
    s.addText("Firemní aplikace pro evidenci požárních ucpávek", {
      x: M, y: 3.5, w: 10.5, h: 0.6, fontFace: "Arial", fontSize: 22, color: "C7D4E8", margin: 0,
    });
    s.addShape(pres.shapes.RECTANGLE, { x: M, y: 4.35, w: 1.3, h: 0.06, fill: { color: AMBER } });
    s.addText("Kompletní přehled funkcí a možností", {
      x: M, y: 4.6, w: 10, h: 0.5, fontFace: "Arial", fontSize: 16, bold: true, color: AMBER, margin: 0,
    });
    s.addText("Podklad k prezentaci  •  Antonín Vojtěšek", {
      x: M, y: 6.5, w: 10, h: 0.4, fontFace: "Arial", fontSize: 13, color: "8A9BB8", margin: 0,
    });
    s.addNotes("Úvod: stará koupená aplikace uměla jen zápis ucpávek a stála dost peněz. Tohle je kompletní vlastní řešení postavené na míru naší práci.");
  }

  // ---------- SLIDE 2: odkud jdeme ----------
  {
    const s = pres.addSlide(); pn++;
    header(s, "Východisko", "Odkud jdeme");
    // dvě karty vedle sebe
    const y = 1.85, h = 4.3, w = 5.75;
    // stará
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M, y, w, h, rectRadius: 0.08, fill: { color: "EDE7E3" }, shadow: makeShadow() });
    iconCircle(s, M + 0.35, y + 0.35, 0.7, RED, I.times);
    s.addText("Stará aplikace", { x: M + 1.25, y: y + 0.45, w: w - 1.5, h: 0.5, fontFace: "Arial", fontSize: 20, bold: true, color: "7A3B2E", margin: 0 });
    s.addText("koupená, drahá", { x: M + 1.25, y: y + 0.92, w: w - 1.5, h: 0.3, fontFace: "Arial", fontSize: 12, italic: true, color: "9A6B5E", margin: 0 });
    s.addText([
      { text: "Pouze zápis ucpávek", options: { bullet: true, breakLine: true } },
      { text: "Nic víc — žádné fotky, výkresy, fakturace", options: { bullet: true, breakLine: true } },
      { text: "Bez práce offline", options: { bullet: true, breakLine: true } },
      { text: "Drahá a nevyhovující", options: { bullet: true } },
    ], { x: M + 0.4, y: y + 1.6, w: w - 0.8, h: 2.4, fontFace: "Arial", fontSize: 14.5, color: INK, paraSpaceAfter: 8, bullet: { indent: 14 } });

    // šipka (kolečko s ikonou, ať je vidět na světlém pozadí)
    iconCircle(s, 6.34, 3.75, 0.66, AMBER, I.arrow);

    // nová
    const x2 = PW - M - w;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x2, y, w, h, rectRadius: 0.08, fill: { color: "E7F0F7" }, shadow: makeShadow() });
    iconCircle(s, x2 + 0.35, y + 0.35, 0.7, GREEN, I.check);
    s.addText("UNIFAST", { x: x2 + 1.25, y: y + 0.45, w: w - 1.5, h: 0.5, fontFace: "Arial", fontSize: 20, bold: true, color: NAVY, margin: 0 });
    s.addText("vlastní, na míru", { x: x2 + 1.25, y: y + 0.92, w: w - 1.5, h: 0.3, fontFace: "Arial", fontSize: 12, italic: true, color: STEEL, margin: 0 });
    s.addText([
      { text: "Kompletní evidence ucpávek", options: { bullet: true, breakLine: true } },
      { text: "Fotky, výkresy, materiály, ceny", options: { bullet: true, breakLine: true } },
      { text: "Plná práce offline na stavbě", options: { bullet: true, breakLine: true } },
      { text: "Soupisy, fakturace, reporty, přehledy", options: { bullet: true } },
    ], { x: x2 + 0.4, y: y + 1.6, w: w - 0.8, h: 2.4, fontFace: "Arial", fontSize: 14.5, color: INK, paraSpaceAfter: 8, bullet: { indent: 14 } });
    pageNum(s, pn);
    s.addNotes("Hlavní pointa: stará appka uměla jednu věc. Tohle pokrývá celý proces.");
  }

  // ---------- SLIDE 3: co dělá - 5 pilířů ----------
  {
    const s = pres.addSlide(); pn++;
    header(s, "Přehled", "Co aplikace dělá");
    s.addText("Pět pilířů, které na sebe navazují — od zápisu v terénu po podklady k fakturaci.", {
      x: M, y: 1.5, w: PW - 2 * M, h: 0.4, fontFace: "Arial", fontSize: 14, color: MUTE, margin: 0,
    });
    const pillars = [
      [I.clipboard, BLUE, "Evidence ucpávek", "Zápis se všemi detaily, fotkami a materiály"],
      [I.wifi, AMBER, "Práce offline", "Funguje bez signálu, pak se vše samo odešle"],
      [I.map, STEEL, "Výkresy pater", "Zakreslení ucpávky do plánu klepnutím"],
      [I.invoice, "5B7C99", "Soupisy a fakturace", "Od rozpracováno až po vyfakturováno"],
      [I.chart, "4A6FA5", "Přehledy a dohled", "Statistiky, hledání, historie změn"],
    ];
    const n = pillars.length, gap = 0.3;
    const cw = (PW - 2 * M - (n - 1) * gap) / n;
    const y = 2.15, ch = 4.4;
    pillars.forEach((p, i) => {
      const x = M + i * (cw + gap);
      s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: cw, h: ch, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
      const d = 1.0;
      iconCircle(s, x + (cw - d) / 2, y + 0.45, d, p[1], p[0]);
      s.addText(String(i + 1), { x: x + 0.15, y: y + 0.2, w: 0.5, h: 0.4, fontFace: "Arial", fontSize: 18, bold: true, color: "C8D2E0", margin: 0 });
      s.addText(p[2], { x: x + 0.15, y: y + 1.7, w: cw - 0.3, h: 0.8, align: "center", fontFace: "Arial", fontSize: 14.5, bold: true, color: NAVY, margin: 0 });
      s.addText(p[3], { x: x + 0.2, y: y + 2.5, w: cw - 0.4, h: 1.6, align: "center", fontFace: "Arial", fontSize: 11.5, color: MUTE, margin: 0, lineSpacingMultiple: 1.05 });
    });
    pageNum(s, pn);
  }

  // ---------- SLIDE 4: role ----------
  {
    const s = pres.addSlide(); pn++;
    header(s, "Uživatelé", "Role a kdo s čím pracuje");
    s.addText("Každý vidí jen to, co potřebuje ke své práci.", {
      x: M, y: 1.5, w: 11, h: 0.4, fontFace: "Arial", fontSize: 14, color: MUTE, margin: 0,
    });
    const roles = [
      [I.hardhat, BLUE, "Pracovník", "Zapisuje ucpávky v terénu, fotí, zakresluje do výkresu, tvoří vlastní soupisy. Vidí jen své přiřazené stavby."],
      [I.tie, STEEL, "Vedení", "Zakládá stavby a patra, přiřazuje pracovníky, kontroluje a schvaluje, spravuje uživatele, exportuje data."],
      [I.calc, "5B7C99", "Účetní", "Pracuje se soupisy a podklady k fakturaci, spravuje ceník, tvoří reporty."],
      [I.shield, NAVY2, "Admin", "Plný přístup vč. koše a obnovy smazaných záznamů, správy všech účtů a záloh."],
    ];
    const gap = 0.3, n = roles.length;
    const cw = (PW - 2 * M - (n - 1) * gap) / n;
    const y = 2.1, ch = 4.4;
    roles.forEach((r, i) => featureCard(s, M + i * (cw + gap), y, cw, ch, r[0], r[1], r[2], r[3]));
    pageNum(s, pn);
  }

  // ---------- SLIDE 5: evidence ucpávek ----------
  {
    const s = pres.addSlide(); pn++;
    header(s, "Jádro aplikace", "Evidence ucpávek");
    // levý panel: co se eviduje
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M, y: 1.75, w: 6.4, h: 4.9, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
    iconCircle(s, M + 0.35, 2.1, 0.7, BLUE, I.clipboard);
    s.addText("U každé ucpávky se eviduje", { x: M + 1.25, y: 2.25, w: 5, h: 0.5, fontFace: "Arial", fontSize: 17, bold: true, color: NAVY, margin: 0 });
    s.addText([
      { text: "Číslo ucpávky — na patře vždy jedinečné (hlídá duplicity)", options: { bullet: true, breakLine: true } },
      { text: "Použitý systém (Hilti, Intuseal, Fischer, Protecta…)", options: { bullet: true, breakLine: true } },
      { text: "Typ konstrukce (beton, cihla, sádrokarton…)", options: { bullet: true, breakLine: true } },
      { text: "Umístění (stěna, strop, podlaha, šachta)", options: { bullet: true, breakLine: true } },
      { text: "Požární odolnost (60 / 90 / 120 minut)", options: { bullet: true, breakLine: true } },
      { text: "Poznámky — veřejné i interní", options: { bullet: true, breakLine: true } },
      { text: "Stav: rozpracováno → zkontrolováno → vyfakturováno", options: { bullet: true } },
    ], { x: M + 0.45, y: 3.0, w: 5.7, h: 3.4, fontFace: "Arial", fontSize: 13.5, color: INK, paraSpaceAfter: 9, bullet: { indent: 14 } });

    // pravý panel: prostupy a materiály
    const x2 = M + 6.4 + 0.4, w2 = PW - M - x2;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x2, y: 1.75, w: w2, h: 4.9, rectRadius: 0.08, fill: { color: "E7F0F7" }, shadow: makeShadow() });
    iconCircle(s, x2 + 0.35, 2.1, 0.7, AMBER, I.layers);
    s.addText("Prostupy a materiály", { x: x2 + 1.25, y: 2.25, w: 4, h: 0.5, fontFace: "Arial", fontSize: 17, bold: true, color: NAVY, margin: 0 });
    s.addText("Jedna ucpávka = více prostupů různého typu. U každého rozměr, počet kusů a materiály.", {
      x: x2 + 0.45, y: 2.95, w: w2 - 0.9, h: 0.8, fontFace: "Arial", fontSize: 13, color: INK, margin: 0, lineSpacingMultiple: 1.05,
    });
    s.addText([
      { text: "Typy: EL.V. • PVC • VZT • PROSTUP • OCEL", options: { bullet: true, breakLine: true } },
      { text: "Plochy a délky se počítají automaticky", options: { bullet: true, breakLine: true } },
      { text: "Cena se doplní z ceníku automaticky", options: { bullet: true } },
    ], { x: x2 + 0.45, y: 3.85, w: w2 - 0.9, h: 1.6, fontFace: "Arial", fontSize: 13.5, color: INK, paraSpaceAfter: 9, bullet: { indent: 14 } });
    s.addText("Změna ceníku nikdy zpětně nerozhodí hotové záznamy — ukládá se i platná verze ceníku.", {
      x: x2 + 0.45, y: 5.7, w: w2 - 0.9, h: 0.8, fontFace: "Arial", fontSize: 11.5, italic: true, color: STEEL, margin: 0, lineSpacingMultiple: 1.05,
    });
    pageNum(s, pn);
  }

  // ---------- SLIDE 6: fotky + výkresy ----------
  {
    const s = pres.addSlide(); pn++;
    header(s, "Dokumentace", "Fotky a výkresy pater");
    const y = 1.9, h = 4.4, w = 5.75;
    // fotky
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M, y, w, h, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
    iconCircle(s, M + 0.35, y + 0.35, 0.75, BLUE, I.camera);
    s.addText("Fotodokumentace", { x: M + 1.3, y: y + 0.5, w: w - 1.5, h: 0.5, fontFace: "Arial", fontSize: 19, bold: true, color: NAVY, margin: 0 });
    s.addText([
      { text: "Libovolný počet fotek ke každé ucpávce", options: { bullet: true, breakLine: true } },
      { text: "Automatické zmenšení — šetří místo i data", options: { bullet: true, breakLine: true } },
      { text: "Fotí se i offline, odešle se po připojení", options: { bullet: true, breakLine: true } },
      { text: "Pracovník fotky nemůže mazat (důkaz)", options: { bullet: true } },
    ], { x: M + 0.45, y: y + 1.45, w: w - 0.85, h: 2.7, fontFace: "Arial", fontSize: 14, color: INK, paraSpaceAfter: 11, bullet: { indent: 14 } });
    // výkresy
    const x2 = PW - M - w;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x2, y, w, h, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
    iconCircle(s, x2 + 0.35, y + 0.35, 0.75, AMBER, I.map);
    s.addText("Výkresy pater", { x: x2 + 1.3, y: y + 0.5, w: w - 1.5, h: 0.5, fontFace: "Arial", fontSize: 19, bold: true, color: NAVY, margin: 0 });
    s.addText([
      { text: "Vedení nahraje plán patra (PNG / JPG / PDF)", options: { bullet: true, breakLine: true } },
      { text: "Ve výkresu jsou vidět značky všech ucpávek", options: { bullet: true, breakLine: true } },
      { text: "Novou ucpávku založíš klepnutím do místa", options: { bullet: true, breakLine: true } },
      { text: "Značku lze posunout, výkres přiblížit", options: { bullet: true } },
    ], { x: x2 + 0.45, y: y + 1.45, w: w - 0.85, h: 2.7, fontFace: "Arial", fontSize: 14, color: INK, paraSpaceAfter: 11, bullet: { indent: 14 } });
    pageNum(s, pn);
  }

  // ---------- SLIDE 7: offline ----------
  {
    const s = pres.addSlide(); pn++;
    s.background = { color: NAVY };
    s.addShape(pres.shapes.OVAL, { x: 11.2, y: -1.4, w: 3.6, h: 3.6, fill: { color: NAVY2 } });
    s.addText("KLÍČOVÁ VÝHODA", { x: M, y: 0.7, w: 8, h: 0.3, fontFace: "Arial", fontSize: 12, bold: true, color: AMBER, charSpacing: 2, margin: 0 });
    s.addText("Práce bez signálu", { x: M, y: 1.0, w: 10, h: 0.8, fontFace: "Arial", fontSize: 34, bold: true, color: WHITE, margin: 0 });
    s.addText("Na stavbě často není signál. Aplikace s tím počítá — práce nikdy nečeká na internet.", {
      x: M, y: 1.85, w: 11.5, h: 0.5, fontFace: "Arial", fontSize: 15, color: "C7D4E8", margin: 0,
    });
    const items = [
      [I.db, "Vše hned lokálně", "Data se uloží přímo do zařízení, práce pokračuje i bez sítě."],
      [I.sync, "Automatické odeslání", "Jakmile je zařízení online, vše se samo odešle na server."],
      [I.shield, "Žádná ztráta dat", "Když dva upraví totéž, aplikace upozorní a nikdy nic tiše nepřepíše."],
      [I.check, "Opakované pokusy", "Odesílání se opakuje automaticky, dokud server vše nepotvrdí."],
    ];
    const gap = 0.35, n = items.length;
    const cw = (PW - 2 * M - (n - 1) * gap) / n;
    const y = 2.75, ch = 3.6;
    items.forEach((it, i) => {
      const x = M + i * (cw + gap);
      s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: cw, h: ch, rectRadius: 0.08, fill: { color: NAVY2 } });
      const d = 0.85;
      iconCircle(s, x + (cw - d) / 2, y + 0.4, d, AMBER, it[0]);
      s.addText(it[1], { x: x + 0.15, y: y + 1.45, w: cw - 0.3, h: 0.7, align: "center", fontFace: "Arial", fontSize: 14.5, bold: true, color: WHITE, margin: 0 });
      s.addText(it[2], { x: x + 0.2, y: y + 2.1, w: cw - 0.4, h: 1.4, align: "center", fontFace: "Arial", fontSize: 11.5, color: "AEBFD8", margin: 0, lineSpacingMultiple: 1.05 });
    });
    s.addText(String(pn), { x: PW - 1.0, y: PH - 0.5, w: 0.5, h: 0.3, align: "right", fontFace: "Arial", fontSize: 10, color: "8A9BB8", margin: 0 });
    pn++;
  }

  // ---------- SLIDE 8: soupisy / workflow ----------
  {
    const s = pres.addSlide();
    header(s, "Fakturace", "Soupisy práce a podklady k fakturaci");
    s.addText("Soupis je formální seznam odvedené práce, který prochází jasným schvalovacím procesem.", {
      x: M, y: 1.5, w: PW - 2 * M, h: 0.4, fontFace: "Arial", fontSize: 14, color: MUTE, margin: 0,
    });
    const steps = [
      ["Rozpracováno", "Pracovník", BLUE],
      ["Odevzdáno", "Pracovník", STEEL],
      ["Zkontrolováno", "Vedení", "4A6FA5"],
      ["Připraveno k fakturaci", "Vedení → Účetní", "5B7C99"],
      ["Vyfakturováno", "Účetní", AMBER_D],
    ];
    const y = 2.35, bh = 1.3;
    const gap = 0.32, n = steps.length;
    const bw = (PW - 2 * M - (n - 1) * gap) / n;
    steps.forEach((st, i) => {
      const x = M + i * (bw + gap);
      s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: bw, h: bh, rectRadius: 0.08, fill: { color: st[2] }, shadow: makeShadow() });
      s.addText(String(i + 1), { x: x + 0.12, y: y + 0.08, w: 0.5, h: 0.3, fontFace: "Arial", fontSize: 12, bold: true, color: "FFFFFF", transparency: 40, margin: 0 });
      s.addText(st[0], { x: x + 0.1, y: y + 0.32, w: bw - 0.2, h: 0.55, align: "center", valign: "middle", fontFace: "Arial", fontSize: 13.5, bold: true, color: WHITE, margin: 0 });
      s.addText(st[1], { x: x + 0.1, y: y + 0.88, w: bw - 0.2, h: 0.3, align: "center", fontFace: "Arial", fontSize: 10.5, color: "EAF1F8", margin: 0 });
      if (i < n - 1) {
        s.addText("›", { x: x + bw - 0.02, y: y + 0.25, w: gap + 0.04, h: 0.8, align: "center", valign: "middle", fontFace: "Arial", fontSize: 24, bold: true, color: "B0BAC9", margin: 0 });
      }
    });
    // spodní výhody
    const feats = [
      [I.clipboard, "Automatické naplnění soupisu ze zapsaných ucpávek"],
      [I.history, "Historie: kdo a kdy stav změnil; vedení může vrátit k opravě"],
      [I.export, "Export soupisu do PDF i CSV"],
    ];
    const fy = 4.25, fh = 1.9, fgap = 0.35;
    const fw = (PW - 2 * M - (feats.length - 1) * fgap) / feats.length;
    feats.forEach((f, i) => {
      const x = M + i * (fw + fgap);
      s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y: fy, w: fw, h: fh, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
      iconCircle(s, x + 0.3, fy + 0.35, 0.6, BLUE, f[0]);
      s.addText(f[1], { x: x + 0.3, y: fy + 1.05, w: fw - 0.6, h: 0.75, fontFace: "Arial", fontSize: 12.5, color: INK, margin: 0, lineSpacingMultiple: 1.05 });
    });
    pageNum(s, pn); pn++;
  }

  // ---------- SLIDE 9: ceník + reporty ----------
  {
    const s = pres.addSlide();
    header(s, "Ceny a výstupy", "Ceník, reporty a exporty");
    const y = 1.9, h = 4.4, w = 5.75;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M, y, w, h, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
    iconCircle(s, M + 0.35, y + 0.35, 0.75, AMBER, I.tag);
    s.addText("Ceník", { x: M + 1.3, y: y + 0.5, w: w - 1.5, h: 0.5, fontFace: "Arial", fontSize: 19, bold: true, color: NAVY, margin: 0 });
    s.addText([
      { text: "Ceny prostupů na jednom místě", options: { bullet: true, breakLine: true } },
      { text: "Verzovaný — platnost od/do, historie cen", options: { bullet: true, breakLine: true } },
      { text: "Cena se při zápisu doplní automaticky", options: { bullet: true, breakLine: true } },
      { text: "Uloží se i verze ceníku, která platila", options: { bullet: true } },
    ], { x: M + 0.45, y: y + 1.45, w: w - 0.85, h: 2.7, fontFace: "Arial", fontSize: 14, color: INK, paraSpaceAfter: 11, bullet: { indent: 14 } });

    const x2 = PW - M - w;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x2, y, w, h, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
    iconCircle(s, x2 + 0.35, y + 0.35, 0.75, BLUE, I.export);
    s.addText("Reporty a exporty", { x: x2 + 1.3, y: y + 0.5, w: w - 1.5, h: 0.5, fontFace: "Arial", fontSize: 19, bold: true, color: NAVY, margin: 0 });
    s.addText([
      { text: "Export do PDF i CSV (účetnictví, archiv)", options: { bullet: true, breakLine: true } },
      { text: "Filtry: stavba, patro, pracovník, období, stav…", options: { bullet: true, breakLine: true } },
      { text: "Hromadné operace nad více ucpávkami", options: { bullet: true, breakLine: true } },
      { text: "Každý vidí jen data, na která má právo", options: { bullet: true } },
    ], { x: x2 + 0.45, y: y + 1.45, w: w - 0.85, h: 2.7, fontFace: "Arial", fontSize: 14, color: INK, paraSpaceAfter: 11, bullet: { indent: 14 } });
    pageNum(s, pn); pn++;
  }

  // ---------- SLIDE 10: další funkce (grid) ----------
  {
    const s = pres.addSlide();
    header(s, "A k tomu navíc", "Další funkce");
    const cards = [
      [I.search, BLUE, "Vyhledávání", "Globální hledání napříč stavbami, patry, ucpávkami i pracovníky."],
      [I.chart, STEEL, "Dashboard", "Přehled statistik podle role — rozpracované, ke kontrole, výkon."],
      [I.comment, "5B7C99", "Komunikace", "Zprávy mezi uživateli a notifikace u důležitých změn."],
      [I.history, "4A6FA5", "Historie změn", "Kdo, kdy a co změnil — vč. původní a nové hodnoty."],
      [I.restore, AMBER_D, "Koš a obnova", "Nic se nemaže natrvalo; admin smazané záznamy obnoví."],
      [I.lock, NAVY2, "Bezpečnost", "Přihlášení PINem, role a oprávnění, automatické zálohy."],
    ];
    const cols = 3, rows = 2, gap = 0.35;
    const cw = (PW - 2 * M - (cols - 1) * gap) / cols;
    const top = 1.85, ch = 2.25, vgap = 0.3;
    cards.forEach((c, i) => {
      const col = i % cols, row = Math.floor(i / cols);
      const x = M + col * (cw + gap);
      const y = top + row * (ch + vgap);
      s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x, y, w: cw, h: ch, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
      iconCircle(s, x + 0.3, y + 0.3, 0.62, c[1], c[0]);
      s.addText(c[2], { x: x + 1.1, y: y + 0.42, w: cw - 1.3, h: 0.5, fontFace: "Arial", fontSize: 15.5, bold: true, color: NAVY, margin: 0, valign: "middle" });
      s.addText(c[3], { x: x + 0.3, y: y + 1.1, w: cw - 0.6, h: 1.0, fontFace: "Arial", fontSize: 11.5, color: MUTE, margin: 0, lineSpacingMultiple: 1.05 });
    });
    pageNum(s, pn); pn++;
  }

  // ---------- SLIDE 11: kde to běží ----------
  {
    const s = pres.addSlide();
    header(s, "Dostupnost", "Kde to běží");
    const y = 1.95, h = 3.7, w = 5.4;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M, y, w, h, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
    iconCircle(s, M + (w - 1.1) / 2, y + 0.5, 1.1, BLUE, I.mobile);
    s.addText("Android", { x: M, y: y + 1.85, w, h: 0.5, align: "center", fontFace: "Arial", fontSize: 22, bold: true, color: NAVY, margin: 0 });
    s.addText("Telefony a tablety do terénu — hotová aplikace (APK)", { x: M + 0.4, y: y + 2.45, w: w - 0.8, h: 1.0, align: "center", fontFace: "Arial", fontSize: 13, color: MUTE, margin: 0, lineSpacingMultiple: 1.05 });

    const x2 = PW - M - w;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x2, y, w, h, rectRadius: 0.08, fill: { color: CARD }, shadow: makeShadow() });
    iconCircle(s, x2 + (w - 1.1) / 2, y + 0.5, 1.1, STEEL, I.desktop);
    s.addText("Windows", { x: x2, y: y + 1.85, w, h: 0.5, align: "center", fontFace: "Arial", fontSize: 22, bold: true, color: NAVY, margin: 0 });
    s.addText("Počítače v kanceláři — hotová verze pro Windows", { x: x2 + 0.4, y: y + 2.45, w: w - 0.8, h: 1.0, align: "center", fontFace: "Arial", fontSize: 13, color: MUTE, margin: 0, lineSpacingMultiple: 1.05 });

    s.addText("Data jsou na společném serveru — všichni pracují nad stejnými aktuálními údaji.", {
      x: M, y: 6.0, w: PW - 2 * M, h: 0.5, align: "center", fontFace: "Arial", fontSize: 14, italic: true, color: STEEL, margin: 0,
    });
    pageNum(s, pn); pn++;
  }

  // ---------- SLIDE 12: srovnání tabulka ----------
  {
    const s = pres.addSlide();
    header(s, "Shrnutí", "Stará aplikace vs. UNIFAST");
    const rows = [
      ["Zápis ucpávek", true, true],
      ["Fotodokumentace", false, true],
      ["Výkresy pater a zakreslení", false, true],
      ["Práce offline bez signálu", false, true],
      ["Materiály a automatické ceny", false, true],
      ["Soupisy práce a fakturace", false, true],
      ["Reporty a exporty (PDF/CSV)", false, true],
      ["Role, oprávnění, historie změn", false, true],
      ["Koš, obnova, statistiky, hledání", false, true],
    ];
    const tx = M, tw = PW - 2 * M, ty = 1.75;
    const c1 = tw * 0.56, c2 = tw * 0.22, c3 = tw * 0.22;
    const rh = 0.43, hh = 0.5;
    // hlavička
    s.addShape(pres.shapes.RECTANGLE, { x: tx, y: ty, w: c1, h: hh, fill: { color: NAVY } });
    s.addShape(pres.shapes.RECTANGLE, { x: tx + c1, y: ty, w: c2, h: hh, fill: { color: NAVY } });
    s.addShape(pres.shapes.RECTANGLE, { x: tx + c1 + c2, y: ty, w: c3, h: hh, fill: { color: AMBER_D } });
    s.addText("Funkce", { x: tx + 0.2, y: ty, w: c1 - 0.3, h: hh, valign: "middle", fontFace: "Arial", fontSize: 13, bold: true, color: WHITE, margin: 0 });
    s.addText("Stará appka", { x: tx + c1, y: ty, w: c2, h: hh, align: "center", valign: "middle", fontFace: "Arial", fontSize: 13, bold: true, color: WHITE, margin: 0 });
    s.addText("UNIFAST", { x: tx + c1 + c2, y: ty, w: c3, h: hh, align: "center", valign: "middle", fontFace: "Arial", fontSize: 13, bold: true, color: WHITE, margin: 0 });
    rows.forEach((r, i) => {
      const y = ty + hh + i * rh;
      const bg = i % 2 ? "EAEFF5" : CARD;
      s.addShape(pres.shapes.RECTANGLE, { x: tx, y, w: tw, h: rh, fill: { color: bg } });
      s.addText(r[0], { x: tx + 0.2, y, w: c1 - 0.3, h: rh, valign: "middle", fontFace: "Arial", fontSize: 12.5, color: INK, margin: 0 });
      const ic1 = r[1] ? I.check_g : I.times_r;
      const ic2 = r[2] ? I.check_g : I.times_r;
      s.addImage({ data: ic1, x: tx + c1 + c2 / 2 - 0.13, y: y + (rh - 0.26) / 2, w: 0.26, h: 0.26 });
      s.addImage({ data: ic2, x: tx + c1 + c2 + c3 / 2 - 0.13, y: y + (rh - 0.26) / 2, w: 0.26, h: 0.26 });
    });
    pageNum(s, pn); pn++;
  }

  // ---------- SLIDE 13: závěr ----------
  {
    const s = pres.addSlide();
    s.background = { color: NAVY };
    s.addShape(pres.shapes.OVAL, { x: -1.5, y: 4.8, w: 4, h: 4, fill: { color: NAVY2 } });
    s.addShape(pres.shapes.OVAL, { x: 11.5, y: -1.5, w: 3.6, h: 3.6, fill: { color: NAVY2 } });
    s.addText("ZÁVĚR", { x: M, y: 0.7, w: 8, h: 0.3, fontFace: "Arial", fontSize: 12, bold: true, color: AMBER, charSpacing: 2, margin: 0 });
    s.addText("Aktuální stav a co dál", { x: M, y: 1.0, w: 11, h: 0.8, fontFace: "Arial", fontSize: 34, bold: true, color: WHITE, margin: 0 });

    // stav dnes
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: M, y: 2.1, w: 5.75, h: 3.5, rectRadius: 0.08, fill: { color: NAVY2 } });
    iconCircle(s, M + 0.35, 2.45, 0.7, GREEN, I.check);
    s.addText("Stav dnes", { x: M + 1.25, y: 2.6, w: 4, h: 0.5, fontFace: "Arial", fontSize: 19, bold: true, color: WHITE, margin: 0 });
    s.addText([
      { text: "Aplikace je hotová a funkční — běží a používá se", options: { bullet: true, breakLine: true } },
      { text: "Hotové verze pro Android i Windows", options: { bullet: true, breakLine: true } },
      { text: "Otestováno (automatické testy)", options: { bullet: true } },
    ], { x: M + 0.45, y: 3.45, w: 5.0, h: 2.0, fontFace: "Arial", fontSize: 14, color: "D7E1F0", paraSpaceAfter: 10, bullet: { indent: 14 } });

    // co dál
    const x2 = PW - M - 5.75;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, { x: x2, y: 2.1, w: 5.75, h: 3.5, rectRadius: 0.08, fill: { color: NAVY2 } });
    iconCircle(s, x2 + 0.35, 2.45, 0.7, AMBER, I.arrow);
    s.addText("Možnosti dalšího rozvoje", { x: x2 + 1.25, y: 2.6, w: 4.3, h: 0.5, fontFace: "Arial", fontSize: 19, bold: true, color: WHITE, margin: 0 });
    s.addText([
      { text: "Nasazení na firemní/cloudový server (HTTPS)", options: { bullet: true, breakLine: true } },
      { text: "Podpis aplikací pro snadnou distribuci", options: { bullet: true, breakLine: true } },
      { text: "Doplnění funkcí podle přání firmy", options: { bullet: true } },
    ], { x: x2 + 0.45, y: 3.45, w: 5.0, h: 2.0, fontFace: "Arial", fontSize: 14, color: "D7E1F0", paraSpaceAfter: 10, bullet: { indent: 14 } });

    s.addText("Postaveno na míru reálné práci s ucpávkami — bez přizpůsobování se cizí aplikaci.", {
      x: M, y: 6.05, w: PW - 2 * M, h: 0.5, align: "center", fontFace: "Arial", fontSize: 15, bold: true, color: AMBER, margin: 0,
    });
    s.addText(String(pn), { x: PW - 1.0, y: PH - 0.5, w: 0.5, h: 0.3, align: "right", fontFace: "Arial", fontSize: 10, color: "8A9BB8", margin: 0 });
  }

  await pres.writeFile({ fileName: "Unifast-prezentace.pptx" });
  console.log("OK: Unifast-prezentace.pptx");
})();
