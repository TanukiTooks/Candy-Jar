-- Candy Jar
-- Stores Rare Candy, converts banked EXP into Rare Candy, and retrieves
-- stored Rare Candy back into the player's bag.
-- The Candy Jar also provides a custom menu for managing its contents.

local mod = ...

local ItemEffects = require("src.inventory.ItemEffects")
local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local GameVersion = require("src.core.GameVersion")

local IS_GOLD = GameVersion.isGold()
-- Gold's Cinnabar Lab no longer exists.  The Ruins of Alph Research Center is
-- its active research facility and is the Gen 2 home for the quest scientist.
local RESEARCH_MAP = IS_GOLD and "RUINS_OF_ALPH_RESEARCH_CENTER"
  or "CINNABAR_LAB_METRONOME_ROOM"
local RESEARCH_POS = IS_GOLD and { x = 6, y = 4 } or { x = 1, y = 5 }
-- Gold keeps the POWER_PLANT id, but its redesigned interior needs a new
-- placement for the engineer.
local ENGINEER_POS = IS_GOLD and { x = 12, y = 10 } or { x = 27, y = 4 }

local JAR_ID = "CANDY_JAR"
local RARE_CANDY_ID = "RARE_CANDY"
local REGULATOR_ID = "POWER_REGULATOR"
local CRYSTAL_ID = "UNSTABLE_CRYSTAL"

local QUEST_STAGE = "questStage"
local QUEST_CRYSTAL_EXP = "questCrystalExp"
local QUEST_COMPLETE = 4

local EXP_PER_CANDY = 20000
local MAX_STACK = 99 -- Gen 1's own per-item bag cap.

-- Passthrough-only hooks (we never change the values, only read them),
local HOOK_PRIORITY = 500

-- Banked EXP storage

local function getBanked(save)
  return (save and save.candyJarBankedExp) or 0
end

local function addBanked(save, amount)
  if not save or not amount or amount <= 0 then return end
  save.candyJarBankedExp = (save.candyJarBankedExp or 0) + amount
end

local function spendBanked(save, amount)
  if not save then return end
  save.candyJarBankedExp = math.max(0, (save.candyJarBankedExp or 0) - amount)
end

-- Stored candy count

local function getStoredCandy(save)
  return (save and save.candyJarStoredCandy) or 0
end

local function addStoredCandy(save, amount)
  if not save or not amount or amount <= 0 then return end
  save.candyJarStoredCandy = (save.candyJarStoredCandy or 0) + amount
end

local function spendStoredCandy(save, amount)
  if not save then return end
  save.candyJarStoredCandy = math.max(0, (save.candyJarStoredCandy or 0) - amount)
end

local function getQuestData()
  local data = mod.save
  return data
end

local function getQuestStage()
  return mod.save:get(QUEST_STAGE) or 0
end

local function setQuestStage(stage)
  mod.save:set(QUEST_STAGE, stage)
end

local function getCrystalExp()
  return mod.save:get(QUEST_CRYSTAL_EXP) or 0
end

local function addCrystalExp(amount)
  if amount and amount > 0 then
    mod.save:set(QUEST_CRYSTAL_EXP, getCrystalExp() + amount)
  end
end

local function clearCrystalExp()
  mod.save:set(QUEST_CRYSTAL_EXP, 0)
end

local function hasAllBadges(save)
  -- Gen1Recomp stores gym badges as inventory entries, not as a
  -- save.badges bitfield/table.  Check the eight vanilla badge IDs
  -- directly so the quest gate matches the game's actual save format.
  local inventory = save and save.inventory
  if type(inventory) ~= "table" then return false end

  local badges = {
    "BOULDERBADGE",
    "CASCADEBADGE",
    "THUNDERBADGE",
    "RAINBOWBADGE",
    "SOULBADGE",
    "MARSHBADGE",
    "VOLCANOBADGE",
    "EARTHBADGE",
  }

  for _, badgeId in ipairs(badges) do
    if not inventory[badgeId] or inventory[badgeId] <= 0 then
      return false
    end
  end

  return true
end

-- Bag access (confirmed pattern -- see header)

local function getInventoryCount(save, itemId)
  return (save and save.inventory and save.inventory[itemId]) or 0
end

