-- OneButtonAssistant: deterministic priority rotation engine
local Engine = {}
Engine.version = "0.2"

-- NOTE: Prefer locale-stable numeric spell IDs where possible.
-- The engine already accepts numeric IDs or strings like "spell:<id>" from adapters
-- and token mappings. To make it easier to migrate mappings to numeric IDs,
-- this helper normalizes a value into a consistent token form used by the engine.
-- Usage examples (in-game adapters / migration scripts):
--   NormalizeSpellToken(12345)    -> returns number 12345
--   NormalizeSpellToken("spell:12345") -> returns number 12345
--   NormalizeSpellToken("Spell Name")  -> returns "Spell Name" (resolution requires GetSpellInfo in-game)
local function NormalizeSpellToken(val)
  if not val then return nil end
  if type(val) == "number" then return val end
  if type(val) == "string" then
    local s = val:match("^%s*spell:(%d+)%s*$")
    if s then return tonumber(s) end
    local n = tonumber(val)
    if n then return n end
    return val
  end
  return val
end

-- Internal player state (can be updated from the game via adapters)
local playerState = {
  talents = {}, -- map: [talentName] = true
  procs = {},   -- map: [procName] = true
  enemyCount = 1,
  cooldowns = {}, -- map: [spellKey] = expirationTime
  buffs = {}, -- map: [buffName] = expirationTime (GetTime() values)
}

-- Define spells (keys are internal identifiers; gamespell names/IDs can be mapped later)
local spells = {
  -- Single-target spells (include optional scoring metadata)
  highPriority = { key = "highPriority", name = "SpellA", priority = 3, castTime = 1.0 },
  mediumPriority = { key = "mediumPriority", name = "SpellB", priority = 2, castTime = 1.5 },
  lowPriority = { key = "lowPriority", name = "SpellC", priority = 1, castTime = 0.5 },

  -- AoE spells
  aoeHighPriority = { key = "aoeHighPriority", name = "SpellAOE1", priority = 3, castTime = 1.25 },
  aoeLowPriority = { key = "aoeLowPriority", name = "SpellAOE2", priority = 1, castTime = 0.8 },
}

-- Buff -> spell mapping (configurable). Each entry: { spellKey = <key in spells>, refreshThreshold = seconds }
local buffRefreshMap = {
  -- example: try to refresh 'Shield' with 'highPriority' when <5s remaining
  --["Shield"] = { spellKey = spells.highPriority.key, refreshThreshold = 5 },
}

function Engine:SetBuffRefreshMap(map)
  if type(map) ~= "table" then return end
  buffRefreshMap = map
end

local function HasTalent(state, talentName)
  state = state or playerState
  return state.talents and state.talents[talentName] == true
end

local function HasProc(state, procName)
  state = state or playerState
  return state.procs and state.procs[procName] == true
end

local function UseAoE(state)
  state = state or playerState
  return (state.enemyCount or 0) >= 3
end

-- Update internal state (adapters should call this with real game data)
function Engine:UpdateState(state)
  if not state then return end
  -- shallow merge fields we expect
  if state.talents then playerState.talents = state.talents end
  if state.procs then playerState.procs = state.procs end
  if state.enemyCount then playerState.enemyCount = state.enemyCount end
  if state.cooldowns then playerState.cooldowns = state.cooldowns end
  if state.buffs then playerState.buffs = state.buffs end
end

-- Returns next action table or nil. Action: {key=..., name=..., reason=...}
function Engine:GetNextAction(state)
  state = state or playerState

  -- First: check buff refresh needs
  local now = GetTime and GetTime() or time()
  for buffName, cfg in pairs(buffRefreshMap) do
    local exp = state.buffs and state.buffs[buffName]
    if exp then
      local remaining = exp - now
      if remaining <= cfg.refreshThreshold then
        -- if mapped spell is off cooldown, use it to refresh buff
        local spellKey = cfg.spellKey
        if spellKey then
          local cdExp = state.cooldowns and state.cooldowns[spellKey]
          if not cdExp or cdExp <= now then
            return { key = spellKey, name = spellKey, reason = "Refresh "..buffName }
          end
        end
      end
    end
  end

  -- AoE handling: short-circuit to AoE priorities if multiple enemies
  if UseAoE(state) then
    if HasProc(state, "ProcX") then
      return { key = spells.aoeHighPriority.key, name = spells.aoeHighPriority.name, reason = "AoE with ProcX" }
    else
      return { key = spells.aoeLowPriority.key, name = spells.aoeLowPriority.name, reason = "AoE default" }
    end
  end

  -- Single-target scoring: pick the available spell with highest score.
  local best, bestScore = nil, -1
  -- get approximate latency (ms) if available
  local latencyMs = 0
  local ok, homeLatency, worldLatency = pcall(function()
    if GetNetStats then return select(3, GetNetStats()) end
  end)
  if ok and type(homeLatency) == "number" then latencyMs = homeLatency end
  for k, s in pairs(spells) do
    -- skip AoE spells in single-target flow
    if not (k:match("^aoe")) then
      local priority = s.priority or 1
      local castTime = s.castTime or 0
      local effectiveCast = castTime + (latencyMs / 1000)
      local cdExp = state.cooldowns and state.cooldowns[s.key]
      local available = (not cdExp) or (cdExp <= now)
      if available then
        local score = priority
        -- small bonus for procs and talents
        if HasProc(state, "ProcX") then score = score + 1.5 end
        if HasTalent(state, "TalentA") then score = score + 0.75 end
        -- penalize long casts slightly when target is about to die / buff windows are small
        local nearExpiryPenalty = 0
        -- if any tracked buff is very low remaining, favor faster spells
        if state.buffs then
          for bname, bexp in pairs(state.buffs) do
            if bexp and (bexp - now) <= 2.0 then
              nearExpiryPenalty = nearExpiryPenalty + (effectiveCast * 0.25)
            end
          end
        end
        score = score - nearExpiryPenalty
        if score > bestScore then bestScore = score; best = s end
      end
    end
  end

  if best then
    return { key = best.key, name = best.name, reason = "scored" }
  end

  -- Fallback
  return { key = spells.lowPriority.key, name = spells.lowPriority.name, reason = "Fallback" }
