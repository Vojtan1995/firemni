const fs = require("fs");
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  AlignmentType, LevelFormat, HeadingLevel, BorderStyle, WidthType,
  ShadingType, TableOfContents, PageNumber, PageBreak, Header, Footer,
} = require("docx");

// ---- barvy / vzhled ----
const BLUE = "1F4E79";
const LIGHTBLUE = "D6E4F0";
const GREY = "F2F2F2";
const GREEN = "E2EFDA";

const CONTENT_WIDTH = 9360; // US Letter, 1" okraje

const border = { style: BorderStyle.SINGLE, size: 1, color: "BBBBBB" };
const borders = { top: border, bottom: border, left: border, right: border };
const cellMargins = { top: 60, bottom: 60, left: 120, right: 120 };

// pomocné funkce
function h1(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_1, children: [new TextRun(text)] });
}
function h2(text) {
  return new Paragraph({ heading: HeadingLevel.HEADING_2, children: [new TextRun(text)] });
}
function p(text, opts = {}) {
  return new Paragraph({
    spacing: { after: 120 },
    children: [new TextRun({ text, ...opts })],
  });
}
function bullet(text, level = 0) {
  return new Paragraph({
    numbering: { reference: "bul", level },
    spacing: { after: 40 },
    children: typeof text === "string" ? [new TextRun(text)] : text,
  });
}
function bulletRuns(runs, level = 0) {
  return new Paragraph({
    numbering: { reference: "bul", level },
    spacing: { after: 40 },
    children: runs,
  });
}

function headerCell(text, width) {
  return new TableCell({
    borders, width: { size: width, type: WidthType.DXA }, margins: cellMargins,
    shading: { fill: BLUE, type: ShadingType.CLEAR },
    children: [new Paragraph({ children: [new TextRun({ text, bold: true, color: "FFFFFF", size: 20 })] })],
  });
}
function cell(text, width, opts = {}) {
  const runs = Array.isArray(text)
    ? text
    : [new TextRun({ text: String(text), size: 20, bold: opts.bold || false })];
  return new TableCell({
    borders, width: { size: width, type: WidthType.DXA }, margins: cellMargins,
    shading: opts.fill ? { fill: opts.fill, type: ShadingType.CLEAR } : undefined,
    children: [new Paragraph({ alignment: opts.align || AlignmentType.LEFT, children: runs })],
  });
}

function table(widths, headerLabels, rows, rowShade) {
  const headerRow = new TableRow({
    tableHeader: true,
    children: headerLabels.map((l, i) => headerCell(l, widths[i])),
  });
  const bodyRows = rows.map((r, ri) =>
    new TableRow({
      children: r.map((c, i) =>
        cell(c, widths[i], { fill: rowShade && ri % 2 === 1 ? GREY : undefined })
      ),
    })
  );
  return new Table({
    width: { size: CONTENT_WIDTH, type: WidthType.DXA },
    columnWidths: widths,
    rows: [headerRow, ...bodyRows],
  });
}

function spacer() {
  return new Paragraph({ spacing: { after: 120 }, children: [new TextRun("")] });
}

// ================= OBSAH DOKUMENTU =================
const children = [];

// --- Titulní strana ---
children.push(new Paragraph({ spacing: { before: 2400, after: 0 }, alignment: AlignmentType.CENTER,
  children: [new TextRun({ text: "UNIFAST", bold: true, size: 72, color: BLUE })] }));
children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 240 },
  children: [new TextRun({ text: "Firemní aplikace pro evidenci požárních ucpávek", size: 30, color: "555555" })] }));
children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { after: 80 },
  children: [new TextRun({ text: "Kompletní přehled funkcí a možností", size: 26, bold: true })] }));
children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 1600 },
  children: [new TextRun({ text: "Podklad k prezentaci", size: 22, color: "777777" })] }));
children.push(new Paragraph({ alignment: AlignmentType.CENTER, spacing: { before: 120 },
  children: [new TextRun({ text: "Antonín Vojtěšek", size: 22 })] }));
children.push(new Paragraph({ children: [new PageBreak()] }));

// --- Obsah ---
children.push(h1("Obsah"));
children.push(new TableOfContents("Obsah", { hyperlink: true, headingStyleRange: "1-2" }));
children.push(new Paragraph({ children: [new PageBreak()] }));