local function setInventoryCount(save, itemId, count)
  save.inventory = save.inventory or {}
  save.inventory[itemId] = count
end

local function orderBag(save)
  local ok, Bag = pcall(require, "src.inventory.Bag")
  if ok and Bag and Bag.order then Bag.order(save) end
end

-- EXP capture: bank whatever a level-100 active fighter would waste

-- Scoped to the current battle.exp_award call via these upvalues. Lua is
-- single-threaded and these hooks fire synchronously (exp.gain only ever
-- fires nested inside battle.exp_award's own next(ctx) call), so this is
-- safe without any extra locking.
local currentAlive = nil
local currentSave = nil

mod.hooks:wrap("battle.exp_award", function(next, ctx)
  local prevAlive, prevSave = currentAlive, currentSave

  currentAlive = {}
  if ctx and ctx.alive then
    for _, mon in ipairs(ctx.alive) do
      currentAlive[mon] = true
    end
  end
  -- battle.game.save is the same path confirmed elsewhere (TextBox.lua
  -- reads game.save.options / game.save.player the same way).
  currentSave = ctx and ctx.battle and ctx.battle.game and ctx.battle.game.save

  local result = next(ctx)

  currentAlive, currentSave = prevAlive, prevSave
  return result
end, HOOK_PRIORITY)

mod.hooks:wrap("exp.gain", function(next, gainCtx)
  local gained = next(gainCtx)

  local mon = gainCtx and gainCtx.mon
  if mon and currentSave and currentAlive and currentAlive[mon]
      and (mon.level or 0) >= 100 and gained and gained > 0 then
    if getQuestStage() == 2
        and getInventoryCount(currentSave, CRYSTAL_ID) > 0 then
      addCrystalExp(gained)
    else
      addBanked(currentSave, gained)
    end
  end

  return gained
end, HOOK_PRIORITY)

-- The items themselves

mod.content.items:register(JAR_ID, {
  id = JAR_ID,
  name = "Candy Jar",
  price = 0, -- not sold in any shop by default
  keyItem = true,
  tossable = false,
})

mod.content.items:register(REGULATOR_ID, {
  id = REGULATOR_ID,
  name = "Power Regulator",
  price = 0,
  keyItem = true,
  tossable = false,
})

mod.content.items:register(CRYSTAL_ID, {
  id = CRYSTAL_ID,
  name = "Unstable Crystal",
  price = 0,
  keyItem = true,
  tossable = false,
})

-- The Candy Jar does not act on a chosen Pokemon, so it does not
-- needed an override here because Candy Jar itself used to level a
-- chosen party member directly.
local baseNeedsTarget = ItemEffects.needsTarget
ItemEffects.needsTarget = function(itemId, itemDef)
  if itemId == JAR_ID then
    return false
  end
  return baseNeedsTarget(itemId, itemDef)
end

-- Unified Candy Jar menu
--
-- item itself is not consumed, the normal bag-use flow receives "failed",
-- and the custom UI is pushed onto game.stack.  We use the same pattern here.
--
-- This means Jar operations happen while the custom menu is on top of the
-- bag.  The stale bag list is therefore never visible while the inventory
-- changes.  On exit we close the underlying bag as well, so we never expose
-- the stale snapshot at all.

-- ListMenu hooks receive the game/context, not the constructed ListMenu.
-- Capture the game while the actual Bag ListMenu is being created.  This is
-- the same game instance later supplied to ItemEffects.use via the bag.
local activeBagGame = nil

mod.hooks:wrap("ui.list_menu", function(next, opts, ctx)
  if ctx and ctx.kind == "bag" and ctx.game then
    activeBagGame = ctx.game
  end
  return next(opts, ctx)
end, HOOK_PRIORITY)

local function closeJarBeforeMessage(menu)
  local game = activeBagGame

  -- Close the Jar first.
  if menu and menu.close then
    menu:close()
  end

  -- The custom Jar is normally reached through BagMenu -> USE/TOSS.
  -- Do not leave either menu visible while operation dialogue is displayed.
  -- Close the remaining UI states from the top down, but stop before the
  -- overworld/game state.  We identify UI states by the presence of close().
  if game and game.stack then
    local stack = game.stack
    for _ = 1, 3 do
      local top = stack:top()
      if not top or not top.close then
        break
      end
      top:close()
    end
  end

  activeBagGame = nil
end

local function closeJarBeforeMessage(menu)
  local game = activeBagGame

  -- Close the Jar first.
  if menu and menu.close then
    menu:close()
  end

  -- The custom Jar is normally reached through BagMenu -> USE/TOSS.
  -- Do not leave either menu visible while operation dialogue is displayed.
  -- Close the remaining UI states from the top down, but stop before the
  -- overworld/game state.  We identify UI states by the presence of close().
  if game and game.stack then
    local stack = game.stack
    for _ = 1, 3 do
      local top = stack:top()
      if not top or not top.close then
        break
      end
      top:close()
    end
  end

  activeBagGame = nil
end

local function closeJarMenu(menu)
  local game = activeBagGame

  if menu and menu.close then
    menu:close()
  end

  if game and game.stack then
    local top = game.stack:top()
    if top and top.close then
      top:close()
    end
  end

  activeBagGame = nil
end

local function candyJarRows(save)
  local bagCandy = getInventoryCount(save, RARE_CANDY_ID)
  local stored = getStoredCandy(save)
  local banked = getBanked(save)
  return {
    {
      label = "Store Candy",
      value = "store",
    },
    {
      label = "Candify EXP",
      value = "press",
    },
    {
      label = "Retrieve Candy",
      value = "retrieve",
    },
    {
      label = "Close",
      value = "close",
    },
  }
end

local function openCandyJarMenu(game)
  if not (game and game.save and game.stack and mod.ui
      and mod.ui.ListMenu) then
    return false
  end

  local function reopen()
    openCandyJarMenu(game)
  end

  local function messageThen(text, again)
    game.stack:push(TextBox.new(game, text, again and reopen or nil))
  end

  local function doStore(menu)
    closeJarMenu(menu)
    local save = game.save
    local have = getInventoryCount(save, RARE_CANDY_ID)
    if have <= 0 then
      messageThen(Strings("You have no\nRare Candy to\nstore."), true)
      return
    end

    local Bag = require("src.inventory.Bag")
    Bag.remove(save, RARE_CANDY_ID, have)
    addStoredCandy(save, have)
    messageThen(Strings(
      "Stored %d Rare\nCandy in the jar!\fThe jar now holds\n%d Rare Candy.",
      have, getStoredCandy(save)), true)
  end

  local function doPress(menu)
    closeJarBeforeMessage(menu)
    local save = game.save
    local banked = getBanked(save)
    local produced = math.floor(banked / EXP_PER_CANDY)
    if produced <= 0 then
      messageThen(Strings(
        "The jar holds\n%d EXP.\fPressing a candy\nneeds %d EXP.",
        banked, EXP_PER_CANDY), true)
      return
    end

    spendBanked(save, produced * EXP_PER_CANDY)
    addStoredCandy(save, produced)
    messageThen(Strings(
      "Candified %d Rare\nCandy!\f%d EXP remains\nbanked.\fThe jar now holds\n%d Rare Candy.",
      produced, getBanked(save), getStoredCandy(save)), true)
  end

  local function doRetrieve(menu)
    closeJarBeforeMessage(menu)
    local save = game.save
    local stored = getStoredCandy(save)
    if stored <= 0 then
      messageThen(Strings("The jar has no\nRare Candy stored."), true)
      return
    end

    local have = getInventoryCount(save, RARE_CANDY_ID)
    local room = MAX_STACK - have
    if room <= 0 then
      messageThen(Strings("Your Rare Candy\npocket is full!"), true)
      return
    end

    local moved = math.min(stored, room)
    setInventoryCount(save, RARE_CANDY_ID, have + moved)
    spendStoredCandy(save, moved)
    orderBag(save)
    messageThen(Strings(
      "Retrieved %d Rare\nCandy.\f%d Rare Candy\nremain in the jar.",
      moved, getStoredCandy(save)), true)
  end

  local menu
  local jarTitle = "-:- Candy Jar -:-"
  menu = mod.ui.ListMenu.new(game, jarTitle, candyJarRows(game.save), {
    onCancel = function()
      closeJarMenu(menu)
    end,
    onChoose = function(item)
      if item.value == "store" then
        doStore(menu)
      elseif item.value == "press" then
        doPress(menu)
      elseif item.value == "retrieve" then
        doRetrieve(menu)
      else
        closeJarMenu(menu)
      end
    end,
  })

  -- Custom Candy Jar layout:
  --   title at the top
  --   three live storage values beneath it
  --   four actions grouped at the bottom
  -- ListMenu still supplies all input/navigation; only its renderer is
  -- replaced for this menu so the action list has no right-hand counts.
  menu.draw = function(self)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, 160, 144)
    love.graphics.setColor(0, 0, 0, 1)

    local xTitle = math.floor((160 - Font.width(self.title)) / 2)
    Font.draw(self.title, xTitle, 4)

    local save = self.game.save
    local bagCandy = getInventoryCount(save, RARE_CANDY_ID)
    local stored = getStoredCandy(save)
    local banked = getBanked(save)

    Font.draw("Bag Candy: x" .. tostring(bagCandy), 8, 24)
    Font.draw("Jar Candy: x" .. tostring(stored), 8, 40)
    Font.draw("Banked EXP: " .. tostring(banked), 8, 56)

    -- A one-pixel separator keeps the information block visually distinct
    -- from the action area without consuming another text row.
    love.graphics.rectangle("fill", 8, 72, 144, 1)

    local optionY = {80, 96, 112, 128}
    for i, item in ipairs(self.items) do
      local y = optionY[i]
      if y then
        Font.draw(item.label, 16, y)
        if i == self.index then
          Font.drawCode(Theme.cursor, 8, y)
        end
      end
    end

    love.graphics.setColor(1, 1, 1, 1)
  end

  game.stack:push(menu)
  return true