end

-- Helper for adapters: map an external suggestion (e.g., from Hekili/GSE) into engine action
function Engine:MapExternalSuggestion(suggestion)
  if not suggestion then return nil end
  -- Handle numeric spell IDs or strings like "spell:12345"
  local key = suggestion.key or suggestion.name
  local name = suggestion.name
  -- normalize numeric keys
  local spellId = nil
  if type(key) == "number" then
    spellId = key
  elseif type(key) == "string" then
    local s = key:match("^%s*spell:(%d+)%s*$")
    if s then spellId = tonumber(s) end
    if not spellId then
      local n = tonumber(key)
      if n then spellId = n end
    end
  end

  if spellId then
    -- try to resolve spell name when API is available (pcall to be safe)
    local ok, resolvedName = pcall(GetSpellInfo, spellId)
    if ok and resolvedName and resolvedName ~= "" then
      name = name or resolvedName
      key = "spell:" .. tostring(spellId)
    else
      name = name or ("spell:" .. tostring(spellId))
      key = "spell:" .. tostring(spellId)
    end
  end

  -- If we don't have a spellId but have a string key/name, try to resolve it via GetSpellInfo
  if not spellId and type(key) == "string" and key ~= "unknown" then
    local ok2, resolved = pcall(GetSpellInfo, key)
    if ok2 and resolved and resolved ~= "" then
      name = name or resolved
      key = resolved
    else
      -- Attempt per-token heuristics when GetSpellInfo failed to resolve the token.
      local lk = tostring(key):lower()
      -- token -> per-class candidate spell ID lists
      local tokenCandidates = {
        interrupt = {
          ROGUE = {1766, 13750},            -- Kick, Adrenaline Rush (fallback)
          WARRIOR = {6552, 6554},           -- Pummel, fallback
          MAGE = {2139},                    -- Counterspell
          PRIEST = {15487},                 -- Silence
          DRUID = {106839, 93985},          -- Skull Bash (various specs)
          DEATHKNIGHT = {"Mind Freeze", "Death Grip"}, -- Mind Freeze primary; Death Grip as fallback pull/interrupt-like
          SHAMAN = {57994},                 -- Wind Shear
          MONK = {116705},                  -- Spear Hand Strike
          HUNTER = {147362, 34490},         -- Counter Shot / Silencing Shot
          PALADIN = {96231, 853},           -- Rebuke, Hammer of Justice (fallback)
          WARLOCK = {19647, 132409},        -- Spell Lock / fallback
          DEMONHUNTER = {183752, 207827},   -- Disrupt / fallback
        },
        silence = {
          MAGE = {1766, 2139},
          PRIEST = {15487},
          WARLOCK = {19647},
          ROGUE = {1766, 1833},
        },
        stun = {
          ROGUE = {408, 1833},
          WARRIOR = {132168, 199085},
          PALADIN = {105593, 853},
          MONK = {119381, 116095},
          DRUID = {5211, 33786},
          DEATHKNIGHT = {"Asphyxiate", "Strangulate", "Blinding Sleet"}, -- DK stuns/major CCs
        },
        crowdcontrol = {
          ROGUE = {677},
          MAGE = {118},
          HUNTER = {3355},
          WARLOCK = {5782},
          PRIEST = {605, 8122},
          DRUID = {33786},
          PALADIN = {20066},
          MONK = {115078, 119381},
          DEATHKNIGHT = {"Chains of Ice", "Blinding Sleet", "Strangulate"},
        },
        interruptoffhand = { DEFAULT = {} },
        -- additional DK-specific tokens
        summon = {
          DEATHKNIGHT = {"Raise Dead", "Army of the Dead"},
        },
        defensive = {
          DEATHKNIGHT = {"Anti-Magic Shell", "Icebound Fortitude", "Dark Command"},
        },
          -- Druid-specific tokens (forms, CC, defensives, core spec spells)
          bear_form = { DRUID = {"Bear Form"} },
          cat_form = { DRUID = {"Cat Form"} },
          travel_form = { DRUID = {"Travel Form"} },
          aquatic_form = { DRUID = {"Aquatic Form"} },
          moonkin_form = { DRUID = {"Moonkin Form"} },
          entangling_roots = { DRUID = {"Entangling Roots"} },
          hibernate = { DRUID = {"Hibernate"} },
          rebirth = { DRUID = {"Rebirth"} },
          barkskin = { DRUID = {"Barkskin"} },
          dash = { DRUID = {"Dash"} },
          stampeding_roar = { DRUID = {"Stampeding Roar"} },
          cyclone = { DRUID = {"Cyclone"} },
          innervate = { DRUID = {"Innervate"} },
          natures_cure = { DRUID = {"Nature's Cure", "Nature's Cure"} },
          typhoon = { DRUID = {"Typhoon"} },
          mighty_bash = { DRUID = {"Mighty Bash"} },
          heart_of_the_wild = { DRUID = {"Heart of the Wild"} },
          wild_charge = { DRUID = {"Wild Charge"} },
          ursols_vortex = { DRUID = {"Ursol's Vortex"} },
          -- Balance core
          moonfire = { DRUID = {"Moonfire"} },
          sunfire = { DRUID = {"Sunfire"} },
          wrath = { DRUID = {"Wrath"} },
          starfire = { DRUID = {"Starfire"} },
          starsurge = { DRUID = {"Starsurge"} },
          starfall = { DRUID = {"Starfall"} },
          -- Feral core
          shred = { DRUID = {"Shred"} },
          rake = { DRUID = {"Rake"} },
          rip = { DRUID = {"Rip"} },
          ferocious_bite = { DRUID = {"Ferocious Bite"} },
          savage_roar = { DRUID = {"Savage Roar"} },
          -- Guardian core
          mangle = { DRUID = {"Mangle"} },
          thrash = { DRUID = {"Thrash"} },
          ironfur = { DRUID = {"Ironfur"} },
          frenzied_regeneration = { DRUID = {"Frenzied Regeneration"} },
          -- Restoration core
          rejuvenation = { DRUID = {"Rejuvenation"} },
          regrowth = { DRUID = {"Regrowth"} },
          wild_growth = { DRUID = {"Wild Growth"} },
          swiftmend = { DRUID = {"Swiftmend"} },
          tranquility = { DRUID = {"Tranquility"} },
          -- Hunter-specific tokens (core abilities, utility, traps, pet)
          auto_shot = { HUNTER = {"Auto Shot"} },
          arcane_shot = { HUNTER = {"Arcane Shot"} },
          kill_shot = { HUNTER = {"Kill Shot"} },
          steady_shot = { HUNTER = {"Steady Shot"} },
          hunters_mark = { HUNTER = {"Hunter's Mark"} },
          tranquilizing_shot = { HUNTER = {"Tranquilizing Shot"} },
          feign_death = { HUNTER = {"Feign Death"} },
          disengage = { HUNTER = {"Disengage"} },
          aspect_cheetah = { HUNTER = {"Aspect of the Cheetah", "Aspect of the Cheetah"} },
          aspect_turtle = { HUNTER = {"Aspect of the Turtle"} },
          misdirection = { HUNTER = {"Misdirection"} },
          revive_pet = { HUNTER = {"Revive Pet"} },
          mend_pet = { HUNTER = {"Mend Pet"} },
          call_pet = { HUNTER = {"Call Pet"} },
          -- Class talents / utility
          binding_shot = { HUNTER = {"Binding Shot"} },
          scatter_shot = { HUNTER = {"Scatter Shot"} },
          explosive_trap = { HUNTER = {"Explosive Trap"} },
          steel_trap = { HUNTER = {"Steel Trap"} },
          intimidation = { HUNTER = {"Intimidation"} },
          -- Spec cores
          -- Beast Mastery
          kill_command = { HUNTER = {"Kill Command"} },
          bestial_wrath = { HUNTER = {"Bestial Wrath"} },
          dire_beast = { HUNTER = {"Dire Beast"} },
          barbed_shot = { HUNTER = {"Barbed Shot"} },
          -- Marksmanship
          aimed_shot = { HUNTER = {"Aimed Shot"} },
          rapid_fire = { HUNTER = {"Rapid Fire"} },
          multi_shot = { HUNTER = {"Multi-Shot"} },
          volley = { HUNTER = {"Volley"} },
          -- Survival
          raptor_strike = { HUNTER = {"Raptor Strike"} },
          mongoose_bite = { HUNTER = {"Mongoose Bite"} },
          carve = { HUNTER = {"Carve"} },
          explosive_shot = { HUNTER = {"Explosive Shot"} },
          -- Mage-specific tokens (core utilities, interrupts, CC, defenses, specs)
          arcane_intellect = { MAGE = {"Arcane Intellect"} },
          blink = { MAGE = {"Blink", "Shimmer"} },
          polymorph = { MAGE = {"Polymorph"} },
          counterspell = { MAGE = {"spell:2139"} },
          spellsteal = { MAGE = {"Spellsteal"} },
          ice_block = { MAGE = {"Ice Block"} },
          mirror_image = { MAGE = {"Mirror Image"} },
          slow_fall = { MAGE = {"Slow Fall"} },
          portal = { MAGE = {"Portal: Dalaran", "Portal: Stormwind", "Portal: Orgrimmar"} },
          teleport = { MAGE = {"Teleport: Dalaran", "Teleport: Stormwind", "Teleport: Orgrimmar"} },
          -- class talents / utility
          dragons_breath = { MAGE = {"Dragon's Breath"} },
          blast_wave = { MAGE = {"Blast Wave"} },
          ring_of_frost = { MAGE = {"Ring of Frost"} },
          mass_invisibility = { MAGE = {"Mass Invisibility"} },
          temporal_warp = { MAGE = {"Temporal Warp"} },
          -- spec cores
          -- Arcane
          arcane_blast = { MAGE = {"Arcane Blast"} },
          arcane_missiles = { MAGE = {"Arcane Missiles"} },
          arcane_barrage = { MAGE = {"Arcane Barrage"} },
          evocation = { MAGE = {"Evocation"} },
          -- Fire
          fireball = { MAGE = {"Fireball"} },
          pyroblast = { MAGE = {"Pyroblast"} },
          flamestrike = { MAGE = {"Flamestrike"} },
          combustion = { MAGE = {"Combustion"} },
          -- Frost
          frostbolt = { MAGE = {"Frostbolt"} },
          ice_lance = { MAGE = {"Ice Lance"} },
          flurry = { MAGE = {"Flurry"} },
          blizzard = { MAGE = {"Blizzard"} },
          -- Monk-specific tokens (mobility, taunt, interrupts, defensives, heals, spec cores)
          roll = { MONK = {"Roll", "Chi Torpedo"} },
          provoke = { MONK = {"Provoke"} },
          paralysis = { MONK = {"Paralysis"} },
          transcendence = { MONK = {"Transcendence", "Transcendence: Transfer"} },
          detox = { MONK = {"Detox"} },
          touch_of_death = { MONK = {"Touch of Death"} },
          fortifying_brew = { MONK = {"Fortifying Brew"} },
          expel_harm = { MONK = {"Expel Harm"} },
          vivify = { MONK = {"Vivify"} },
          tiger_palm = { MONK = {"Tiger Palm"} },
          -- class talents / utility
          ring_of_peace = { MONK = {"Ring of Peace"} },
          diffuse_magic = { MONK = {"Diffuse Magic"} },
          dampen_harm = { MONK = {"Dampen Harm"} },
          chi_torpedo = { MONK = {"Chi Torpedo"} },
          jade_serpent_statue = { MONK = {"Summon Jade Serpent Statue"} },
          -- Brewmaster core
          keg_smash = { MONK = {"Keg Smash"} },
          breath_of_fire = { MONK = {"Breath of Fire"} },
          purifying_brew = { MONK = {"Purifying Brew"} },
          celestial_brew = { MONK = {"Celestial Brew"} },
          -- Mistweaver core
          enveloping_mist = { MONK = {"Enveloping Mist"} },
          essence_font = { MONK = {"Essence Font"} },
          renewing_mist = { MONK = {"Renewing Mist"} },
          soothing_mist = { MONK = {"Soothing Mist"} },
          -- Windwalker core
          blackout_kick = { MONK = {"Blackout Kick"} },
          rising_sun_kick = { MONK = {"Rising Sun Kick"} },
          fists_of_fury = { MONK = {"Fists of Fury"} },
          spinning_crane_kick = { MONK = {"Spinning Crane Kick"} },
          -- Paladin-specific tokens (core abilities, blessings, defensives, utilities, specs)
          judgment = { PALADIN = {"Judgment"} },
          crusader_strike = { PALADIN = {"Crusader Strike"} },
          hammer_of_justice = { PALADIN = {"Hammer of Justice"} },
          divine_shield = { PALADIN = {"Divine Shield"} },
          lay_on_hands = { PALADIN = {"Lay on Hands"} },
          blessing_of_freedom = { PALADIN = {"Blessing of Freedom"} },
          blessing_of_protection = { PALADIN = {"Blessing of Protection"} },
          blessing_of_sacrifice = { PALADIN = {"Blessing of Sacrifice"} },
          flash_of_light = { PALADIN = {"Flash of Light"} },
          cleanse_toxins = { PALADIN = {"Cleanse Toxins"} },
          consecration = { PALADIN = {"Consecration"} },
          divine_steed = { PALADIN = {"Divine Steed"} },
          -- class talents / utility
          holy_prism = { PALADIN = {"Holy Prism"} },
          repentance = { PALADIN = {"Repentance"} },
          hammer_of_wrath = { PALADIN = {"Hammer of Wrath"} },
          divine_toll = { PALADIN = {"Divine Toll"} },
          shield_of_vengeance = { PALADIN = {"Shield of Vengeance"} },
          -- spec cores
          -- Holy
          holy_light = { PALADIN = {"Holy Light"} },
          light_of_dawn = { PALADIN = {"Light of Dawn"} },
          holy_shock = { PALADIN = {"Holy Shock"} },
          beacon_of_light = { PALADIN = {"Beacon of Light"} },
          -- Protection
          shield_of_the_righteous = { PALADIN = {"Shield of the Righteous"} },
          avengers_shield = { PALADIN = {"Avenger's Shield"} },
          hammer_of_the_righteous = { PALADIN = {"Hammer of the Righteous"} },
          guardian_of_ancient_kings = { PALADIN = {"Guardian of Ancient Kings"} },
          -- Retribution
          blade_of_justice = { PALADIN = {"Blade of Justice"} },
          templars_verdict = { PALADIN = {"Templar's Verdict"} },
          divine_storm = { PALADIN = {"Divine Storm"} },
          wake_of_ashes = { PALADIN = {"Wake of Ashes"} },
          -- Shaman-specific tokens (core spells, totems, utility, interrupts, defensives, specs)
          lightning_bolt = { SHAMAN = {"spell:403"} },
          flame_shock = { SHAMAN = {"spell:8050"} },
          frost_shock = { SHAMAN = {"spell:8056"} },
          chain_lightning = { SHAMAN = {"spell:421"} },
          healing_surge = { SHAMAN = {"spell:8004"} },
          ghost_wolf = { SHAMAN = {"spell:2645"} },
          reincarnation = { SHAMAN = {"spell:20608"} },
          purge = { SHAMAN = {"Purge"} },
          tremor_totem = { SHAMAN = {"spell:8143"} },
          capacitor_totem = { SHAMAN = {"spell:192058"} },
          wind_shear = { SHAMAN = {"spell:57994"} },
          astral_shift = { SHAMAN = {"spell:108271"} },
          -- class talents / utility
          earthgrab_totem = { SHAMAN = {"Earthgrab Totem"} },
          thunderstorm = { SHAMAN = {"Thunderstorm"} },
          spirit_walk = { SHAMAN = {"Spirit Walk"} },
          totemic_projection = { SHAMAN = {"Totemic Projection"} },
          ancestral_guidance = { SHAMAN = {"Ancestral Guidance"} },
          -- Elemental core
          lava_burst = { SHAMAN = {"Lava Burst"} },
          earth_shock = { SHAMAN = {"spell:8042"} },
          earthquake = { SHAMAN = {"spell:61882"} },
          -- Enhancement core
          stormstrike = { SHAMAN = {"spell:17364"} },
          lava_lash = { SHAMAN = {"spell:60103"} },
          crash_lightning = { SHAMAN = {"spell:187874"} },
          feral_spirit = { SHAMAN = {"spell:51533"} },
          -- Restoration core
          healing_wave = { SHAMAN = {"spell:77472"} },
          chain_heal = { SHAMAN = {"spell:1064"} },
          healing_rain = { SHAMAN = {"spell:73920"} },
          riptide = { SHAMAN = {"spell:61295"} },
          -- Warlock-specific tokens (demons, core spells, utilities, defensives, talents, specs)
          summon_demon = { WARLOCK = {"Summon Imp", "Summon Voidwalker", "Summon Succubus", "Summon Felhunter"} },
          health_funnel = { WARLOCK = {"Health Funnel"} },
          soulstone = { WARLOCK = {"Soulstone"} },
          create_healthstone = { WARLOCK = {"Create Healthstone"} },
          fear = { WARLOCK = {"Fear"} },
          corruption = { WARLOCK = {"Corruption"} },
          drain_life = { WARLOCK = {"Drain Life"} },
          unending_resolve = { WARLOCK = {"Unending Resolve"} },
          demonic_gateway = { WARLOCK = {"Demonic Gateway"} },
          ritual_of_summoning = { WARLOCK = {"Ritual of Summoning"} },
          -- class talents / utility
          howl_of_terror = { WARLOCK = {"Howl of Terror"} },
          mortal_coil = { WARLOCK = {"Mortal Coil"} },
          shadowfury = { WARLOCK = {"Shadowfury"} },
          soulburn = { WARLOCK = {"Soulburn"} },
          demonic_circle = { WARLOCK = {"Demonic Circle"} },
          -- Affliction core
          agony = { WARLOCK = {"Agony"} },
          unstable_affliction = { WARLOCK = {"Unstable Affliction"} },
          drain_soul = { WARLOCK = {"Drain Soul"} },
          seed_of_corruption = { WARLOCK = {"Seed of Corruption"} },
          -- Demonology core
          hand_of_guldan = { WARLOCK = {"Hand of Gul'dan"} },
          demonbolt = { WARLOCK = {"Demonbolt"} },
          summon_felguard = { WARLOCK = {"Summon Felguard"} },
          call_dreadstalkers = { WARLOCK = {"Call Dreadstalkers"} },
          -- Destruction core
          incinerate = { WARLOCK = {"Incinerate"} },
          conflagrate = { WARLOCK = {"Conflagrate"} },
          chaos_bolt = { WARLOCK = {"Chaos Bolt"} },
          rain_of_fire = { WARLOCK = {"Rain of Fire"} },
          -- Warrior-specific tokens (core abilities, interrupts, defensives, utilities, specs)
          charge = { WARRIOR = {"Charge"} },
          heroic_leap = { WARRIOR = {"Heroic Leap"} },
          execute = { WARRIOR = {"Execute"} },
          victory_rush = { WARRIOR = {"Victory Rush"} },
          shield_slam = { WARRIOR = {"Shield Slam"} },
          pummel = { WARRIOR = {"Pummel"} },
          rallying_cry = { WARRIOR = {"Rallying Cry"} },
          intimidating_shout = { WARRIOR = {"Intimidating Shout"} },
          berserker_rage = { WARRIOR = {"Berserker Rage"} },
          hamstring = { WARRIOR = {"Hamstring"} },
          battle_shout = { WARRIOR = {"Battle Shout"} },
          -- class talents / utility
          shockwave = { WARRIOR = {"Shockwave"} },
          storm_bolt = { WARRIOR = {"Storm Bolt"} },
          spell_reflection = { WARRIOR = {"Spell Reflection"} },
          thunder_clap = { WARRIOR = {"Thunder Clap"} },
          avatar = { WARRIOR = {"Avatar"} },
          -- Arms core
          mortal_strike = { WARRIOR = {"Mortal Strike"} },
          overpower = { WARRIOR = {"Overpower"} },
          colossus_smash = { WARRIOR = {"Colossus Smash"} },
          sweeping_strikes = { WARRIOR = {"Sweeping Strikes"} },
          -- Fury core
          bloodthirst = { WARRIOR = {"Bloodthirst"} },
          raging_blow = { WARRIOR = {"Raging Blow"} },
          rampage = { WARRIOR = {"Rampage"} },
          enrage = { WARRIOR = {"Enrage"} },
          -- Protection core
          shield_block = { WARRIOR = {"Shield Block"} },
          revenge = { WARRIOR = {"Revenge"} },
          devastate = { WARRIOR = {"Devastate"} },
          last_stand = { WARRIOR = {"Last Stand"} },
          -- Rogue-specific tokens (stealth, CC, interrupts, defensives, utility, specs)
          stealth = { ROGUE = {"Stealth"} },
          sap = { ROGUE = {"Sap"} },
          cheap_shot = { ROGUE = {"Cheap Shot"} },
          kick = { ROGUE = {"spell:1766"} },
          blind = { ROGUE = {"Blind"} },
          vanish = { ROGUE = {"Vanish"} },
          cloak_of_shadows = { ROGUE = {"Cloak of Shadows"} },
          evasion = { ROGUE = {"Evasion"} },
          sprint = { ROGUE = {"Sprint"} },
          pick_lock = { ROGUE = {"Pick Lock"} },
          pick_pocket = { ROGUE = {"Pick Pocket"} },
          crimson_vial = { ROGUE = {"Crimson Vial"} },
          shiv = { ROGUE = {"Shiv"} },
          -- class talents / utility
          gouge = { ROGUE = {"Gouge"} },
          distract = { ROGUE = {"Distract"} },
          shadowstep = { ROGUE = {"Shadowstep"} },
          smoke_bomb = { ROGUE = {"Smoke Bomb"} },
          thistle_tea = { ROGUE = {"Thistle Tea"} },
          -- Assassination
          mutilate = { ROGUE = {"Mutilate"} },
          rupture = { ROGUE = {"Rupture"} },
          envenom = { ROGUE = {"Envenom"} },
          garrote = { ROGUE = {"Garrote"} },
          -- Outlaw
          sinister_strike = { ROGUE = {"Sinister Strike"} },
          pistol_shot = { ROGUE = {"Pistol Shot"} },
          between_the_eyes = { ROGUE = {"Between the Eyes"} },
          roll_the_bones = { ROGUE = {"Roll the Bones"} },
          -- Subtlety
          backstab = { ROGUE = {"Backstab"} },
          shadowstrike = { ROGUE = {"Shadowstrike"} },
          eviscerate = { ROGUE = {"Eviscerate"} },
          symbols_of_death = { ROGUE = {"Symbols of Death"} },
      }

        -- Helper: check whether the player actually has this spell/talent available.
        local function SpellKnown(sp)
          if not sp then return false end
          -- try numeric id first
          if type(sp) == "number" then
            local ok, name = pcall(GetSpellInfo, sp)
            if not ok or not name or name == "" then return false end
            -- prefer explicit API if present
            local ok2, res = pcall(IsPlayerSpell, sp)
            if ok2 and res then return true end
            ok2, res = pcall(IsSpellKnown, sp)
            if ok2 and res then return true end
            -- fallback: if GetSpellInfo returned a name, assume available
            return true
          end
          -- if given a string name
          do
            local ok, name = pcall(GetSpellInfo, sp)
            if not ok or not name or name == "" then return false end
            -- try IsPlayerSpell by name
            local ok2, res = pcall(IsPlayerSpell, name)
            if ok2 and res then return true end
            ok2, res = pcall(IsSpellKnown, name)
            if ok2 and res then return true end
            -- finally assume it's known if we could resolve a name
            return true
          end
        end

      -- If a special 'interruptoffhand' token is used, treat it like 'interrupt'
      if lk == "interruptoffhand" then lk = "interrupt" end

      local mapping = tokenCandidates[lk]
      if mapping then
        local _, playerClass = UnitClass("player")
        -- prefer class-specific list, else try DEFAULT then try each class's first candidate
        local tried = false
        if playerClass and mapping[playerClass] then
          for _, sid in ipairs(mapping[playerClass]) do
            -- Resolve name and check whether the player actually knows the spell.
            local ok3, sname = pcall(GetSpellInfo, sid)
            if ok3 and sname and sname ~= "" then
              local available = SpellKnown(sid)
              if available then
                OneButtonAssistantDB = OneButtonAssistantDB or {}
                OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
                OneButtonAssistantDB.heuristics = OneButtonAssistantDB.heuristics or {}
                local mappedVal
                if type(sid) == "number" then mappedVal = "spell:" .. tostring(sid) else mappedVal = tostring(sid) end
                OneButtonAssistantDB.aliases[lk] = mappedVal
                OneButtonAssistantDB.heuristics[lk] = { value = mappedVal, time = (GetTime and GetTime() or time()), source = suggestion and (suggestion.source or suggestion.adapter or suggestion.reason) or "engine" }
                key = mappedVal
                name = sname
                -- If user has enabled auto-confirm, promote immediately; otherwise show a UI confirmation if possible
                pcall(function()
                    if OneButtonAssistantDB and OneButtonAssistantDB.heuristicAutoConfirm then
                      if OneButtonAssistant and OneButtonAssistant.PromoteHeuristic then pcall(OneButtonAssistant.PromoteHeuristic, OneButtonAssistant, lk) end
                    else
                      if StaticPopup_Show then StaticPopup_Show("ONEBUTTONASSISTANT_HEURISTIC_CONFIRM", lk, mappedVal, { token = lk, value = mappedVal, source = (suggestion and (suggestion.source or suggestion.adapter or suggestion.reason)) or "engine" }) end
                    end
                end)
                tried = true
                break
              end
            end
          end
        end
        if not tried and mapping.DEFAULT then
          for _, sid in ipairs(mapping.DEFAULT) do
            local ok3, sname = pcall(GetSpellInfo, sid)
            if ok3 and sname and sname ~= "" then
              OneButtonAssistantDB = OneButtonAssistantDB or {}
              OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
              OneButtonAssistantDB.heuristics = OneButtonAssistantDB.heuristics or {}
              local mappedVal
              if type(sid) == "number" then mappedVal = "spell:" .. tostring(sid) else mappedVal = tostring(sid) end
              OneButtonAssistantDB.aliases[lk] = mappedVal
              OneButtonAssistantDB.heuristics[lk] = { value = mappedVal, time = (GetTime and GetTime() or time()), source = suggestion and (suggestion.source or suggestion.adapter or suggestion.reason) or "engine" }
              key = mappedVal
              name = sname
              pcall(function()
                if OneButtonAssistantDB and OneButtonAssistantDB.heuristicAutoConfirm then
                  if OneButtonAssistant and OneButtonAssistant.PromoteHeuristic then pcall(OneButtonAssistant.PromoteHeuristic, OneButtonAssistant, lk) end
                else
                  if StaticPopup_Show then StaticPopup_Show("ONEBUTTONASSISTANT_HEURISTIC_CONFIRM", lk, mappedVal, { token = lk, value = mappedVal, source = (suggestion and (suggestion.source or suggestion.adapter or suggestion.reason)) or "engine" }) end
                end
              end)
              break
            end
          end
        end
        -- as a last resort, try probing across all classes for a common candidate
        if not name then
          for cls, list in pairs(mapping) do
            if type(list) == "table" then
              for _, sid in ipairs(list) do
                local ok3, sname = pcall(GetSpellInfo, sid)
                if ok3 and sname and sname ~= "" then
                  OneButtonAssistantDB = OneButtonAssistantDB or {}
                  OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
                  OneButtonAssistantDB.heuristics = OneButtonAssistantDB.heuristics or {}
                  local mappedVal
                  if type(sid) == "number" then mappedVal = "spell:" .. tostring(sid) else mappedVal = tostring(sid) end
                  OneButtonAssistantDB.aliases[lk] = mappedVal
                  OneButtonAssistantDB.heuristics[lk] = { value = mappedVal, time = (GetTime and GetTime() or time()), source = suggestion and (suggestion.source or suggestion.adapter or suggestion.reason) or "engine" }
                  key = mappedVal
                  name = sname
                  pcall(function()
                    if OneButtonAssistantDB and OneButtonAssistantDB.heuristicAutoConfirm then
                      if OneButtonAssistant and OneButtonAssistant.PromoteHeuristic then pcall(OneButtonAssistant.PromoteHeuristic, OneButtonAssistant, lk) end
                    else
                      if StaticPopup_Show then StaticPopup_Show("ONEBUTTONASSISTANT_HEURISTIC_CONFIRM", lk, mappedVal, { token = lk, value = mappedVal, source = (suggestion and (suggestion.source or suggestion.adapter or suggestion.reason)) or "engine" }) end
                    end
                  end)
                  break
                end
              end
            end
            if name then break end
          end
        end
      end
    end
  end

  -- Fallback to original mapping
  key = key or "unknown"
  -- check user aliases (map arbitrary tokens to spell:<id> or spell names)
  -- Try to normalize common tokens into spell names automatically (e.g., flame_shock -> "Flame Shock")
  if not spellId and type(key) == "string" and key ~= "unknown" then
    local norm = key:gsub("[_%-]", " ")
    norm = norm:gsub("(%a)([%w_']*)", function(a,b) return string.upper(a) .. string.lower(b) end)
    if norm and #norm > 0 then
      local okn, resolved = pcall(GetSpellInfo, norm)
      if okn and resolved and resolved ~= "" then
        name = name or resolved
        key = resolved
        OneButtonAssistantDB = OneButtonAssistantDB or {}
        OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
        OneButtonAssistantDB.aliases[tostring(key):lower()] = resolved
      end
    end
  end

  if OneButtonAssistantDB and OneButtonAssistantDB.aliases and type(OneButtonAssistantDB.aliases) == "table" then
    local lk = tostring(key):lower()
    local ali = OneButtonAssistantDB.aliases[lk]
    if ali then
      -- prefer explicit alias mapping
      key = ali
      -- if alias is a spell:id form, resolve name if possible
      local sId = tostring(ali):match("^spell:(%d+)$")
      if sId then
        local ok, resolved = pcall(GetSpellInfo, tonumber(sId))
        if ok and resolved and resolved ~= "" then
          name = resolved
        end
      else
        name = ali
      end
    end
  end

  -- small heuristics: common tokens map to startattack macro
  local lkey = tostring(key):lower()
    if not OneButtonAssistantDB.aliases or not OneButtonAssistantDB.aliases[lkey] then
    if lkey == "autoattack" or lkey == "startattack" or lkey == "offhand" or lkey == "mainhand" then
      OneButtonAssistantDB = OneButtonAssistantDB or {}
      OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
      OneButtonAssistantDB.heuristics = OneButtonAssistantDB.heuristics or {}
      OneButtonAssistantDB.aliases[lkey] = "macro:/startattack"
      OneButtonAssistantDB.heuristics[lkey] = { value = "macro:/startattack", time = (GetTime and GetTime() or time()), source = "engine" }
      key = "macro:/startattack"
      name = "Auto Attack"
    end
  end
  name = name or tostring(key)
  return { key = key, name = name, reason = suggestion.reason or "external" }
end

-- Optional test helper (runs a few sample states). Uses the logger if present.
function Engine:RunSelfTest()
  local tests = {}
  -- single target, no talents/procs
  self:UpdateState({ talents = {}, procs = {}, enemyCount = 1 })
  table.insert(tests, self:GetNextAction())

  -- single target, TalentA + ProcX
  self:UpdateState({ talents = { TalentA = true }, procs = { ProcX = true }, enemyCount = 1 })
  table.insert(tests, self:GetNextAction())

  -- aoe with proc
  self:UpdateState({ talents = {}, procs = { ProcX = true }, enemyCount = 4 })
  table.insert(tests, self:GetNextAction())

  if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then
    for i, res in ipairs(tests) do
      OneButtonAssistantLogger:Log("selftest", res)
    end
  end
  return tests
end

function Engine:GetBuffRemaining(buffName)
  if not buffName then return nil end
  local now = GetTime and GetTime() or time()
  local exp = playerState.buffs and playerState.buffs[buffName]
  if not exp then return nil end
  return math.max(0, exp - now)
end

OneButtonAssistantEngine = Engine
