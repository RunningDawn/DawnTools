// Writes ../DawnTools_Seed/BisProfiles.lua (the seed addon beside DawnTools: in no download and no repository, as
// these numbers are not cleared for passing on; see THIRD_PARTY_LICENSES.txt): what a point of each stat is worth to every class and spec, and its caps.
//   node tools/bisweights.js
// Read from tools/bis/*.json: the numbers as two WoW: Forever sites publish them, taken down by hand
// (see THIRD_PARTY_LICENSES.txt):
//   mythicsim_*.json  mythicsim.com/wow-forever/stat-priority/<slug>: damage (tanks: threat) per point, measured
//   wfb_*.json        wowforeverbislist.com/preraid/<class>/<spec>/: WoWSims values, healers and tanks too
// The rule: damage specs from MythicSim; healers, and what keeps a tank alive, from wowforeverbislist. A tank
// that both sites have is wowforeverbislist's values, with MythicSim's threat values for the stats it leaves
// out, brought to its scale at a stat both have.
// Units in the output: hit, crit, haste and expertise per 1% (MythicSim gives them per point of rating:
// 10, 14, 10, 10 rating a percent on client 1.60.1); everything else per point.
const fs = require('fs');
const path = require('path');
const dir = path.join(__dirname, 'bis');
const read = (...files) => files.flatMap(f => JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')));
const MS = Object.fromEntries(read('mythicsim_a.json', 'mythicsim_b.json').map(o => [o.slug, o]));
const WFB = Object.fromEntries(read('wfb_a.json', 'wfb_b.json').map(o => [o.path, o]));

// MythicSim's name of a stat: our word, and how many of its points make one of ours
const MS_STAT = {
  'Strength': ['str'], 'Agility': ['agi'], 'Stamina': ['sta'], 'Intellect': ['int'], 'Spirit': ['spi'],
  'Attack power': ['ap'], 'Ranged attack power': ['rap'], 'Feral attack power': ['fap'], 'Armor penetration': ['arp'],
  'Block value': ['bv'], 'Defense': ['def'], 'Dodge': ['dodge'], 'Parry': ['parry'], 'Block': ['block'],
  'Hit': ['hit', 10], 'Crit': ['crit', 14], 'Haste': ['haste', 10], 'Spell haste': ['haste', 10], 'Expertise': ['exp', 10],
  'Spell hit': ['shit', 10], 'Spell crit': ['scrit', 14], 'Spell damage': ['sp'], 'Mana per 5': ['mp5'],
  'Spell penetration': ['spen'],
  // ("weapon damage" is taken to be per point of the weapon's damage per second)
  'Weapon damage': ['dps'], 'Weapon damage (not in line)': ['dps'],
  'Shadow spell damage': ['sp_shadow'], 'Fire spell damage': ['sp_fire'], 'Frost spell damage': ['sp_frost'],
  'Arcane spell damage': ['sp_arcane'], 'Nature spell damage': ['sp_nature'], 'Holy spell damage': ['sp_holy'],
};
// wowforeverbislist's: our word; for one who casts, hit and crit are the spell ones
const WFB_STAT = {
  'Strength': 'str', 'Agility': 'agi', 'Stamina': 'sta', 'Intellect': 'int', 'Spirit': 'spi', 'Attack Power': 'ap',
  'Ranged Attack Power': 'rap', 'Feral Attack Power': 'fap', 'Armor Penetration': 'arp', 'Block Value': 'bv',
  'Defense': 'def', 'Dodge': 'dodge', 'Parry': 'parry', 'Block': 'block', 'Hit': 'hit', 'Critical Strike': 'crit',
  'Haste': 'haste', 'Expertise': 'exp', 'Spell Power': 'sp', 'Healing Power': 'heal', 'Mana per 5 sec': 'mp5',
  'Spell Penetration': 'spen', 'Shadow Damage': 'sp_shadow', 'Fire Damage': 'sp_fire', 'Frost Damage': 'sp_frost',
  'Arcane Damage': 'sp_arcane', 'Nature Damage': 'sp_nature', 'Holy Damage': 'sp_holy',
  // (the same numbers as Critical Strike and Hit on the hunter pages: not counted twice)
  'Ranged Crit': null, 'Ranged Hit': null,
};
const SPELL = { hit: 'shit', crit: 'scrit' };

// { w, caps } of a MythicSim page: its damage column, or its threat column
function fromMS(slug, threat) {
  const w = {};
  for (const [name, v] of Object.entries(MS[slug].weights)) {
    const m = MS_STAT[name];
    const ep = threat ? v.ep_threat : v.ep_dmg;
    // (a worth below nothing is noise of the measuring: defense and dodge do not lower a tank's threat)
    if (m && typeof ep === 'number' && ep > 0) w[m[0]] = (w[m[0]] || 0) + ep * (m[1] || 1);
  }
  return w;
}
// of a wowforeverbislist page. A value whose unit the page does not say (hit, on two tank pages) is taken to be
// per point of rating: beside the other values of its page nothing else fits.
function fromWFB(p, caster) {
  const w = {}, caps = {};
  for (const s of WFB[p].weights) {
    let word = WFB_STAT[s.stat];
    if (word === undefined) throw new Error(p + ': unknown stat ' + s.stat);
    if (word) {
      if (caster && SPELL[word]) word = SPELL[word];
      const k = s.unit === 'unknown' ? 10 : 1;
      w[word] = s.value * k;
      if (s.cap != null) caps[word] = { cap: s.cap, over: (s.after_cap || 0) * k };
    }
  }
  return { w, caps };
}

// a spec's picture, under Interface\\Icons (the game's own art, by name)
const ICONS = { "warrior-arms": "Ability_Warrior_SavageBlow", "warrior-fury": "Ability_Warrior_InnerRage", "warrior-protection": "Ability_Warrior_DefensiveStance", "warrior-furyprot": "Ability_Warrior_Revenge", "paladin-holy": "Spell_Holy_HolyBolt", "paladin-protection": "Spell_Holy_DevotionAura", "paladin-retprot": "Spell_Holy_SealOfMight", "paladin-holyprot": "Spell_Holy_SealOfProtection", "paladin-retribution": "Spell_Holy_AuraOfLight", "paladin-shockadin": "Spell_Holy_SearingLight", "hunter-beastmastery": "Ability_Hunter_BeastTaming", "hunter-marksmanship": "Ability_Marksmanship", "hunter-survival": "Ability_Hunter_SwiftStrike", "hunter-svweave": "Ability_MeleeDamage", "hunter-svmelee": "Ability_Parry", "rogue-assassination": "Ability_Rogue_Eviscerate", "rogue-combat": "Ability_BackStab", "rogue-combatdaggers": "Ability_Rogue_SliceDice", "rogue-subtlety": "Ability_Stealth", "priest-discipline": "Spell_Holy_WordFortitude", "priest-holy": "Spell_Holy_Heal", "priest-shadow": "Spell_Shadow_ShadowWordPain", "priest-smite": "Spell_Holy_HolySmite", "shaman-elemental": "Spell_Nature_Lightning", "shaman-enhancement": "Spell_Nature_LightningShield", "shaman-elehance": "Spell_Nature_ChainLightning", "shaman-restoration": "Spell_Nature_MagicImmunity", "mage-arcane": "Spell_Holy_MagicalSentry", "mage-arcanefire": "Spell_Nature_WispSplode", "mage-fire": "Spell_Fire_FireBolt02", "mage-frost": "Spell_Frost_FrostBolt02", "mage-frostfire": "Spell_Fire_SoulBurn", "warlock-affliction": "Spell_Shadow_DeathCoil", "warlock-demonology": "Spell_Shadow_Metamorphosis", "warlock-demoshadow": "Spell_Shadow_SummonVoidWalker", "warlock-destruction": "Spell_Shadow_RainOfFire", "warlock-smruin": "Spell_Shadow_ShadowBolt", "druid-balance": "Spell_Nature_StarFall", "druid-feral": "Ability_Druid_CatForm", "druid-bear": "Ability_Racial_BearForm", "druid-restoration": "Spell_Nature_HealingTouch" };
const HELD = ['held', '2h'];
// id, class, title, role, hands; ms = MythicSim slug, wfb = wowforeverbislist path. ref = the stat both have,
// by which one site's values are brought to the other's scale.
const SPECS = [
  { id: 'warrior-arms', class: 'WARRIOR', title: 'Arms', hands: ['2h'], ms: 'arms-warrior' },
  { id: 'warrior-fury', class: 'WARRIOR', title: 'Fury', hands: ['dw'], ms: 'warrior', wfb: '/preraid/warrior/fury/', ref: ['Strength', 'Strength'] },
  { id: 'warrior-protection', class: 'WARRIOR', title: 'Protection', role: 'tank', hands: ['shield'], ms: 'protection-warrior', wfb: '/preraid/warrior/protection/', ref: ['Strength', 'Strength'] },
  { id: 'paladin-holy', class: 'PALADIN', title: 'Holy', role: 'healer', hands: ['shield', 'held'], wfb: '/preraid/paladin/holy/', caster: true },
  { id: 'paladin-protection', class: 'PALADIN', title: 'Protection', role: 'tank', hands: ['shield'], ms: 'protection-paladin', wfb: '/preraid/paladin/protection/', ref: ['Agility', 'Agility'] },
  { id: 'paladin-retprot', class: 'PALADIN', title: 'Ret-Prot (threat only)', role: 'tank', hands: ['shield'], ms: 'ret-protection-paladin' },
  { id: 'paladin-holyprot', class: 'PALADIN', title: 'Holy-Prot (threat only)', role: 'tank', hands: ['shield'], ms: 'holy-protection-paladin' },
  { id: 'paladin-retribution', class: 'PALADIN', title: 'Retribution', hands: ['2h'], ms: 'retribution-paladin', wfb: '/preraid/paladin/retribution/', ref: ['Strength', 'Strength'] },
  { id: 'paladin-shockadin', class: 'PALADIN', title: 'Shockadin', ms: 'shockadin-paladin' },
  { id: 'hunter-beastmastery', class: 'HUNTER', title: 'Beast Mastery', hands: ['2h', 'dw'], ms: 'hunter' },
  { id: 'hunter-marksmanship', class: 'HUNTER', title: 'Marksmanship', hands: ['2h', 'dw'], ms: 'marksmanship-hunter' },
  { id: 'hunter-survival', class: 'HUNTER', title: 'Survival', hands: ['2h', 'dw'], ms: 'survival-hunter', wfb: '/preraid/hunter/survival/', ref: ['Agility', 'Agility'] },
  { id: 'hunter-svweave', class: 'HUNTER', title: 'Survival (melee weave)', hands: ['2h', 'dw'], wfb: '/preraid/hunter/sv-weave/' },
  { id: 'hunter-svmelee', class: 'HUNTER', title: 'Survival (melee)', hands: ['2h', 'dw'], wfb: '/preraid/hunter/survival-melee/' },
  { id: 'rogue-assassination', class: 'ROGUE', title: 'Assassination', hands: ['dw'], ms: 'assassination-rogue', wfb: '/preraid/rogue/assassination/' },
  { id: 'rogue-combat', class: 'ROGUE', title: 'Combat', hands: ['dw'], ms: 'combat-rogue', wfb: '/preraid/rogue/combat/' },
  { id: 'rogue-combatdaggers', class: 'ROGUE', title: 'Combat (daggers)', hands: ['dw'], wfb: '/preraid/rogue/combat-daggers/' },
  { id: 'rogue-subtlety', class: 'ROGUE', title: 'Subtlety', hands: ['dw'], ms: 'subtlety-rogue', wfb: '/preraid/rogue/subtlety/' },
  { id: 'priest-discipline', class: 'PRIEST', title: 'Discipline', role: 'healer', hands: HELD, wfb: '/preraid/priest/discipline/', caster: true },
  { id: 'priest-holy', class: 'PRIEST', title: 'Holy', role: 'healer', hands: HELD, wfb: '/preraid/priest/holy/', caster: true },
  { id: 'priest-shadow', class: 'PRIEST', title: 'Shadow', hands: HELD, ms: 'shadow-priest' },
  { id: 'priest-smite', class: 'PRIEST', title: 'Smite', hands: HELD, ms: 'smite-priest' },
  { id: 'shaman-elemental', class: 'SHAMAN', title: 'Elemental', hands: ['shield', 'held', '2h'], ms: 'elemental-shaman' },
  { id: 'shaman-enhancement', class: 'SHAMAN', title: 'Enhancement', hands: ['dw', '2h'], ms: 'enhancement-shaman', wfb: '/preraid/shaman/enhancement/', ref: ['Strength', 'Strength'] },
  { id: 'shaman-elehance', class: 'SHAMAN', title: 'Elehance', hands: ['shield', 'held', '2h', 'dw'], ms: 'elehance-shaman' },
  { id: 'shaman-restoration', class: 'SHAMAN', title: 'Restoration', role: 'healer', hands: ['shield', 'held', '2h'], wfb: '/preraid/shaman/restoration/', caster: true },
  { id: 'mage-arcane', class: 'MAGE', title: 'Arcane', hands: HELD, wfb: '/preraid/mage/arcane/', caster: true },
  { id: 'mage-arcanefire', class: 'MAGE', title: 'Arcane Fire', hands: HELD, ms: 'arcane-mage' },
  { id: 'mage-fire', class: 'MAGE', title: 'Fire', hands: HELD, ms: 'fire-mage' },
  { id: 'mage-frost', class: 'MAGE', title: 'Frost', hands: HELD, ms: 'frost-mage' },
  { id: 'mage-frostfire', class: 'MAGE', title: 'Frostfire', hands: HELD, ms: 'frostfire-mage' },
  { id: 'warlock-affliction', class: 'WARLOCK', title: 'Affliction', hands: HELD, ms: 'affliction-warlock' },
  { id: 'warlock-demonology', class: 'WARLOCK', title: 'Demonology', hands: HELD, ms: 'demonology-warlock' },
  { id: 'warlock-demoshadow', class: 'WARLOCK', title: 'Demonology (Shadow Brand)', hands: HELD, wfb: '/preraid/warlock/demonology-shadow/', caster: true },
  { id: 'warlock-destruction', class: 'WARLOCK', title: 'Destruction', hands: HELD, ms: 'destruction-warlock' },
  { id: 'warlock-smruin', class: 'WARLOCK', title: 'SM/Ruin', hands: HELD, wfb: '/preraid/warlock/sm-ruin/', caster: true },
  { id: 'druid-balance', class: 'DRUID', title: 'Balance', hands: HELD, ms: 'balance-druid' },
  { id: 'druid-feral', class: 'DRUID', title: 'Feral (cat)', hands: ['2h', 'held'], ms: 'feral-druid' },
  { id: 'druid-bear', class: 'DRUID', title: 'Feral (bear)', role: 'tank', hands: ['2h', 'held'], ms: 'feral-bear-druid', wfb: '/preraid/druid/feral-tank/', ref: ['Strength', 'Strength'] },
  { id: 'druid-restoration', class: 'DRUID', title: 'Restoration', role: 'healer', hands: HELD, wfb: '/preraid/druid/restoration/', caster: true },
];

const msValue = (slug, name, threat) => { const v = MS[slug].weights[name]; return v ? (threat ? v.ep_threat : v.ep_dmg) : null; };
const wfbValue = (p, name) => { const s = WFB[p].weights.find(x => x.stat === name); return s ? s.value : null; };
// Spell hit: MythicSim says 16%, wowforeverbislist and Conquest Capped 17%: two against one, and a percent too
// many costs less than one too few.
const DEF = 440, MELEE_HIT = 8, SPELL_HIT_MS = 17, EXPERTISE = 6.5;

function build(spec) {
  const notes = [], src = [];
  let w, caps = {};
  const tank = spec.role === 'tank';
  if (spec.ms) src.push(MS[spec.ms].url);
  if (spec.wfb) src.push(WFB[spec.wfb].url);
  if (spec.ms && spec.wfb && tank) {
    // a tank both sites have
    ({ w, caps } = fromWFB(spec.wfb, false));
    const k = wfbValue(spec.wfb, spec.ref[1]) / msValue(spec.ms, spec.ref[0], true);
    const added = [];
    for (const [word, v] of Object.entries(fromMS(spec.ms, true))) {
      if (w[word] == null && v > 0) { w[word] = v * k; added.push(word); }
    }
    notes.push('Survival and its own threat values: wowforeverbislist. Added from MythicSim threat, x' + k.toFixed(2) + ' (matched at ' + spec.ref[1] + '): ' + added.sort().join(' ') + '.');
  } else if (spec.ms) {
    w = fromMS(spec.ms, tank);
    if (tank) notes.push('Threat only: nothing here says what keeps a tank alive.');
    const melee = w.exp != null || w.hit != null || /WARRIOR|ROGUE|HUNTER/.test(spec.class);
    // a hit the measured character already had enough of: its worth below the cap from the other site
    if (melee && !w.hit && spec.wfb && spec.ref) {
      const k = msValue(spec.ms, spec.ref[0], tank) / wfbValue(spec.wfb, spec.ref[1]);
      w.hit = wfbValue(spec.wfb, 'Hit') * k;
      notes.push('Hit below the cap from wowforeverbislist, x' + k.toFixed(2) + ' (MythicSim measured a character at the cap).');
    }
    if (melee) {
      caps.hit = { cap: MELEE_HIT, over: 0 };
      // two weapons: white swings go on gaining up to 27%, at the part of the worth the other site gives
      const o = spec.wfb && WFB[spec.wfb].weights.find(x => x.stat === 'Hit');
      if (o && o.after_cap && w.hit) {
        caps.hit.over = w.hit * o.after_cap / o.value;
        notes.push('Hit past 8%: white swings with two weapons gain up to 27%.');
      }
      if (w.exp != null) caps.exp = { cap: EXPERTISE, over: 0 };
    }
    if (w.shit != null) caps.shit = { cap: SPELL_HIT_MS, over: 0 };
  } else {
    ({ w, caps } = fromWFB(spec.wfb, spec.caster));
  }
  if (tank) {
    // defense: before anything else
    // (not for a bear, who is kept from being crit by talents and cannot reach it)
    caps.def = { cap: DEF, over: Math.max((caps.def && caps.def.over) || 0, 0), hard: spec.class !== 'DRUID' };
    if (w.def == null || w.def < 0) w.def = caps.def.over;
    if (!caps.hit) caps.hit = { cap: MELEE_HIT, over: 0 };
    if (!caps.exp && w.exp != null) caps.exp = { cap: EXPERTISE, over: 0 };
    if (w.shit != null && !caps.shit) caps.shit = { cap: SPELL_HIT_MS, over: 0 };
  }
  for (const word of Object.keys(caps)) if (w[word] == null) w[word] = 0;
  for (const m of [spec.ms && MS[spec.ms].build_measured_on, spec.ms && /Experimental/.test(MS[spec.ms].build_measured_on) && 'experimental build']) {
    if (m && m !== true && !notes.includes(m)) notes.unshift(m === 'experimental build' ? 'MythicSim marks this build experimental.' : 'Measured on ' + m + '.');
  }
  if (spec.wfb && !spec.ms) notes.unshift(String(WFB[spec.wfb].source || '').replace(/\s+/g, ' ').slice(0, 90) + '.');
  if (!ICONS[spec.id]) throw new Error('no picture for ' + spec.id);
  return { ...spec, icon: ICONS[spec.id], w, caps, src, note: notes.join(' ') };
}

const num = n => String(Math.round(n * 1000) / 1000);
const q = s => '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
const keys = o => Object.keys(o).sort();
const any = Object.values(MS)[0];
const client = (any.client.match(/\d+\.\d+\.\d+\.\d+/) || ['?'])[0];
const lines = [
  '-- What a point of each stat is worth to every class and spec, and where it stops being worth it.',
  '-- GENERATED by tools/bisweights.js from tools/bis/*.json: do not edit by hand.',
  '-- Sources (see THIRD_PARTY_LICENSES.txt), both for WoW: Forever, client ' + client + ':',
  '--   mythicsim.com/wow-forever/stat-priority (' + any.updated + '): damage and threat per point, measured',
  '--   wowforeverbislist.com/preraid (' + Object.values(WFB)[0].updated + '): WoWSims values; healers, and what keeps a tank alive',
  '-- { id, class, title, role, icon (under Interface\\\\Icons), src = { where from }, note, hands = { what the hands may hold },',
  '--   w = { [stat] = worth of one: hit, crit, haste, exp, dodge, parry and block per 1%, the rest per point },',
  '--   caps = { [stat] = { cap = total on the character sheet, over = worth of one past it, hard = reach it first } } }',
  'local _, DT = ...',
  'DT.BisBuild = ' + q(client),
  'DT.BisProfiles = {',
];
for (const spec of SPECS) {
  const p = build(spec);
  lines.push('\t{ id = ' + q(p.id) + ', class = ' + q(p.class) + ', title = ' + q(p.title) + ', role = ' + q(p.role || 'damage') + ', icon = ' + q(p.icon) + ',');
  lines.push('\t\tsrc = { ' + p.src.map(q).join(', ') + ' },');
  if (p.note) lines.push('\t\tnote = ' + q(p.note) + ',');
  if (p.hands) lines.push('\t\thands = { ' + p.hands.map(q).join(', ') + ' },');
  lines.push('\t\tw = { ' + keys(p.w).map(k => k + ' = ' + num(p.w[k])).join(', ') + ' },');
  lines.push('\t\tcaps = { ' + keys(p.caps).map(k => k + ' = { cap = ' + num(p.caps[k].cap) + ', over = ' + num(p.caps[k].over) + (p.caps[k].hard ? ', hard = true' : '') + ' }').join(', ') + ' } },');
}
lines.push('}', '');
fs.writeFileSync(path.join(__dirname, '..', '..', 'DawnTools_Seed', 'BisProfiles.lua'), lines.join('\n'));
console.log('wrote ../DawnTools_Seed/BisProfiles.lua: ' + SPECS.length + ' profiles, client ' + client);