end

local baseUse = ItemEffects.use
ItemEffects.use = function(data, save, itemId, target, battle, moveIndex, ow)
  if itemId == JAR_ID then
    if battle then
      return "failed", { Strings("OAK: %s!\nThis isn't the\ntime to use that!",
        save.player and save.player.name or "") }
    end

    -- Match Thunderheart: the item is a gateway to its own UI, not a
    -- consumed item effect. BagMenu therefore leaves the Jar itself alone.
    local game = nil
    if activeBagGame and activeBagGame.save == save then
      game = activeBagGame
    end
    if game and openCandyJarMenu(game) then
      return "failed", nil
    end
    return "failed", { Strings("The Candy Jar\nis unavailable right now.") }
  end

  -- Preserve every vanilla item effect. The Candy Jar is the only item
  -- whose behaviour is overridden by this mod.
  return baseUse(data, save, itemId, target, battle, moveIndex, ow)
end

-- Power Plant Engineer
local ENGINEER_OBJECT = "CANDY_JAR_POWER_ENGINEER"
local ENGINEER_TEXT = "TEXT_CANDY_JAR_POWER_ENGINEER"
local ENGINEER_TRAINER = "CANDY_JAR_ENGINEER"

mod.content.trainers:register(ENGINEER_TRAINER, {
  id = ENGINEER_TRAINER,
  name = "ENGINEER",
  basePic = "OPP_ENGINEER",
  baseMoney = 5,
  parties = {
    {
      { species = "ELECTRODE", level = 52 },
      { species = "ELECTABUZZ", level = 55 },
      { species = "MAGNETON", level = 58 },
    },
  },
})