// --- 1. Shrnutí ---
children.push(h1("Ve zkratce"));
children.push(p("UNIFAST je interní firemní aplikace pro evidenci požárních (a stavebních) ucpávek přímo na stavbě. Vznikla jako náhrada za dříve zakoupenou aplikaci, která uměla pouze zapsat ucpávku a nic víc."));
children.push(p("Oproti tomu UNIFAST pokrývá celý pracovní proces od zápisu ucpávky v terénu, přes fotodokumentaci a zakreslení do výkresu, až po soupisy práce, podklady k fakturaci, reporty a kompletní přehled o tom, kdo, kdy a co udělal."));
children.push(spacer());
children.push(h2("Čísla, která ukazují rozsah"));
children.push(table([3120, 3120, 3120],
  ["", "", ""],
  [
    [[new TextRun({ text: "25+", bold: true, size: 36, color: BLUE })], [new TextRun({ text: "60+", bold: true, size: 36, color: BLUE })], [new TextRun({ text: "4", bold: true, size: 36, color: BLUE })]],
    ["obrazovek a funkcí", "serverových funkcí (API)", "uživatelské role"],
  ]
));
children.push(spacer());
children.push(table([3120, 3120, 3120],
  ["", "", ""],
  [
    [[new TextRun({ text: "2", bold: true, size: 36, color: BLUE })], [new TextRun({ text: "100 %", bold: true, size: 36, color: BLUE })], [new TextRun({ text: "0", bold: true, size: 36, color: BLUE })]],
    ["platformy (Android, Windows)", "funkční offline (bez signálu)", "ztráty dat při výpadku sítě"],
  ]
));

// --- 2. Co aplikace dělá ---
children.push(h1("Co aplikace dělá"));
children.push(p("Aplikaci si lze představit jako pět hlavních pilířů, které na sebe navazují:"));
children.push(bulletRuns([new TextRun({ text: "Evidence ucpávek — ", bold: true }), new TextRun("jádro celé aplikace. Zápis každé ucpávky s veškerými detaily, fotkami a materiály.")]));
children.push(bulletRuns([new TextRun({ text: "Práce v terénu bez signálu — ", bold: true }), new TextRun("vše funguje offline, data se po připojení sama odešlou na server.")]));
children.push(bulletRuns([new TextRun({ text: "Výkresy pater — ", bold: true }), new TextRun("zakreslení ucpávky přímo do plánu patra jedním klepnutím.")]));
children.push(bulletRuns([new TextRun({ text: "Soupisy práce a podklady k fakturaci — ", bold: true }), new TextRun("od rozpracovaného soupisu až po vyfakturováno, vč. ceníku a exportů.")]));
children.push(bulletRuns([new TextRun({ text: "Přehledy a dohled — ", bold: true }), new TextRun("statistiky, vyhledávání, kompletní historie změn a koš s obnovou.")]));

// --- 3. Role ---
children.push(h1("Role a kdo s čím pracuje"));
children.push(p("Aplikace rozlišuje čtyři role. Každý uživatel vidí jen to, co potřebuje ke své práci."));
children.push(table([1700, 7660],
  ["Role", "Co dělá"],
  [
    ["Pracovník", "Zapisuje ucpávky v terénu, fotí, zakresluje do výkresu, vytváří vlastní soupisy. Vidí jen stavby, na které je přiřazen."],
    ["Vedení", "Zakládá stavby a patra, přiřazuje pracovníky, kontroluje a schvaluje ucpávky, spravuje uživatele, exportuje data."],
    ["Účetní", "Pracuje se soupisy a podklady k fakturaci, spravuje ceník, dělá reporty."],
    ["Admin", "Plný přístup vč. koše a obnovy smazaných záznamů, správy všech účtů a záloh."],
  ], true
));