if not IS_GOLD then
  mod.content.maps:patch("POWER_PLANT", {
    objects = { __append = {
      {
        index = 91,
        x = ENGINEER_POS.x,
        y = ENGINEER_POS.y,
        sprite = "SPRITE_SUPER_NERD",
        movement = "STAY",
        range = "DOWN",
        text = ENGINEER_TEXT,
        name = ENGINEER_OBJECT,
        hidden = true,
      },
    } },
  })
end

if not IS_GOLD then
mod.content.map_scripts:register("POWER_PLANT", {
  onEnter = function(game, ow)
    if getQuestStage() == 1 and getInventoryCount(game.save, REGULATOR_ID) <= 0 then
      ow:queueScript({
        { "show_object", "POWER_PLANT", ENGINEER_OBJECT },
      })
    else
      ow:queueScript({
        { "hide_object", "POWER_PLANT", ENGINEER_OBJECT },
      })
    end
  end,
  talk = {
    [ENGINEER_TEXT] = {
      { "face_player" },
      { "show_text",
        "Hey there. Didn't expect to\nsee anyone else in here.\fI'm an engineer. I've been\nlooking around for useful\nsalvage.\fThis old place is full of\nequipment that nobody seems\nto want anymore.\fA Power Regulator? I could\nhelp you find one, I guess.\fI'd be willing to help... but\nyou've got to prove you're\nstrong enough to put it to\ngood use.\fHow about a Pokémon battle?" },
      { "start_battle", "trainer", ENGINEER_TRAINER, 1 },
      { "check_battle_result", "win" },
      { "jump_if_false", "lost" },
      { "show_text",
        "You beat me fair and square!\fYou've got the strength to\nmake good use of this.\fHere. Take the Power\nRegulator I found." },
      { "give_item", REGULATOR_ID },
      { "hide_object", "POWER_PLANT", ENGINEER_OBJECT },
      { "jump", "end" },
      { "label", "lost" },
      { "show_text",
        "Not bad. But you'll need to\nbeat me if you want that Power\nRegulator.\fCome back when you're ready." },
    },
  },
})
end

-- Existing Eevee scientist
local GIFT_TEXT = "TEXT_CINNABARLABMETRONOMEROOM_SCIENTIST2"

local function vanillaEeveeDialogue(game, overworld, npc)
  local text = select(1, game.data:resolveText(
    overworld.map.def.label, GIFT_TEXT))
  if npc then npc:facePlayer(overworld.player) end
  if text then
    game.stack:push(TextBox.new(game, text))
  end
end

if not IS_GOLD then
mod.content.map_scripts:register("CINNABAR_LAB_METRONOME_ROOM", {
  talk = {
    [GIFT_TEXT] = function(game, overworld, npc, onDone)
      vanillaEeveeDialogue(game, overworld, npc)
    end,
  },
})
end

-- Candy Jar research scientist
local QUEST_TEXT = "TEXT_CANDY_JAR_SCIENTIST"
local SCIENTIST_INDEX = 900

local function questText(game, overworld, npc, text, callback, ...)
  if npc then npc:facePlayer(overworld.player) end
  game.stack:push(TextBox.new(game, Strings(text, ...), callback))
end

local function yesNoMenu(game, onYes)
  local menu
  menu = mod.ui.ListMenu.new(game, "RESEARCH", {
    { label = "Yes", value = true },
    { label = "No", value = false },
  }, {
    onCancel = function()
      menu:close()
    end,
    onChoose = function(item)
      local answer = item.value
      menu:close()
      if answer then
        onYes()
      else
        game.stack:push(TextBox.new(game,
          Strings("I understand. If you\nchange your mind, come\nand speak to me again.")))
      end
    end,
  })
  game.stack:push(menu)
end

local function giveItem(game, itemId)
  local Bag = require("src.inventory.Bag")
  return Bag.add(game.save, itemId, 1, game.data)
end