// --- 4. Evidence ucpávek ---
children.push(h1("Jádro: evidence ucpávek"));
children.push(p("U každé ucpávky se eviduje vše potřebné pro pozdější kontrolu i fakturaci:"));
children.push(bullet("Číslo ucpávky (na patře je vždy jedinečné — aplikace hlídá duplicity)"));
children.push(bullet("Použitý systém (např. Hilti, Intuseal, Fischer, Protecta…)"));
children.push(bullet("Typ konstrukce (beton, cihla, sádrokarton…) a umístění (stěna, strop, podlaha, šachta)"));
children.push(bullet("Požární odolnost (např. 60 / 90 / 120 minut)"));
children.push(bullet("Poznámky (veřejné i interní)"));
children.push(bullet("Stav: rozpracováno → zkontrolováno → vyfakturováno"));
children.push(spacer());
children.push(h2("Položky prostupů a materiály"));
children.push(p("Každá ucpávka může obsahovat více prostupů různého typu. U každého se eviduje rozměr, počet kusů a použité materiály:"));
children.push(table([2200, 4360, 2800],
  ["Typ prostupu", "Co se zadává", "Výpočet"],
  [
    ["EL.V. (elektro)", "průměr (přednastavené hodnoty i vlastní)", "automaticky"],
    ["PVC", "šířka × délka", "plocha / délka"],
    ["VZT (vzduchotechnika)", "rozměry potrubí", "plocha / délka"],
    ["PROSTUP", "rozměr dle izolace", "plocha"],
    ["OCEL", "průměr", "automaticky"],
  ], true
));
children.push(spacer());
children.push(p("Cena se k položce doplní automaticky z ceníku a uloží se i s tím, jaká verze ceníku platila — pozdější změna ceníku tedy nikdy zpětně nerozhodí už hotové záznamy.", { italics: true }));

// --- 5. Fotky ---
children.push(h1("Fotodokumentace"));
children.push(bullet("Ke každé ucpávce lze přidat libovolný počet fotek (z fotoaparátu i galerie)."));
children.push(bullet("Fotky se automaticky zmenší, aby šetřily místo i data, ale zůstaly čitelné."));
children.push(bullet("Fotky se nahrávají i offline — počkají ve frontě a odešlou se po připojení."));
children.push(bullet("Pracovník nemůže fotky mazat — slouží jako důkazní dokumentace (audit)."));

// --- 6. Výkresy ---
children.push(h1("Výkresy pater"));
children.push(bullet("Vedení nahraje plán patra (PNG, JPG nebo PDF)."));
children.push(bullet("Pracovník vidí ve výkresu značky všech ucpávek na patře."));
children.push(bullet("Novou ucpávku založí klepnutím přímo do místa ve výkresu."));
children.push(bullet("Značku lze tažením posunout; výkres lze přibližovat a posouvat."));

// --- 7. Offline ---
children.push(h1("Práce bez signálu (offline režim)"));
children.push(p("Toto je jedna z nejdůležitějších vlastností — na stavbě často není signál."));
children.push(bullet("Vše se nejdřív uloží do telefonu/notebooku, takže práce nikdy nečeká na internet."));
children.push(bullet("Jakmile je zařízení online, data se sama odešlou na server."));
children.push(bullet("Když dva lidé upraví to samé, aplikace na to upozorní a nikdy nic tiše nepřepíše — nehrozí ztráta dat."));
children.push(bullet("Odesílání se opakuje automaticky, dokud server vše nepotvrdí."));

// --- 8. Soupisy ---
children.push(h1("Soupisy práce a podklady k fakturaci"));
children.push(p("Soupis práce je formální seznam odvedené práce na stavbě, který prochází jasným schvalovacím procesem:"));
children.push(table([3400, 3400, 2560],
  ["Stav", "Kdo posouvá dál", "Význam"],
  [
    ["Rozpracováno", "Pracovník", "Doplňují se položky"],
    ["Odevzdáno", "Pracovník", "Předáno ke kontrole"],
    ["Zkontrolováno", "Vedení", "Schváleno vedením"],
    ["Připraveno k fakturaci", "Vedení → Účetní", "Předáno účetní"],
    ["Vyfakturováno", "Účetní", "Uzavřeno"],
  ], true
));
children.push(spacer());
children.push(bullet("Soupis lze automaticky naplnit z již zapsaných ucpávek."));
children.push(bullet("U každého kroku se ukládá, kdo a kdy stav změnil (historie)."));
children.push(bullet("Vedení může soupis vrátit zpět k opravě."));
children.push(bullet("Soupis lze vyexportovat do PDF i CSV."));