local function scientistQuest(game, overworld, npc)
  local save = game.save
  local stage = getQuestStage()

  if stage >= QUEST_COMPLETE or getInventoryCount(save, JAR_ID) > 0 then
    setQuestStage(QUEST_COMPLETE)
    questText(game, overworld, npc,
      "The Candy Jar stores\nunused potential and\nturns it into something\nuseful.")
    return
  end

  if stage == 0 then
    if not hasAllBadges(save) then
      questText(game, overworld, npc,
        "I'm studying some unusual\ncrystals from Paldea.\nThe work is fascinating,\nbut I'm not ready for help yet.")
      return
    end

    questText(game, overworld, npc,
      "Eight badges... Impressive.\nI'm looking for a really\nstrong trainer to help me\nwith my research.\fWould you help me?", function()
        yesNoMenu(game, function()
          setQuestStage(1)
          mod.save:set("engineerActive", true)
          questText(game, overworld, npc,
            "Excellent. My research\nconcerns crystals from\nArea Zero in Paldea.\fI believe they can retain\npotential that a Pokémon\ncan no longer use.\fI need a piece of equipment\nto test the theory. I've heard\nKanto once used something\nlike it for power generation.\fLook for a Power Regulator\nat the old Power Plant and\nbring it back to me.")
        end)
      end)
    return
  end

  if stage == 1 then
    if getInventoryCount(save, REGULATOR_ID) > 0 then
      local Bag = require("src.inventory.Bag")
      Bag.remove(save, REGULATOR_ID, 1)
      if giveItem(game, CRYSTAL_ID) then
        setQuestStage(2)
        clearCrystalExp()
        questText(game, overworld, npc,
          "You found it! Excellent.\nThis is exactly what I needed.\fI'll work on the containment\nvessel while you field-test\nmy process.\fTake this Unstable Crystal.\nExpose it to the potential\nreleased by a very strong\nPokémon in battle, then bring\nit back to me.")
      else
        Bag.add(save, REGULATOR_ID, 1, game.data)
        questText(game, overworld, npc,
          "You'll need room in your\nbag before I can continue.")
      end
    else
      questText(game, overworld, npc,
        "The Power Regulator should\nbe somewhere in the old\nPower Plant. Bring it back\nwhen you find it.")
    end
    return
  end

  if stage == 2 then
    local crystalExp = getCrystalExp()
    if crystalExp >= EXP_PER_CANDY then
      local Bag = require("src.inventory.Bag")
      Bag.remove(save, CRYSTAL_ID, 1)
      clearCrystalExp()
      setQuestStage(3)
      questText(game, overworld, npc,
        "You did it! The crystal is\nholding the potential!\fMy theory was correct!\nThe excess potential can\nreally be captured and stored.\fGive me a moment. I just\nneed to finish the containment\nvessel.", function()
          require("src.core.Sound").play(game.data, "Heal")
          questText(game, overworld, npc,
            "There! It's finished.\fThis is the first successful\nprototype. You earned it.\fYou received the Candy Jar!",
            function()
              if giveItem(game, JAR_ID) then
                setQuestStage(QUEST_COMPLETE)
              end
            end)
        end)
    elseif crystalExp > 0 then
      questText(game, overworld, npc,
        "The process seems to be\nworking. I can see some\npotential stored in the crystal,\nbut I need more testing.\fKeep going. I need at least\n%d units before I can draw any\nconclusions.",
        nil, EXP_PER_CANDY)
    else
      questText(game, overworld, npc,
        "The Unstable Crystal is\nready for field testing.\fTake it into battle with a\nPokémon that has reached its\nfull potential, then bring it\nback to me.")
    end
    return
  end

  if stage == 3 then
    questText(game, overworld, npc,
      "Just a moment longer. I'm\nstill finishing the vessel.")
  end
end

if not IS_GOLD then
mod.content.map_scripts:register("CINNABAR_LAB_METRONOME_ROOM", {
  talk = {
    [QUEST_TEXT] = function(game, overworld, npc, onDone)
      scientistQuest(game, overworld, npc)
    end,
  },
})
end

mod.content.maps:patch(RESEARCH_MAP, {
  objects = { __append = {
    {
      index = SCIENTIST_INDEX,
      x = RESEARCH_POS.x,
      y = RESEARCH_POS.y,
      sprite = "SPRITE_SCIENTIST",
      movement = "STAY",
      range = "NONE",
      text = QUEST_TEXT,
      name = "CANDY_JAR_SCIENTIST",
    },
  } },
})

-- Gold has no map_scripts registry yet.  Its engineer is therefore a runtime
-- object, recreated when the player enters the Power Plant only while the
-- regulator objective is active.  This keeps the Gen 1 event-script version
-- intact while using Gold's supported world API for visibility.
if IS_GOLD then
  local goldEngineerId
  local function refreshGoldEngineer()
    local ow = mod.world:overworld()
    local onPowerPlant = ow and ow.map and ow.map.id == "POWER_PLANT"
    local active = onPowerPlant and getQuestStage() == 1
      and getInventoryCount(ow.game.save, REGULATOR_ID) <= 0
    if active and not goldEngineerId then
      goldEngineerId = mod.world:spawnNpc("POWER_PLANT", {
        x = ENGINEER_POS.x,
        y = ENGINEER_POS.y,
        sprite = "SPRITE_SUPER_NERD",
        movement = "STAY",
        range = "DOWN",
        text = ENGINEER_TEXT,
        name = ENGINEER_OBJECT,
      })
    elseif not active and goldEngineerId then
      mod.world:removeNpc(goldEngineerId)
      goldEngineerId = nil
    end
  end
  mod.events:on("map.entered", refreshGoldEngineer)
end

mod.log:info("Candy Jar loaded")