// --- 9. Ceník ---
children.push(h1("Ceník"));
children.push(bullet("Ceny jednotlivých typů prostupů jsou na jednom místě ve verzovaném ceníku."));
children.push(bullet("Ceník má platnost od/do — historie cen zůstává dohledatelná."));
children.push(bullet("Při zápisu ucpávky se cena doplní automaticky a uloží se s aktuální verzí ceníku."));

// --- 10. Reporty ---
children.push(h1("Reporty a exporty"));
children.push(bullet("Export do PDF i CSV (např. pro účetnictví nebo archiv)."));
children.push(bullet("Filtry: stavba, patro, pracovník, období, stav, typ prostupu, materiál."));
children.push(bullet("Hromadné operace — např. změna stavu nebo přesun více ucpávek najednou."));
children.push(bullet("Každý vidí jen data, na která má právo (pracovník svoje, vedení vše)."));

// --- 11. Vyhledávání a přehledy ---
children.push(h1("Vyhledávání a přehledy"));
children.push(bullet("Globální vyhledávání napříč stavbami, patry, ucpávkami i pracovníky."));
children.push(bullet("Přehledová obrazovka (dashboard) se statistikami podle role — kolik je rozpracovaných, kolik čeká na kontrolu, výkon pracovníků apod."));

// --- 12. Komunikace ---
children.push(h1("Komunikace"));
children.push(bullet("Zprávy mezi uživateli přímo v aplikaci."));
children.push(bullet("Notifikace při důležitých změnách (např. ucpávka ke kontrole)."));

// --- 13. Bezpečnost ---
children.push(h1("Bezpečnost a dohled"));
children.push(bullet("Přihlášení jménem a PINem (6–8 číslic)."));
children.push(bullet("Role a oprávnění — každý vidí jen to, co má."));
children.push(bullet("Kompletní historie: kdo, kdy a co změnil (vč. původní a nové hodnoty)."));
children.push(bullet("Žádné trvalé mazání — smazané záznamy jdou do koše a admin je může obnovit."));
children.push(bullet("Záznam pokusů o přihlášení a automatické zálohy databáze."));

// --- 14. Kde to běží ---
children.push(h1("Kde to běží"));
children.push(bullet("Android — hotová aplikace (APK) pro telefony a tablety do terénu."));
children.push(bullet("Windows — hotová verze pro počítače v kanceláři."));
children.push(bullet("Data jsou na společném serveru, všichni pracují nad stejnými aktuálními údaji."));

// --- 15. Kompletní seznam funkcí ---
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(h1("Kompletní seznam funkcí"));
children.push(p("Přehled všeho, co je v aplikaci hotové a funkční:"));
const featureGroups = [
  ["Evidence ucpávek", ["Zápis ucpávky se všemi detaily", "Více prostupů na jednu ucpávku", "Materiály u každého prostupu", "Automatický výpočet ploch a délek", "Automatická cena z ceníku", "Kontrola duplicitních čísel", "Stavy ucpávky (rozpracováno/zkontrolováno/vyfakturováno)", "Veřejné i interní poznámky", "Historie změn ucpávky"]],
  ["Terén a offline", ["Plný offline režim", "Automatická synchronizace", "Řešení konfliktů bez ztráty dat", "Opakované odesílání při výpadku", "Paměť „pokračovat v práci“"]],
  ["Fotky a výkresy", ["Fotky ke každé ucpávce", "Automatická komprese fotek", "Offline fronta nahrávání", "Nahrání výkresu patra (PNG/JPG/PDF)", "Zakreslení ucpávky do výkresu klepnutím", "Posouvání značek, přiblížení/posun"]],
  ["Soupisy a fakturace", ["Soupisy práce se schvalovacím procesem", "Automatické naplnění soupisu z ucpávek", "Vrácení soupisu k opravě", "Export soupisu PDF/CSV", "Verzovaný ceník", "Historie cen"]],
  ["Přehledy a export", ["Reporty s filtry", "Export PDF a CSV", "Hromadné operace", "Globální vyhledávání", "Dashboard se statistikami"]],
  ["Správa a bezpečnost", ["4 role s oprávněními", "Přihlášení PINem + změna PINu", "Správa uživatelů", "Správa staveb a pater", "Přiřazení pracovníků ke stavbám", "Kompletní historie změn (audit)", "Koš a obnova smazaných", "Záznam přihlášení", "Automatické zálohy", "Zprávy a notifikace", "Kontrola aktualizací aplikace"]],
];
featureGroups.forEach(([title, items]) => {
  children.push(new Paragraph({ spacing: { before: 160, after: 60 }, children: [new TextRun({ text: title, bold: true, color: BLUE, size: 24 })] }));
  items.forEach((it) => children.push(bullet(it)));
});

// --- 16. Srovnání ---
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(h1("Srovnání: stará aplikace vs. UNIFAST"));
children.push(table([4680, 2340, 2340],
  ["Oblast", "Stará aplikace", "UNIFAST"],
  [
    ["Zápis ucpávek", "Ano", "Ano"],
    ["Fotodokumentace", "Ne", "Ano"],
    ["Výkresy pater a zakreslení", "Ne", "Ano"],
    ["Práce offline bez signálu", "Ne", "Ano"],
    ["Materiály a automatický výpočet cen", "Ne", "Ano"],
    ["Ceník s historií", "Ne", "Ano"],
    ["Soupisy práce a fakturace", "Ne", "Ano"],
    ["Reporty a exporty (PDF/CSV)", "Ne", "Ano"],
    ["Role a oprávnění", "Ne", "Ano"],
    ["Historie změn (kdo/kdy/co)", "Ne", "Ano"],
    ["Koš a obnova dat", "Ne", "Ano"],
    ["Statistiky a vyhledávání", "Ne", "Ano"],
  ], true
));
children.push(spacer());
children.push(new Paragraph({ shading: { fill: GREEN, type: ShadingType.CLEAR },
  spacing: { before: 120, after: 120 },
  children: [new TextRun({ text: "Stará aplikace uměla jednu věc. UNIFAST pokrývá celý pracovní proces.", bold: true, size: 24 })] }));

// --- 17. Závěr ---
children.push(h1("Aktuální stav a co dál"));
children.push(h2("Stav dnes"));
children.push(bullet("Aplikace je hotová a funkční — běží a používá se."));
children.push(bullet("Hotové verze pro Android i Windows."));
children.push(bullet("Otestováno (automatické testy backendu i aplikace)."));
children.push(h2("Možnosti dalšího rozvoje"));
children.push(bullet("Nasazení na firemní/cloudový server s bezpečným připojením (HTTPS)."));
children.push(bullet("Podpis aplikací pro snadnou distribuci a případně zveřejnění."));
children.push(bullet("Úpravy a doplnění funkcí podle konkrétních přání firmy."));
children.push(spacer());
children.push(p("Veškeré funkce v tomto dokumentu byly navrženy a postaveny na míru reálné práci s ucpávkami — bez vnuceného přizpůsobování se cizí aplikaci.", { italics: true }));

// ================= DOKUMENT =================
const doc = new Document({
  creator: "Antonín Vojtěšek",
  title: "UNIFAST — přehled funkcí",
  styles: {
    default: { document: { run: { font: "Arial", size: 22 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 30, bold: true, font: "Arial", color: BLUE },
        paragraph: { spacing: { before: 280, after: 160 }, outlineLevel: 0,
          border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: BLUE, space: 4 } } } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 25, bold: true, font: "Arial", color: "333333" },
        paragraph: { spacing: { before: 180, after: 100 }, outlineLevel: 1 } },
    ],
  },
  numbering: {
    config: [
      { reference: "bul", levels: [
        { level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 540, hanging: 280 } } } },
        { level: 1, format: LevelFormat.BULLET, text: "–", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 1080, hanging: 280 } } } },
      ] },
    ],
  },
  sections: [{
    properties: { page: {
      size: { width: 12240, height: 15840 },
      margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
    } },
    footers: { default: new Footer({ children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: "UNIFAST — přehled funkcí    |    strana ", size: 16, color: "888888" }),
        new TextRun({ children: [PageNumber.CURRENT], size: 16, color: "888888" })],
    })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then((buffer) => {
  fs.writeFileSync("Unifast-prehled-funkci.docx", buffer);
  console.log("OK: Unifast-prehled-funkci.docx (" + buffer.length + " B)");
});
