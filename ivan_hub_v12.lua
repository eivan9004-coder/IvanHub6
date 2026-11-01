--[[ ====================================================================
     Иван Хаб | Steal an Egg  (v12)
     Вставь в экзекьютор и нажми Execute.
     Две панели тянутся отдельно за шапку: левое меню и правая «Кража».
     Круглая кнопка «ИХ» (тоже тянется) и RightShift скрывают/показывают всё.
     Все этапы пишут в консоль (F9): [DEBUG] ...

     Как ищутся яйца:
       обычные ..... Part «SmartPromptPart» по всему Workspace, у которого внутри
                     ProximityPrompt с ActionText = "Steal" («Apply Mutation» игнорируется)
       Хэллоуин .... Workspace.HalloweenDimension.WorldEggs.HalloweenEgg
                     (модели с атрибутом PreparedSourceName)
     Данные (вес, доход, редкость) берутся из BillboardGui.TextLabel ближайшего
     NestModel (GuardAreas) или HalloweenEgg — по координатам.
     Сдача: EggCarryBounds.SafeZone (обычные) / HalloweenDimension.Zones.SafeZone.
==================================================================== ]]

local function IvanHubMain()

-- ============================== КОНФИГ ==================================
local Config = {
    Debug = true,               -- печатать [DEBUG] в консоль
    ScanInterval = 2,           -- период сканера (сек)
    FarDistance = 100,          -- дальше: Noclip + MoveTo; ближе: Pathfinding + MoveTo
    PortalJump = 500,           -- скачок позиции больше этого = портал → пересчёт маршрута
    NestRadius = 5,             -- NestModel считается «своим» яйцу, если ближе этого (studs, до границ модели)
    NestFarRadius = 40,         -- запасной радиус: если в 5 studs гнезда нет, берём ближайшее в этом радиусе
    BillboardRadius = 12,       -- запасной поиск BillboardGui рядом с SmartPromptPart (studs)
    BackOffTime = 3,            -- сколько ждать после удара стража (сек)
    MoveMode = "Walk",          -- Walk | Fly (AlignPosition + AlignOrientation)
    FlySpeed = 80,              -- скорость авто-полёта к цели
    Priority = "Closest",       -- Closest | Income | Rarity | Weight
    StartBiome = "All",         -- All | Auto (по скорости) | имя биома
    SpeedOverride = 0,          -- >0: ручная «скорость» для режима Auto
    SpeedMargin = 1.25,         -- запас к минимальной скорости биома
    HalloweenEggs = false,      -- в Хэллоуин-измерении брать только яйца Хэллоуина
    Cooldown = 1,               -- пауза между циклами кражи
    TargetZone = "Auto",        -- «Куда нести»: All/Auto/Forest = стандартная база SafeZone; Хэллоуин = SafeZone измерения;
                                -- другой биом = SafeZone внутри этого биома (если нет — стандартная база)
    AntiAFK = true,             -- LocalPlayer.Idled → VirtualUser
    AntiTraps = false,          -- Trap / Spike / Beartrap / Snare → CanTouch = false
    YouTubeURL = "https://raw.githubusercontent.com/Dan41/Roblox-Scripts/main/Youtube%20Music%20Player/YoutubeMusicPlayer.lua",

    -- Питомцы
    AutoEquipBest = false,
    AutoFuse = false, FuseRarities = { Common = true }, NeverFuseMutated = true, NeverFuseEquipped = true, FuseCount = 3,
    AutoSell = false, SellRarities = { Common = true }, NeverSellMutated = true, NeverSellEquipped = true,
    AutoDelete = false, DeleteRarities = {},          -- ОПАСНО: удаляет навсегда
    -- Прогресс
    AutoTreadmill = false, TreadmillDir = 1, TreadmillUsePrompt = true,
    AutoBuyUpgrades = false, AutoClaimIndex = false,
    -- Хэллоуин
    AutoPhantom = false, AutoMonsters = false, AutoFishing = false,
    -- Игрок
    WalkSpeedOverride = false, WalkSpeed = 16, JumpPowerOverride = false, JumpPower = 50,
    Fly = false, PlayerFlySpeed = 70, AntiRagdoll = false, AntiKnockback = true, InfJump = false, NoClip = false,
    -- ESP
    ESPEggs = false, ESPGuards = false, ESPPets = false, ESPPlayers = false,
    -- Музыка
    Volume = 0.5,
    Music = {
        { name = "Phonk", id = "rbxassetid://9046862126" },
        { name = "Bass",  id = "rbxassetid://1836342909" },
    },
    -- Прочее
    RemoteDelay = 0.25,         -- мин. пауза между вызовами remote (0.2-0.3 с)
    RemoteOverrides = {},       -- {sell = "ReplicatedStorage.Remotes.Sell"} — имя или путь
}

local Biomes = {
    { name = "Forest", minSpeed = 0 },        { name = "Lake", minSpeed = 900 },
    { name = "Desert", minSpeed = 10e3 },     { name = "Jungle", minSpeed = 40e3 },
    { name = "Snow", minSpeed = 170e3 },      { name = "Volcano", minSpeed = 700e3 },
    { name = "Abyss Ocean", minSpeed = 2.5e6 }, { name = "Prehistoric", minSpeed = 18e6 },
    { name = "Cosmic", minSpeed = 700e6 },    { name = "Cherry Blossom", minSpeed = 2.5e9 },
    { name = "Titan Temple", minSpeed = 7e9 }, { name = "Angels & Demons", minSpeed = 20e9 },
    { name = "Enchanted Forest", minSpeed = 50e9 },
}
local Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Cosmic", "Eternal", "Divine" }
local RarityRank = {}
for i, r in ipairs(Rarities) do RarityRank[r] = i end
local RarityRU = { Common = "Обычный", Uncommon = "Необычный", Rare = "Редкий", Epic = "Эпический", Legendary = "Легендарный",
    Mythic = "Мифический", Secret = "Секретный", Cosmic = "Космос", Eternal = "Вечный", Divine = "Божественный" }
local RarityColor = {
    Common = Color3.fromRGB(190, 190, 190), Uncommon = Color3.fromRGB(110, 220, 110), Rare = Color3.fromRGB(90, 160, 255),
    Epic = Color3.fromRGB(190, 110, 255), Legendary = Color3.fromRGB(255, 190, 60), Mythic = Color3.fromRGB(255, 90, 120),
    Secret = Color3.fromRGB(240, 240, 240), Cosmic = Color3.fromRGB(100, 240, 255), Eternal = Color3.fromRGB(255, 120, 255), Divine = Color3.fromRGB(255, 245, 160),
}
local RarityRUStems = {          -- корни русских названий (без первой буквы — регистр не важен)
    Divine = { "жествен" }, Eternal = { "ечн" }, Cosmic = { "осмос" }, Secret = { "екретн" }, Mythic = { "ифич" }, Legendary = { "егендарн" },
    Epic = { "пич" }, Rare = { "едк" }, Uncommon = { "еобычн" }, Common = { "бычн" },
}
local MutationWords = { "golden", "diamond", "rainbow", "spectral", "shiny", "neon", "gold", "radioactive", "galaxy",
    "золот", "алмаз", "радуж", "призрач", "неон" }
local KnownPets = {
    Chicken = 1, Dog = 2, Bird = 8, Owl = 35, Raccoon = 45, Fox = 180, Bear = 240, ["Brr Brr Patapim"] = 1800, Frog = 3,
    Duckling = 4, Catfish = 12, Turtle = 60, Swan = 320, Axolotl = 2800, Leviathan = 220e3, Jerboa = 6, Fennec = 18, Camel = 75,
    Snake = 3600, Scorpion = 18500, ["Royal Sphinx"] = 280e3, Chimpanzee = 90, Toucan = 110, Crocodile = 420, Gorilla = 4800,
    Spider = 22e3, Tiger = 28e3, ["King Snake"] = 3.5e6,
}
-- ЖЁСТКАЯ ТАБЛИЦА: питомцы по биомам и их базовые параметры (вес, доход). Данные игры в мире не читаются.
-- min/max = диапазон дохода для редкости; income = точное значение; weight только там, где он известен.
local EggStats = {
    ["Forest"] = {
        { rarity = "Common", min = 1, max = 6 },          { rarity = "Uncommon", min = 8, max = 12 },
        { rarity = "Rare", min = 35, max = 220 },         { rarity = "Epic", min = 180, max = 1100 },
        { rarity = "Legendary", min = 1800, max = 15000 }, { rarity = "Mythic", min = 16000, max = 120000 },
    },
    ["Lake"] = { { name = "Axolotl", rarity = "Legendary", income = 2800, weight = 28 },
                 { name = "Leviathan", rarity = "Cosmic", income = 220000, weight = 5000 } },
    ["Desert"] = { { name = "Scorpion", rarity = "Mythic", income = 18500 }, { name = "Royal Sphinx", rarity = "Cosmic", income = 280000 } },
    ["Jungle"] = { { name = "King Snake", rarity = "Secret", income = 3.5e6 } },
    ["Snow"] = { { name = "Ice Dragon", rarity = "Eternal", income = 65e6 } },
    ["Volcano"] = { { name = "Lava Dragon", rarity = "Eternal", income = 100e6 } },
    ["Abyss Ocean"] = { { name = "El Maja", rarity = "Eternal", income = 130e6 }, { name = "Kraken", rarity = "Secret", income = 15e6 } },
    ["Prehistoric"] = { { name = "Mosasaurus", rarity = "Eternal", income = 180e6 } },
    ["Cosmic"] = { { name = "Unicorn", rarity = "Divine", income = 1e9 } },
    ["Cherry Blossom"] = { { name = "Kitsune", rarity = "Divine", income = 1.8e9 } },
    ["Titan Temple"] = { { name = "Nightflame", rarity = "Divine", income = 3e9 } },
    ["Angels & Demons"] = { { name = "ArchAngel / World Burner", rarity = "Divine", income = 5e9 } },
    ["Enchanted Forest"] = { { name = "Royal Skywhale", rarity = "Divine", income = 8e9 } },
}
local P = {                       -- паттерны (Lua-patterns по имени в нижнем регистре)
    petContainers = { "^pets?$", "petinventory", "^inventory$", "^petinv" },
    upgradePrompts = { "upgrade", "buy" },
    swingTool = { "sword", "bat", "bonk", "hammer", "slap", "swing" },
    fisherman = { "fisherman" }, rod = { "rod" }, phantom = { "phantom", "express" },
    monster = { "monster", "ghoul", "zombie", "skeleton", "wraith", "mummy", "reaper", "ghost" },
    guard = { "guard" },
    Remotes = {
        equipBest = { "equipbest", "equip", "setpet" }, sell = { "sell" }, fuse = { "fuse", "merge" }, delete = { "delete", "discard" },
        index = { "index" }, upgrade = { "upgrade" }, swing = { "swing", "hit", "attack" }, fish = { "fish", "cast", "reel" },
    },
}

-- ============================== СЕРВИСЫ / СОСТОЯНИЕ =====================
local env = (getgenv and getgenv()) or _G
for _, k in ipairs({ "IvanHub", "IvanHubV5", "IvanHubV6", "IvanHubV7", "IvanHubV8", "IvanHubV9", "IvanHubV10", "IvanHubV11", "IvanHubV12" }) do      -- выгружаем старые версии
    if env[k] and env[k].Unload then pcall(env[k].Unload) end
end
local IH = { Alive = true, Conns = {} }
env.IvanHubV12 = IH

local cloneref = cloneref or function(x) return x end
local Svc = {}
for _, n in ipairs({ "Players", "ReplicatedStorage", "UserInputService", "RunService", "TweenService", "CoreGui", "SoundService",
    "PathfindingService", "Lighting", "VirtualUser", "TeleportService", "HttpService" }) do
    Svc[n] = cloneref(game:GetService(n))
end
local LP = Svc.Players.LocalPlayer

local U, W, M, A, E, UI = {}, {}, {}, {}, {}, {}
local State = {
    running = false, oneShot = false, gen = 0, cycleNo = 0, farming = false, expectCarry = false, forced = nil,
    blacklist = {}, eggs = {}, scanAt = 0, scanning = false, nests = {}, nestAt = -100, noclip = false, moving = false,
    lastCount = -1, lastSummary = "", stats = { eggs = 0, fails = 0, pets = 0 },
    plotCache = nil, plotDumped = false, treadEntered = false, remoteCache = {}, variantIdx = {}, lastFire = 0,
    petCounts = {}, firstPets = true, lastPets = {}, baseWalk = 16, lastSet = nil, flyObjs = nil, flyTarget = nil,
    spawnPos = nil, hCache = nil, hCacheAt = -100, lastStatus = "", Remotes = {},
    hitAt = nil, lastHealth = nil, wasRag = false, hitCount = {}, dataWarned = {}, portalCache = nil, portalAt = -100,
    rarWarned = {}, ytArmed = false, traps = {}, trapScanAt = -100, biomeBoxes = nil, biomeBoxAt = -100,
    queue = {}, nameDbg = {}, returnSpeed = nil, promptLogged = {},
}
local ui = {}

-- ============================== U: УТИЛИТЫ ==============================
local function dbg(msg, ...)
    if not Config.Debug then return end
    local args = table.pack(...)
    local parts = { tostring(msg) }
    for i = 1, args.n do parts[#parts + 1] = tostring(args[i]) end
    print("[DEBUG] " .. table.concat(parts, " "))
end
local function tb(e)
    return tostring(e) .. " | " .. ((debug and debug.traceback) and debug.traceback("", 2) or "")
end
local function setStatus(t)
    if ui.status then ui.status.Text = "Статус: " .. tostring(t) end
    if t ~= State.lastStatus then dbg("СТАТУС:", t); State.lastStatus = t end
end
local function getChar() return LP.Character end
local function getHum() local c = LP.Character; return c and c:FindFirstChildOfClass("Humanoid") end
local function getHRP() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function alive() local h = getHum(); return h ~= nil and h.Health > 0 and getHRP() ~= nil end
local function hdist(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end

function U.norm(s) return (tostring(s):lower():gsub("[^%w]", "")) end
function U.matchAny(name, list)
    name = tostring(name):lower()
    for _, pat in ipairs(list) do if name:find(pat) then return true end end
    return false
end
function U.dig(root, path)
    local n = root
    for seg in tostring(path):gmatch("[^%.]+") do
        if not n then return nil end
        n = n:FindFirstChild(seg)
    end
    return n
end
function U.resolvePath(path)
    local node = game
    for seg in tostring(path):gmatch("[^%.]+") do
        if seg ~= "game" then
            local nxt
            if node == game then pcall(function() nxt = game:GetService(seg) end) end
            if not nxt and node == Svc.Players and seg == "LocalPlayer" then nxt = LP end
            nxt = nxt or node:FindFirstChild(seg)
            if not nxt then return nil end
            node = nxt
        end
    end
    return node ~= game and node or nil
end
function U.posOf(inst)
    local ok, p = pcall(function()
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then return inst:GetPivot().Position end
        local sum, n = Vector3.zero, 0
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("BasePart") then sum += d.Position; n += 1 end
        end
        if n > 0 then return sum / n end
    end)
    return ok and p or nil
end
function U.boxOf(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.CFrame, inst.Size end
    if inst:IsA("Model") then
        local ok, cf, sz = pcall(function() return inst:GetBoundingBox() end)
        if ok then return cf, sz end
    end
    local minV, maxV, n = Vector3.one * math.huge, Vector3.one * -math.huge, 0
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("BasePart") then
            local p, s = d.Position, d.Size / 2
            minV = Vector3.new(math.min(minV.X, p.X - s.X), math.min(minV.Y, p.Y - s.Y), math.min(minV.Z, p.Z - s.Z))
            maxV = Vector3.new(math.max(maxV.X, p.X + s.X), math.max(maxV.Y, p.Y + s.Y), math.max(maxV.Z, p.Z + s.Z))
            n += 1
        end
    end
    if n == 0 then return nil end
    return CFrame.new((minV + maxV) / 2), maxV - minV
end
function U.insideBox(inst, margin)
    local cf, size = U.boxOf(inst)
    local hrp = getHRP()
    if not cf or not hrp then return false end
    local rel = cf:PointToObjectSpace(hrp.Position)
    margin = margin or 0
    return math.abs(rel.X) <= size.X / 2 + margin and math.abs(rel.Z) <= size.Z / 2 + margin and math.abs(rel.Y) <= size.Y / 2 + 12
end
function U.groundAt(x, z, yTop)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { LP.Character }
    local r = workspace:Raycast(Vector3.new(x, yTop + 60, z), Vector3.new(0, -500, 0), params)
    return r and (r.Position.Y + 3) or (yTop + 3)
end
local SUF = { K = 1e3, M = 1e6, B = 1e9, T = 1e12, Q = 1e15, QA = 1e15 }
function U.parseNum(v, suffix)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return nil end
    local s = v:gsub("[%$,%s]", "")
    local num, suf = s:match("^([%d%.]+)(%a*)$")
    local n = tonumber(num)
    if not n then return nil end
    suf = ((suffix and suffix ~= "") and suffix or suf or ""):upper()
    return n * (SUF[suf] or 1)
end
function U.fmt(n)
    if not n then return "Неизвестно" end
    for _, u in ipairs({ { 1e15, "Q" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
        if n >= u[1] then return ("%.2f%s"):format(n / u[1], u[2]) end
    end
    return tostring(math.floor(n))
end
function U.fmt2(n) return n and U.fmt(n) or "—" end
function U.connect(sig, fn)
    local c = sig:Connect(function(...)
        local ok, e = xpcall(fn, tb, ...)
        if not ok then dbg("ОШИБКА в обработчике:", e) end
    end)
    IH.Conns[#IH.Conns + 1] = c
    return c
end
function U.loop(interval, fn)
    task.spawn(function()
        while IH.Alive do
            local ok, e = xpcall(fn, tb)
            if not ok then dbg("ОШИБКА цикла:", e) end
            task.wait(type(interval) == "function" and interval() or interval)
        end
    end)
end
function U.throttle()
    local dt = tick() - State.lastFire
    if dt < Config.RemoteDelay then task.wait(Config.RemoteDelay - dt) end
    State.lastFire = tick()
end
function U.isCarrying()
    local c = getChar()
    if not c then return false end
    for _, k in ipairs({ "Carrying", "CarryingEgg", "HasEgg", "IsCarrying" }) do
        if LP:GetAttribute(k) or c:GetAttribute(k) then return true end
    end
    for _, d in ipairs(c:GetDescendants()) do
        if d.Name:lower():find("egg") then return true end
    end
    return false
end
function U.inOtherChar(d)
    local cur = d.Parent
    for _ = 1, 6 do
        if not cur or cur == workspace then return false end
        if cur:IsA("Model") and Svc.Players:GetPlayerFromCharacter(cur) then return true end
        cur = cur.Parent
    end
    return false
end

-- ============================== W: ДАННЫЕ ЯИЦ / МИР =====================
local function hasAny(text, list)
    for _, s in ipairs(list) do if text:find(s, 1, true) then return true end end
    return false
end
local function rarityOf(text)
    local low = text:lower()
    for i = #Rarities, 1, -1 do
        local r = Rarities[i]
        if low:find(r:lower(), 1, true) then return r end
        local stems = RarityRUStems[r]
        if stems and hasAny(text, stems) then return r end
    end
    return nil
end

local GENERIC_TEXT = { steal = true, egg = true, take = true, e = true, ["apply mutation"] = true }
local function cleanText(s)
    local t = tostring(s):gsub("<[^>]+>", "")
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    return t
end

-- Вес / доход / редкость из списка текстов (регулярки). Нет данных → nil («Неизвестно»)
function W.parseTexts(texts, fallbackName)
    local d = { texts = texts, text = table.concat(texts, " | ") }
    local nameCand
    for _, t in ipairs(texts) do
        local low = t:lower()
        local w = low:match("([%d%.,]+)%s*kg")
        if w and not d.weight then d.weight = tonumber((w:gsub(",", ""))) end
        local inc, suf = t:match("%$%s*([%d%.,]+)%s*(%a*)%s*/%s*[sS]")
        if inc and not d.income then d.income = U.parseNum((inc:gsub(",", "")), suf) end
        local r = rarityOf(t)
        if r and not d.rarity then d.rarity = r end
        local isData = low:find("kg", 1, true) or low:find("/s", 1, true) or t:find("%$") or (r and #t <= 16) or GENERIC_TEXT[low]
        if not isData and not nameCand and #t > 1 then nameCand = t:sub(1, 26) end
    end
    local lowAll = d.text:lower()
    for _, wd in ipairs(MutationWords) do
        if lowAll:find(wd, 1, true) or d.text:find(wd, 1, true) then d.mutation = wd; break end
    end
    d.name = nameCand or fallbackName or "Egg"
    return d
end

-- Тексты объекта: BillboardGui/SurfaceGui.TextLabel + ObjectText/ActionText вложенных ProximityPrompt
function W.holderTexts(holder, out)
    out = out or {}
    for _, x in ipairs(holder:GetDescendants()) do
        if x:IsA("TextLabel") and x.Text ~= "" and (x:FindFirstAncestorWhichIsA("BillboardGui") or x:FindFirstAncestorWhichIsA("SurfaceGui")) then
            out[#out + 1] = cleanText(x.Text)
        elseif x:IsA("ProximityPrompt") then
            if x.ObjectText ~= "" then out[#out + 1] = cleanText(x.ObjectText) end
            if x.ActionText ~= "" then out[#out + 1] = cleanText(x.ActionText) end
        end
    end
    return out
end
function W.parseHolder(holder)
    return W.parseTexts(holder and W.holderTexts(holder) or {}, holder and holder.Name or nil)
end

function W.hRoot() return workspace:FindFirstChild("HalloweenDimension") end
function W.guardAreas() return U.dig(workspace, "World.Areas.GuardAreas") end

-- Все NestModel из GuardAreas (с границами и биомом)
function W.refreshNests()
    local list = {}
    local ga = W.guardAreas()
    if ga then
        for _, d in ipairs(ga:GetDescendants()) do
            if d.Name == "NestModel" and (d:IsA("Model") or d:IsA("BasePart")) then
                local cf, size = U.boxOf(d)
                local pos = U.posOf(d)
                if pos then
                    local biome, cur = "?", d
                    while cur and cur.Parent do
                        if cur.Parent == ga then biome = cur.Name; break end
                        cur = cur.Parent
                    end
                    list[#list + 1] = { model = d, pos = pos, cf = cf or CFrame.new(pos), size = size or Vector3.new(4, 4, 4), biome = biome }
                end
            end
        end
    end
    State.nests, State.nestAt = list, os.clock()
end
-- Расстояние от точки до границ модели (не до центра)
function W.boxDist(cf, size, pos)
    local rel = cf:PointToObjectSpace(pos)
    return Vector3.new(math.max(math.abs(rel.X) - size.X / 2, 0), math.max(math.abs(rel.Y) - size.Y / 2, 0),
        math.max(math.abs(rel.Z) - size.Z / 2, 0)).Magnitude
end
function W.nearestIn(list, pos)
    local best, bd
    for _, n in ipairs(list) do
        local d = W.boxDist(n.cf, n.size, pos)
        if not bd or d < bd then best, bd = n, d end
    end
    return best, bd
end
function W.biomeFolder(name)
    local ga = W.guardAreas()
    if not ga then return nil end
    local d = ga:FindFirstChild(name)
    if d then return d end
    local key = U.norm(name)
    for _, c in ipairs(ga:GetChildren()) do if U.norm(c.Name) == key then return c end end
end
-- Каноническое имя биома (как в списке Biomes) по имени папки GuardAreas
function W.canonBiome(name)
    if not name then return nil end
    if name == "Halloween" then return name end
    local key = U.norm(name)
    for _, b in ipairs(Biomes) do if U.norm(b.name) == key then return b.name end end
    return nil
end
-- Биом по координатам: ближайший NestModel, запасной вариант — ближайшая папка GuardAreas.[Биом]
function W.biomeAt(pos)
    local n = W.nearestIn(State.nests, pos)
    if n then return W.canonBiome(n.biome) or n.biome end
    local ga = W.guardAreas()
    if not ga then return nil end
    if not State.biomeBoxes or os.clock() - State.biomeBoxAt > 20 then
        local t = {}
        for _, c in ipairs(ga:GetChildren()) do
            local cf, size = U.boxOf(c)
            if cf then t[#t + 1] = { name = c.Name, cf = cf, size = size } end
        end
        State.biomeBoxes, State.biomeBoxAt = t, os.clock()
    end
    local best, bd
    for _, b in ipairs(State.biomeBoxes) do
        local d = W.boxDist(b.cf, b.size, pos)
        if not bd or d < bd then best, bd = b, d end
    end
    return best and (W.canonBiome(best.name) or best.name) or nil
end
-- Имя яйца: 1) ProximityPrompt.ObjectText  2) имя MeshPart внутри SmartPromptPart. Иначе — nil.
local GENERIC_NAMES = { [""] = true, egg = true, steal = true, part = true, meshpart = true, handle = true, union = true,
    smartpromptpart = true, mesh = true, model = true }
function W.eggNameOf(part, pr)
    local ot = cleanText(pr.ObjectText or "")
    if ot ~= "" and not GENERIC_NAMES[ot:lower()] then return ot, "ObjectText" end
    for _, d in ipairs(part:GetDescendants()) do
        if d:IsA("MeshPart") and not GENERIC_NAMES[d.Name:lower()] then return d.Name, "MeshPart внутри SmartPromptPart" end
    end
    return nil, nil
end
-- Редкость только из РЕАЛЬНЫХ источников: атрибуты яйца и слова в его собственном имени (не из имён биомов/предков!)
function W.attrRarity(part, pr, holder, eggName)
    local function fromAttrs(inst)
        if not inst then return nil end
        for _, k in ipairs({ "Rarity", "EggRarity", "Tier", "RarityName" }) do
            local v = inst:GetAttribute(k)
            if v ~= nil then
                local r = rarityOf(tostring(v))
                if r then return r end
            end
        end
    end
    for _, inst in ipairs({ part, pr, holder }) do
        local r = fromAttrs(inst)
        if r then return r end
    end
    for _, d in ipairs(part:GetDescendants()) do
        local r = fromAttrs(d)
        if r then return r end
    end
    if eggName then return rarityOf(eggName) end
    return nil
end
-- Индекс таблицы EggStats по ИМЕНИ питомца (имена с «/» разбиваются)
local statIndex
function W.statsByName(name)
    if not statIndex then
        statIndex = {}
        for biome, list in pairs(EggStats) do
            for _, e in ipairs(list) do
                if e.name then
                    for piece in (e.name .. "/"):gmatch("([^/]+)/") do
                        local k = U.norm(piece)
                        if k ~= "" then statIndex[k] = { e = e, biome = biome } end
                    end
                end
            end
        end
    end
    local key = U.norm(name)
    local hit = statIndex[key]
    if not hit then
        local bl
        for k, v in pairs(statIndex) do
            if key:find(k, 1, true) and (not bl or #k > bl) then hit, bl = v, #k end
        end
    end
    if not hit then return nil end
    local e = hit.e
    return { name = e.name, rarity = e.rarity, weight = e.weight, income = e.income, key = hit.biome }
end
-- Forest: диапазон дохода по редкости (только если биом Forest подтверждён надёжно и редкость названа в имени)
function W.forestStats(rarity)
    for _, e in ipairs(EggStats["Forest"] or {}) do
        if e.rarity == rarity then
            return { rarity = rarity, income = (e.min + e.max) / 2, incomeText = U.fmt(e.min) .. "–" .. U.fmt(e.max), key = "Forest" }
        end
    end
    return nil
end

-- Модели HalloweenEgg (кэш на 3 c)
function W.halloweenEggs()
    if State.hCache and os.clock() - State.hCacheAt < 3 then return State.hCache end
    local out = {}
    local f = U.dig(workspace, "HalloweenDimension.WorldEggs")
    if f then
        for _, d in ipairs(f:GetDescendants()) do
            if d:IsA("Model") and (d:GetAttribute("PreparedSourceName") ~= nil or d.Name == "HalloweenEgg") then
                local cf, size = U.boxOf(d)
                local pos = U.posOf(d)
                if pos then out[#out + 1] = { model = d, pos = pos, cf = cf or CFrame.new(pos), size = size or Vector3.new(4, 4, 4) } end
            end
        end
    end
    State.hCache, State.hCacheAt = out, os.clock()
    return out
end
-- Зона Хэллоуина, где стоит игрок (Zone1/2/3/SafeZone) или nil
function W.hZoneAt()
    local zs, hrp = U.dig(workspace, "HalloweenDimension.Zones"), getHRP()
    if not zs or not hrp then return nil end
    local best, bd
    for _, n in ipairs({ "Zone1", "Zone2", "Zone3", "SafeZone" }) do
        local z = zs:FindFirstChild(n)
        local c, s = U.boxOf(z)
        if c then
            local rel = hrp.Position - c.Position
            local dx, dz = math.max(math.abs(rel.X) - s.X / 2, 0), math.max(math.abs(rel.Z) - s.Z / 2, 0)
            local d = math.sqrt(dx * dx + dz * dz)
            if d < 150 and math.abs(rel.Y) < 400 and (not bd or d < bd) then best, bd = n, d end
        end
    end
    return best
end

function W.bbPos(g)
    local a = g.Adornee
    if a then
        if a:IsA("BasePart") then return a.Position end
        if a:IsA("Attachment") then return a.WorldPosition end
        return U.posOf(a)
    end
    local p = g.Parent
    if p and p:IsA("BasePart") then return p.Position end
    if p and p:IsA("Attachment") then return p.WorldPosition end
    return p and U.posOf(p) or nil
end

-- Сканер: SmartPromptPart с ActionText = "Steal" по всему Workspace (+ HalloweenEgg).
-- Данные берутся из ближайшего NestModel / HalloweenEgg, запасной вариант — ближайшие BillboardGui.
function W.scan()
    if State.scanning then return State.eggs end
    State.scanning = true
    print("[DEBUG] Сканирую карту на яйца...")
    local t0 = os.clock()
    if os.clock() - State.nestAt > 10 then W.refreshNests() end
    local all = workspace:GetDescendants()
    local char = LP.Character
    local eggs, seen, bbs, cands = {}, {}, {}, {}
    local cnt = { parts = 0, prompts = 0, accepted = 0, garbage = 0, clicks = 0 }
    local hroot = W.hRoot()

    -- ---- вспомогательные функции фильтра ----
    -- 1) Гибкий текст кнопки: steal / красть / украсть / grab (без учёта регистра; для кириллицы сверяем корень «расть»/«РАСТЬ»)
    local function isStealText(t)
        if not t or t == "" then return false end
        local low = t:lower()
        return low:find("steal", 1, true) ~= nil or low:find("grab", 1, true) ~= nil
            or t:find("расть", 1, true) ~= nil or t:find("РАСТЬ", 1, true) ~= nil
    end
    -- 3) Мусор: Apply Mutation / Open / Buy / Sell / Talk / Enter
    local GARBAGE = { "apply mutation", "open", "buy", "sell", "talk", "enter" }
    local function isGarbage(a, o)
        local low = (a .. " " .. o):lower()
        for _, g in ipairs(GARBAGE) do
            if low:find(g, 1, true) then return true end
        end
        return false
    end
    -- 2) «Яичные» регионы: SmartPromptPart / AreaEggSlotsClient / NestModel в GuardAreas / WorldEggs (HalloweenEgg)
    local slots = workspace:FindFirstChild("AreaEggSlotsClient")
    local gAreas = W.guardAreas()
    local wEggs = U.dig(workspace, "HalloweenDimension.WorldEggs")
    local function regionOf(d)
        if d.Parent and d.Parent.Name == "SmartPromptPart" or d:FindFirstAncestor("SmartPromptPart") then return "SmartPromptPart" end
        if slots and d:IsDescendantOf(slots) then return "AreaEggSlotsClient" end
        if wEggs and d:IsDescendantOf(wEggs) then return "WorldEggs/HalloweenEgg" end
        if gAreas and d:IsDescendantOf(gAreas) then
            local cur = d.Parent
            for _ = 1, 10 do
                if not cur or cur == gAreas then break end
                if cur.Name == "NestModel" then return "GuardAreas/NestModel" end
                cur = cur.Parent
            end
        end
        return nil
    end
    -- BasePart, к которому привязан prompt (Part / Attachment / Model)
    local function promptPart(pr)
        local par = pr.Parent
        if not par then return nil end
        if par:IsA("BasePart") then return par end
        if par:IsA("Attachment") and par.Parent and par.Parent:IsA("BasePart") then return par.Parent end
        if par:IsA("Model") then return par.PrimaryPart or par:FindFirstChildWhichIsA("BasePart", true) end
        return par:FindFirstChildWhichIsA("BasePart", true)
    end

    for i = 1, #all do
        local d = all[i]
        if i % 4000 == 0 then task.wait() end                               -- не вешаем кадр
        local isPrompt = d:IsA("ProximityPrompt")
        local isClick = d:IsA("ClickDetector")
        if d.Name == "SmartPromptPart" and d:IsA("BasePart") then cnt.parts += 1 end
        if isPrompt or isClick then
            local parName = d.Parent and d.Parent.Name or "?"
            -- ОТЛАДКА: каждый найденный ProximityPrompt / ClickDetector — в консоль (один раз на объект)
            if not State.promptLogged[d] then
                State.promptLogged[d] = true
                if isPrompt then
                    print("[DEBUG] Найден промпт:", parName, "| ActionText:", d.ActionText, "| ObjectText:", d.ObjectText,
                        "| Enabled:", d.Enabled, "| Путь:", d:GetFullName())
                else
                    print("[DEBUG] Найден ClickDetector:", parName, "| Путь:", d:GetFullName())
                end
            end
            if isClick then cnt.clicks += 1 end
            if isPrompt and not (char and d:IsDescendantOf(char)) and not U.inOtherChar(d) then
                cnt.prompts += 1
                local act, obj = d.ActionText or "", d.ObjectText or ""
                if isGarbage(act, obj) then
                    cnt.garbage += 1
                elseif d.Enabled then
                    local byText = isStealText(act) or isStealText(obj)
                    local region = regionOf(d)
                    if byText or region then
                        local part = promptPart(d)
                        if part then
                            cnt.accepted += 1
                            cands[#cands + 1] = { part = part, prompt = d,
                                by = (byText and "текст кнопки" or "регион") .. (region and (" · " .. region) or "") }
                        end
                    end
                end
            end
        elseif d:IsA("BillboardGui") then
            bbs[#bbs + 1] = d
        end
    end
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then
        for _, d in ipairs(pg:GetDescendants()) do
            if d:IsA("BillboardGui") and d.Adornee then bbs[#bbs + 1] = d end
        end
    end

    local bbCache = {}
    local function bbp(g)
        local p = bbCache[g]
        if p == nil then p = W.bbPos(g) or false; bbCache[g] = p end
        return p or nil
    end
    local function build(part, pr, holderHint, by)
        if seen[pr] then return end
        seen[pr] = true
        local pos = part.Position
        local etype = (hroot and part:IsDescendantOf(hroot)) and "halloween" or "normal"
        local holder, biome, nd, how
        if etype == "halloween" then
            holder = holderHint
            if holder then how = "HalloweenEgg с prompt" end
            if not holder then
                local cur = part
                for _ = 1, 8 do
                    if not cur or cur == workspace then break end
                    if cur:IsA("Model") and (cur:GetAttribute("PreparedSourceName") ~= nil or cur.Name == "HalloweenEgg") then holder = cur; how = "предок HalloweenEgg"; break end
                    cur = cur.Parent
                end
            end
            if not holder then
                local n, dist = W.nearestIn(W.halloweenEggs(), pos)
                nd = dist
                if n and dist <= Config.NestFarRadius then
                    holder = n.model
                    how = ("ближайший HalloweenEgg (%.1f studs)"):format(dist)
                end
            end
            biome = "Halloween"
        else
            local cur = part
            for _ = 1, 10 do
                if not cur or cur == workspace then break end
                if cur.Name == "NestModel" then holder = cur; how = "предок NestModel"; break end
                cur = cur.Parent
            end
            if holder then
                local ga = W.guardAreas()
                local c2 = holder
                while ga and c2 and c2.Parent do
                    if c2.Parent == ga then biome = c2.Name; break end
                    c2 = c2.Parent
                end
            else
                local n, dist = W.nearestIn(State.nests, pos)
                nd = dist
                if n and dist <= Config.NestFarRadius then
                    holder, biome = n.model, n.biome
                    how = ("ближайший NestModel (%.1f studs%s)"):format(dist, dist > Config.NestRadius and ", дальше нормы" or "")
                end
            end
        end
        local texts = holder and W.holderTexts(holder) or {}
        local data = W.parseTexts(texts, holder and holder.Name or nil)
        local source = holder and (how or "holder") or "holder не найден"
        if not (data.weight or data.income or data.rarity) then
            local near = {}
            for _, g in ipairs(bbs) do
                local gp = bbp(g)
                if gp then
                    local dd = (gp - pos).Magnitude
                    if dd <= Config.BillboardRadius then near[#near + 1] = { g = g, d = dd } end
                end
            end
            table.sort(near, function(a, b) return a.d < b.d end)
            local t2 = {}
            for i = 1, math.min(3, #near) do
                for _, x in ipairs(near[i].g:GetDescendants()) do
                    if x:IsA("TextLabel") and x.Text ~= "" then t2[#t2 + 1] = cleanText(x.Text) end
                end
            end
            local d2 = W.parseTexts(t2, data.name)
            if d2.weight or d2.income or d2.rarity then data = d2; source = "BillboardGui рядом" end
            if not (data.weight or data.income or data.rarity) and not State.dataWarned[pr] then
                State.dataWarned[pr] = true
                dbg("ДАННЫЕ НЕ ПРОЧИТАНЫ:", part:GetFullName(), "| holder:", holder and holder:GetFullName() or "не найден",
                    "| до ближайшего гнезда:", nd and math.floor(nd) or "?", "studs | текстов в holder:", #texts, "| BillboardGui рядом:", #near)
                for i = 1, math.min(5, #texts) do dbg("   текст holder:", texts[i]) end
            end
        end
        -- биом: только из надёжных источников (предок NestModel / ближайшее гнездо ≤ NestFarRadius) — без «значения по умолчанию»
        if etype == "halloween" then biome = "Halloween" else biome = W.canonBiome(biome) or "?" end
        local trusted = etype == "normal" and holder ~= nil and (how == "предок NestModel" or (nd ~= nil and nd <= Config.NestRadius))
        -- имя яйца: ProximityPrompt.ObjectText → MeshPart внутри SmartPromptPart
        local eggName, nameSrc = W.eggNameOf(part, pr)
        local st = eggName and W.statsByName(eggName) or nil
        if not st and eggName and trusted and biome == "Forest" then
            local fr = rarityOf(eggName)
            if fr then st = W.forestStats(fr) end
        end
        local hasRealText = (data.weight or data.income or data.rarity) and true or false
        data.name = (st and st.name) or eggName or (hasRealText and data.name) or "Неизвестное яйцо"
        if st then
            if not data.weight then data.weight = st.weight end
            if not data.income then data.income = st.income; data.incomeText = st.incomeText end
            data.rarity = data.rarity or st.rarity
            source = source .. " + EggStats[" .. tostring(st.key) .. "]"
        else
            data.income = data.income or 0                                   -- лучше 0, чем ложь
            data.rarity = data.rarity or W.attrRarity(part, pr, holder, eggName) or "?"
        end
        if not State.nameDbg[pr] then
            State.nameDbg[pr] = true
            dbg("ЯЙЦО:", part:GetFullName(), "| ObjectText =", pr.ObjectText, "| имя =", eggName or "НЕ НАЙДЕНО", "(" .. tostring(nameSrc or "-") .. ")",
                "| биом =", biome, trusted and "(надёжно)" or "(не подтверждён)", "| в таблице:", st and "да" or "нет",
                "| доход =", tostring(data.income), "| редкость =", tostring(data.rarity))
        end
        eggs[#eggs + 1] = { key = pr, part = part, prompt = pr, pos = pos, etype = etype, holder = holder, biome = biome or "?",
            data = data, source = source .. (by and (" · принят: " .. by) or "") }
    end

    for _, c in ipairs(cands) do build(c.part, c.prompt, nil, c.by) end
    -- Хэллоуин: модели HalloweenEgg (атрибут PreparedSourceName) — любые не-мусорные prompt внутри них
    for _, h in ipairs(W.halloweenEggs()) do
        for _, pr in ipairs(h.model:GetDescendants()) do
            if pr:IsA("ProximityPrompt") and not seen[pr] and pr.Enabled and not isGarbage(pr.ActionText or "", pr.ObjectText or "") then
                local part = promptPart(pr)
                if part then build(part, pr, h.model, "HalloweenEgg") end
            end
        end
    end

    State.eggs, State.scanAt = eggs, os.clock()
    print("[DEBUG] Найдено потенциальных яиц:", #eggs)
    if #eggs == 0 then print("[DEBUG] Яиц нет! Жду появления / респавна.") end
    local summary = ("SmartPromptPart=%d промптов=%d принято=%d мусор(Apply Mutation/Open/Buy/Sell/Talk/Enter)=%d ClickDetector=%d яиц=%d"):format(
        cnt.parts, cnt.prompts, cnt.accepted, cnt.garbage, cnt.clicks, #eggs)
    if #eggs ~= State.lastCount or summary ~= State.lastSummary then
        dbg(("Скан: %s | NestModel: %d | BillboardGui: %d | объектов в мире: %d | %.2f c"):format(summary, #State.nests, #bbs, #all, os.clock() - t0))
        for i, e in ipairs(eggs) do
            if i > 8 then break end
            dbg(("  [%s/%s] %s | вес=%s доход=%s редкость=%s | данные: %s"):format(e.etype, e.biome, e.part:GetFullName():gsub("^Workspace%.", ""),
                U.fmt(e.data.weight), U.fmt(e.data.income), e.data.rarity or "Неизвестно", e.source))
        end
        State.lastCount, State.lastSummary = #eggs, summary
    end
    State.scanning = false
    return eggs
end

function W.safeZone(etype)
    local tz = Config.TargetZone
    if etype == "halloween" or tz == "Хэллоуин" then
        return U.dig(workspace, "HalloweenDimension.Zones.SafeZone"), "HalloweenDimension.Zones.SafeZone"
    end
    if tz ~= "All" and tz ~= "Auto" and tz ~= "Forest" then
        local f = W.biomeFolder(tz)
        if f then
            for _, d in ipairs(f:GetDescendants()) do
                if (d:IsA("BasePart") or d:IsA("Model")) and d.Name:lower():find("safe", 1, true) then
                    return d, (d:GetFullName():gsub("^Workspace%.", ""))
                end
            end
        end
        dbg("TargetZone =", tz, "→ SafeZone внутри биома не найдена, беру стандартную базу")
    end
    return U.dig(workspace, "World.Areas.EggCarryBounds.SafeZone"), "World.Areas.EggCarryBounds.SafeZone"
end

-- ============================== M: ДВИЖЕНИЕ =============================
-- stepTo: MoveTo + MoveToFinished; застрял (скорость < 2 за 1.5 c) → прыжок, потом обход вбок.
-- Возвращает: reached | stuck | teleported | dead | abort | timeout
function M.stepTo(target, timeout, cond, early, reach)
    reach = reach or 3.5
    local hum, hrp = getHum(), getHRP()
    if not hum or not hrp then return "dead" end
    hum:MoveTo(target)
    local finished, reachedFlag = false, false
    local conn = hum.MoveToFinished:Connect(function(r) finished = true; reachedFlag = r end)
    local t0, samples, stage, prev = os.clock(), {}, 0, hrp.Position
    local result = "timeout"
    while os.clock() - t0 < timeout and cond() do
        task.wait(0.1)
        hrp = getHRP()
        if not hrp or not alive() then result = "dead"; break end
        if (hrp.Position - prev).Magnitude > Config.PortalJump then
            dbg("Позиция скакнула на", math.floor((hrp.Position - prev).Magnitude), "studs — портал/телепорт")
            result = "teleported"; break
        end
        prev = hrp.Position
        if hdist(hrp.Position, target) <= reach then result = "reached"; break end
        if early and early() then result = "reached"; break end
        if finished then
            result = reachedFlag and "reached" or "stuck"
            if not reachedFlag then dbg("MoveToFinished(false) — цель не достигнута") end
            break
        end
        samples[#samples + 1] = { os.clock(), hrp.Position }
        while #samples > 1 and os.clock() - samples[1][1] > 1.7 do table.remove(samples, 1) end
        local first = samples[1]
        local dt = os.clock() - first[1]
        if dt >= 1.5 then
            local spd = hdist(hrp.Position, first[2]) / dt
            if spd < 2 then
                stage += 1
                samples = {}
                if stage == 1 then
                    dbg(("Застрял (скорость %.1f < 2 за 1.5 c) → прыжок"):format(spd))
                    hum.Jump = true
                else
                    dbg("Всё ещё стоит → обход вбок")
                    hum:MoveTo(hrp.Position + hrp.CFrame.RightVector * ((stage % 2 == 0) and 6 or -6))
                    task.wait(0.7)
                    hum.Jump = true
                    hum:MoveTo(target)
                    if stage >= 4 then result = "stuck"; break end
                end
            else
                stage = 0
            end
        end
    end
    conn:Disconnect()
    if not cond() then return "abort" end
    return result
end

function M.followPath(target, cond, early, reach)
    local hrp = getHRP()
    local path = Svc.PathfindingService:CreatePath({ AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true, AgentCanClimb = true, WaypointSpacing = 6 })
    local ok, err = pcall(function() path:ComputeAsync(hrp.Position, target) end)
    if not ok or path.Status ~= Enum.PathStatus.Success then
        dbg("Pathfinding: путь не построен, статус =", ok and tostring(path.Status) or tostring(err))
        return "nopath"
    end
    local wps = path:GetWaypoints()
    dbg("Pathfinding: точек в пути =", #wps)
    for i = 2, #wps do
        if not cond() then return "abort" end
        if early and early() then return "reached" end
        if wps[i].Action == Enum.PathWaypointAction.Jump then local h = getHum(); if h then h.Jump = true end end
        local r = M.stepTo(wps[i].Position, 6, cond, early, i == #wps and reach or 3.5)
        if r == "stuck" then dbg("Застрял на точке", i, "из", #wps, "→ пересчёт пути"); return "stuck" end
        if r == "teleported" or r == "dead" or r == "abort" then return r end
    end
    return "reached"
end

-- Ходьба: близко → Pathfinding + MoveTo; далеко → Noclip + MoveTo; скачок дистанции 500+ → пересчёт
function M.walkTo(target, stop, cond, early)
    cond = cond or function() return IH.Alive end
    stop = stop or 4
    local reach = math.min(3.5, math.max(1.0, stop - 0.5))
    local t0, lastDist = os.clock(), nil
    while cond() and os.clock() - t0 < 300 do
        local hrp = getHRP()
        if not hrp or not alive() then dbg("Персонаж мёртв/недоступен"); State.noclip = false; return false end
        local dist = hdist(hrp.Position, target)
        if dist <= stop or (early and early()) then
            dbg(("Дошёл (осталось %.0f studs)"):format(dist)); State.noclip = false; return true
        end
        if lastDist and dist - lastDist > Config.PortalJump then
            dbg(("Дистанция выросла на %.0f studs → портал, пересчитываю маршрут"):format(dist - lastDist))
        end
        lastDist = dist
        local r
        if dist > Config.FarDistance then
            dbg(("До цели %.0f studs (>%d) → NOCLIP + MoveTo"):format(dist, Config.FarDistance))
            State.noclip = true
            r = M.stepTo(target, 10, cond, early, reach)
        else
            State.noclip = false
            dbg(("До цели %.0f studs → Pathfinding + MoveTo"):format(dist))
            r = M.followPath(target, cond, early, reach)
            if r == "nopath" then r = M.stepTo(target, 8, cond, early, reach) end
        end
        if r == "teleported" then lastDist = nil
        elseif r == "abort" or r == "dead" then State.noclip = false; return false end
    end
    State.noclip = false
    return false
end

-- Полёт к цели: AlignPosition + AlignOrientation (MaxForce = 1e9, Responsiveness = 100)
function M.flyTo(target, stop, cond, early)
    cond = cond or function() return IH.Alive end
    stop = stop or 3
    local hrp = getHRP()
    if not hrp then return false end
    local a0 = Instance.new("Attachment"); a0.Parent = hrp
    local ap = Instance.new("AlignPosition")
    ap.Attachment0 = a0; ap.Mode = Enum.PositionAlignmentMode.OneAttachment; ap.MaxForce = 1e9
    ap.Responsiveness = 100; ap.MaxVelocity = Config.FlySpeed; ap.RigidityEnabled = false; ap.Position = target; ap.Parent = hrp
    local ao = Instance.new("AlignOrientation")
    ao.Attachment0 = a0; ao.Mode = Enum.OrientationAlignmentMode.OneAttachment; ao.MaxTorque = 1e9
    ao.Responsiveness = 100; ao.CFrame = hrp.CFrame; ao.Parent = hrp
    State.noclip, State.moving = true, true
    dbg(("Полёт к цели: %.0f studs, скорость %d"):format((hrp.Position - target).Magnitude, Config.FlySpeed))
    local t0, prev, ok = os.clock(), hrp.Position, false
    local limit = (hrp.Position - target).Magnitude / math.max(Config.FlySpeed, 1) * 2 + 6
    while cond() and alive() and os.clock() - t0 < limit do
        task.wait(0.05)
        local h = getHRP()
        if not h then break end
        if (h.Position - prev).Magnitude > Config.PortalJump then
            dbg("Позиция скакнула (портал?) → пересчитываю полёт")
            ap.Position = target
        end
        prev = h.Position
        local dir = Vector3.new(target.X - h.Position.X, 0, target.Z - h.Position.Z)
        if dir.Magnitude > 1 then ao.CFrame = CFrame.lookAt(Vector3.zero, dir) end
        if (h.Position - target).Magnitude <= stop or (early and early()) then ok = true; break end
    end
    pcall(function() ap:Destroy(); ao:Destroy(); a0:Destroy() end)
    local h = getHRP()
    if h then pcall(function() h.AssemblyLinearVelocity = Vector3.zero end) end
    State.noclip, State.moving = false, false
    dbg("Полёт завершён:", ok and "долетел" or "не долетел")
    return ok
end

function M.moveTo(target, stop, cond, early)
    if Config.MoveMode == "Fly" then return M.flyTo(target, stop, cond, early) end
    return M.walkTo(target, stop, cond, early)
end

-- ============================== A: КРАЖА ================================
function A.speed()
    if Config.SpeedOverride > 0 then return Config.SpeedOverride end
    local best = State.baseWalk or 0
    pcall(function()
        local ls = LP:FindFirstChild("leaderstats")
        if ls then
            for _, v in ipairs(ls:GetChildren()) do
                if v:IsA("ValueBase") and v.Name:lower():find("speed") then
                    local n = U.parseNum(v.Value)
                    if n and n > best then best = n end
                end
            end
        end
        for _, k in ipairs({ "Speed", "WalkSpeed", "SpeedLevel" }) do
            local n = U.parseNum(LP:GetAttribute(k))
            if n and n > best then best = n end
        end
    end)
    return best
end

-- Подходящие яйца по режимам (Хэллоуин / биом / блэклист) и приоритет
function A.pick(eggs)
    local wantH = Config.HalloweenEggs or Config.StartBiome == "Хэллоуин"
    local speed = A.speed()
    local allowed
    if Config.StartBiome == "Auto" then
        allowed = {}
        for _, b in ipairs(Biomes) do if speed >= b.minSpeed * Config.SpeedMargin then allowed[b.name] = true end end
    end
    local hrp = getHRP()
    local best, bs
    for _, e in ipairs(eggs) do
        local bl = State.blacklist[e.part]
        local okType = (wantH and e.etype == "halloween") or (not wantH and e.etype == "normal")
        local okBiome = true
        if e.etype == "normal" then
            if Config.StartBiome == "Auto" then okBiome = (e.biome == "?") or allowed[e.biome] == true
            elseif Config.StartBiome ~= "All" and Config.StartBiome ~= "Хэллоуин" then okBiome = (e.biome == Config.StartBiome) end
        end
        if okType and okBiome and e.part.Parent and e.prompt.Parent and e.prompt.Enabled and not (bl and tick() < bl) then
            local d = e.data
            local s
            if Config.Priority == "Income" then s = d.income or 0
            elseif Config.Priority == "Rarity" then s = (RarityRank[d.rarity or ""] or 0) * 1e6 + (d.income or 0) / 1e9
            elseif Config.Priority == "Weight" then s = d.weight or 0
            else s = hrp and -(e.pos - hrp.Position).Magnitude or 0 end
            if not bs or s > bs then best, bs = e, s end
        end
    end
    return best
end

-- Был ли удар (здоровье упало / Ragdoll) после момента t
function A.hitSince(t) return State.hitAt ~= nil and State.hitAt >= t end

-- Защита от стража: отпрыгнуть назад и подождать, пока он успокоится
function A.backOff(e, why)
    dbg("ЗАЩИТА ОТ СТРАЖА:", why, "→ отпрыгиваю назад, жду", Config.BackOffTime, "с и пробую снова. На базу НЕ иду.")
    local hum, hrp = getHum(), getHRP()
    if hum and hrp then
        local dir = Vector3.new(hrp.Position.X - e.pos.X, 0, hrp.Position.Z - e.pos.Z)
        if dir.Magnitude < 0.5 then dir = -hrp.CFrame.LookVector end
        hum.Jump = true
        hum:MoveTo(hrp.Position + dir.Unit * 12)
    end
    task.wait(Config.BackOffTime)
    State.hitCount[e.part] = (State.hitCount[e.part] or 0) + 1
    if State.hitCount[e.part] >= 3 then
        dbg("Яйцо охраняется (3 удара подряд) → блэклист 30 сек")
        State.blacklist[e.part] = tick() + 30
        State.hitCount[e.part] = nil
    end
end

-- Кража. Возвращает: ok | fail | hit | abort
-- 1) prompt.Enabled и Parent  2) fireproximityprompt  3) ждём до 2 с
-- Успех: в Character есть объект «Egg» ИЛИ SmartPromptPart исчез ИЛИ prompt.Enabled == false
function A.steal(e, cond)
    local pr, part = e.prompt, e.part
    local hum = getHum()
    for attempt = 1, 2 do
        if not cond() or not alive() then return "abort" end
        if not (pr.Parent and pr.Enabled and part.Parent) then
            dbg("КРАЖА: prompt недоступен (Parent =", pr.Parent ~= nil, "| Enabled =", pr.Parent and pr.Enabled or "нет prompt", ")")
            return "fail"
        end
        local hrp = getHRP()
        local pp = part.Position
        local maxd = pr.MaxActivationDistance or 10
        local dist = hrp and (hrp.Position - pp).Magnitude or 0
        if dist > maxd - 1.5 then
            dbg(("Далеко от prompt (%.1f, активация до %.1f) — подхожу"):format(dist, maxd))
            M.walkTo(pp, math.max(2, maxd - 3), cond)
            if not cond() or not alive() then return "abort" end
        end
        local t0 = tick()
        pcall(function() pr.HoldDuration = 0; pr.RequiresLineOfSight = false end)
        if fireproximityprompt then
            dbg("Вызываю fireproximityprompt(prompt), попытка", attempt, "→", pr:GetFullName())
            local ok, err = pcall(fireproximityprompt, pr)
            dbg("fireproximityprompt результат:", ok, err)
        else
            dbg("fireproximityprompt недоступен → InputHoldBegin/End")
            pcall(function() pr:InputHoldBegin(); task.wait(0.2); pr:InputHoldEnd() end)
        end
        local success = false
        for _ = 1, 20 do                                                  -- ждём до 2 секунд
            task.wait(0.1)
            if U.isCarrying() or not part.Parent or not pr.Parent or not pr.Enabled then success = true; break end
            if A.hitSince(t0) then break end
        end
        dbg("Проверка кражи: Egg в Character =", U.isCarrying(), "| SmartPromptPart исчез =", not part.Parent,
            "| prompt.Enabled =", pr.Parent ~= nil and pr.Enabled or "нет prompt", "| удар =", A.hitSince(t0))
        if success then dbg("КРАЖА УДАЛАСЬ (попытка", attempt, ")"); return "ok" end
        if A.hitSince(t0) then return "hit" end
        if attempt < 2 then
            dbg("Не удалось → шаг назад на 2 studs и повтор")
            local h2 = getHRP()
            if h2 and hum then
                local dir = Vector3.new(h2.Position.X - pp.X, 0, h2.Position.Z - pp.Z)
                if dir.Magnitude < 0.5 then dir = -h2.CFrame.LookVector end
                hum:MoveTo(h2.Position + dir.Unit * 2)
                task.wait(0.8)
            end
        end
    end
    return "fail"
end

-- ТП по CFrame: пока dist > stop — прыжки по 50 studs каждые 0.1 c; на время возврата WalkSpeed = 500 и Noclip = true
function A.tpTo(target, stop, cond)
    cond = cond or function() return IH.Alive end
    State.noclip, State.returnSpeed = true, 500
    local rollbacks, ok = 0, false
    while cond() and alive() do
        local hrp = getHRP()
        local delta = target - hrp.Position
        local dist = delta.Magnitude
        if dist <= stop then ok = true; break end
        local newPos = hrp.Position + delta.Unit * math.min(dist, 50)
        hrp.CFrame = CFrame.new(newPos) * (hrp.CFrame - hrp.CFrame.Position)
        task.wait(0.1)
        local h2 = getHRP()
        if h2 and (h2.Position - newPos).Magnitude > 25 then
            rollbacks += 1
            dbg("ТП: позиция откатилась (", rollbacks, "из 6)")
            if rollbacks >= 6 then break end
        end
    end
    local h = getHRP()
    if h then pcall(function() h.AssemblyLinearVelocity = Vector3.zero end) end
    State.noclip, State.returnSpeed = false, nil
    if not ok and rollbacks >= 6 then
        dbg("ТП: слишком много откатов → дальше обычной ходьбой")
        return M.walkTo(target, math.max(stop, 6), cond)
    end
    return ok
end

-- Возврат на базу сразу после кражи: мгновенный ТП (а не MoveTo)
function A.deliver(etype, cond)
    local zone, path = W.safeZone(etype)
    if not zone then dbg("БАЗА НЕ НАЙДЕНА: Workspace." .. path); return false end
    local cf, size = U.boxOf(zone)
    if not cf then dbg("Не удалось получить размеры базы"); return false end
    local top = cf.Position.Y + size.Y / 2
    local target = Vector3.new(cf.Position.X, U.groundAt(cf.Position.X, cf.Position.Z, top), cf.Position.Z)
    dbg("ТП на базу:", "Workspace." .. path, "| центр:", math.floor(target.X) .. ", " .. math.floor(target.Z))
    local hrp0 = getHRP()
    if hrp0 and target.Y < -100 and hrp0.Position.Y > 0 then
        dbg("База в измерении (Y < -100), а я в обычном мире → через портал")
        if not A.enterPortal(cond) then return false end
    end
    local ok = A.tpTo(target, 20, cond)
    local hrp = getHRP()
    if ok and hrp then hrp.CFrame = CFrame.new(target) * (hrp.CFrame - hrp.CFrame.Position) end      -- финальный точный ТП
    task.wait(0.2)
    dbg("Доставка:", ok and "на базе" or "не долетел", "| внутри SafeZone =", U.insideBox(zone, 2), "| несу яйцо =", U.isCarrying())
    task.wait(0.6)
    return ok
end

-- Хэллоуин: вход по зашитому пути Workspace.World.Build.EnchantedTreeInterior.Markers.EnterTrigger (ActionText "Enter")
function A.inDimension()
    local hrp = getHRP()
    return hrp ~= nil and (W.hZoneAt() ~= nil or hrp.Position.Y < -100)
end
-- Цель в измерении (Y < -100), а я в обычном мире (Y > 0) → сначала портал
function A.needPortal(e)
    local hrp = getHRP()
    if not hrp or A.inDimension() then return false end
    return hrp.Position.Y > 0 and (e.pos.Y < -100 or (e.pos - hrp.Position).Magnitude > 400)
end
function A.portalPrompt()
    local trig = U.dig(workspace, "World.Build.EnchantedTreeInterior.Markers.EnterTrigger")
    local function enterIn(root)
        local any
        local list = root:IsA("ProximityPrompt") and { root } or root:GetDescendants()
        for _, d in ipairs(list) do
            if d:IsA("ProximityPrompt") then
                if (d.ActionText or ""):lower():gsub("%s+", "") == "enter" then return d end
                any = any or d
            end
        end
        return any
    end
    if trig then
        local pr = enterIn(trig)
        if pr then return pr end
    end
    local markers = U.dig(workspace, "World.Build.EnchantedTreeInterior.Markers")
    if markers then
        for _, d in ipairs(markers:GetDescendants()) do
            if d:IsA("ProximityPrompt") and (d.ActionText or ""):lower():find("enter", 1, true) then return d end
        end
    end
    return nil
end
-- Запасной поиск по именам Portal / Whirlpool (если зашитый путь не найден)
function A.findPortal()
    if State.portalCache and State.portalCache.Parent and os.clock() - State.portalAt < 10 then return State.portalCache end
    local hroot, hrp = W.hRoot(), getHRP()
    local best, bd
    for _, d in ipairs(workspace:GetDescendants()) do
        if (d:IsA("Model") or d:IsA("BasePart")) and U.matchAny(d.Name, { "portal", "whirlpool" }) and not (hroot and d:IsDescendantOf(hroot)) then
            local p = U.posOf(d)
            if p and hrp then
                local dd = (p - hrp.Position).Magnitude
                if not bd or dd < bd then best, bd = d, dd end
            end
        end
    end
    State.portalCache, State.portalAt = best, os.clock()
    return best
end
function A.enterPortal(cond)
    dbg("ХЭЛЛОУИН: яйцо в измерении, а я в обычном мире (Y > 0) → ТП к EnterTrigger, напрямую через карту не бегу")
    for attempt = 1, 3 do
        if not cond() or not alive() then return false end
        local pr = A.portalPrompt()
        local trig = U.dig(workspace, "World.Build.EnchantedTreeInterior.Markers.EnterTrigger")
        local part, p
        if pr and pr.Parent and pr.Parent:IsA("BasePart") then part = pr.Parent end
        if not part and trig then part = trig:IsA("BasePart") and trig or trig:FindFirstChildWhichIsA("BasePart", true) end
        p = part and part.Position or (trig and U.posOf(trig))
        if not p then
            local portal = A.findPortal()                                         -- запасной поиск Portal / Whirlpool
            if not portal then dbg("ХЭЛЛОУИН: EnterTrigger / Portal / Whirlpool не найдены"); return false end
            p = U.posOf(portal)
            part = portal:IsA("BasePart") and portal or portal:FindFirstChildWhichIsA("BasePart", true)
            pr = pr or portal:FindFirstChildWhichIsA("ProximityPrompt", true)
        end
        if not p then return false end
        dbg("ХЭЛЛОУИН: попытка", attempt, "| prompt:", pr and pr:GetFullName() or "нет", "| ActionText =", pr and pr.ActionText or "-")
        local near = p + Vector3.new(0, 3, 0)
        A.tpTo(near, 3, cond)                                                      -- ТП вплотную к триггеру
        local h0 = getHRP()
        if h0 then h0.CFrame = CFrame.new(near) * (h0.CFrame - h0.CFrame.Position) end
        task.wait(0.4)
        local start = h0 and h0.Position or near
        if pr and pr.Parent and pr.Enabled then
            pcall(function() pr.HoldDuration = 0; pr.RequiresLineOfSight = false end)
            if fireproximityprompt then
                dbg("ХЭЛЛОУИН: fireproximityprompt(Enter)")
                pcall(fireproximityprompt, pr)
            else
                A.usePrompt(pr)
            end
        else
            dbg("ХЭЛЛОУИН: prompt недоступен (нет / выключен)")
        end
        task.wait(2)                                                               -- ждём 2 секунды
        local h = getHRP()
        if h and h.Position.Y > -100 then
            dbg("ХЭЛЛОУИН: Y =", math.floor(h.Position.Y), "> -100 → пробую firetouchinterest")
            if part and part:IsA("BasePart") and firetouchinterest then
                pcall(function() firetouchinterest(h, part, 0); task.wait(0.1); firetouchinterest(h, part, 1) end)
            end
            task.wait(1.5)
            h = getHRP()
        end
        if h and (h.Position.Y < -100 or W.hZoneAt() or (h.Position - start).Magnitude > 300) then
            dbg("ХЭЛЛОУИН: вошёл (Y =", math.floor(h.Position.Y), ") → теперь бегу к яйцу")
            task.wait(1)
            return true
        end
        dbg("ХЭЛЛОУИН: вход не сработал")
    end
    return false
end
-- Возврат из Train-ивента: prompt "Return to Halloween" в Workspace.TrainEventAssets.Map.EventMarkers
function A.inTrainEvent()
    local m = U.dig(workspace, "TrainEventAssets.Map")
    return m ~= nil and U.insideBox(m, 40)
end
function A.returnToHalloween(cond)
    cond = cond or function() return IH.Alive end
    local root = U.dig(workspace, "TrainEventAssets.Map.EventMarkers")
    if not root then dbg("Return to Halloween: TrainEventAssets.Map.EventMarkers не найден"); return false end
    for _, d in ipairs(root:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled then
            local txt = ((d.ActionText or "") .. " " .. (d.ObjectText or "")):lower()
            if txt:find("return to halloween", 1, true) then
                local p = d.Parent and U.posOf(d.Parent)
                dbg("Return to Halloween: prompt", d:GetFullName())
                if p then M.moveTo(p, 4, cond) end
                if fireproximityprompt then pcall(fireproximityprompt, d) else A.usePrompt(d) end
                task.wait(2)
                return true
            end
        end
    end
    dbg("Return to Halloween: prompt не найден в EventMarkers")
    return false
end

function A.cycle(my)
    State.cycleNo += 1
    print("[DEBUG] ===== Цикл " .. State.cycleNo .. " =====")
    local function cond() return IH.Alive and State.gen == my and (State.running or State.oneShot) end
    if not alive() then setStatus("жду персонажа"); task.wait(1); return end

    if State.expectCarry and U.isCarrying() then                       -- уже несём яйцо → сразу на базу
        setStatus("яйцо в руках → бегу на базу")
        State.farming = true
        if A.deliver(State.carryType or "normal", cond) then State.stats.eggs += 1; setStatus("сдано! всего: " .. State.stats.eggs) end
        State.expectCarry = false; State.farming = false
        return
    end
    State.expectCarry = false

    if os.clock() - State.scanAt > Config.ScanInterval * 2.5 then W.scan() end
    local e = State.forced
    State.forced = nil
    if e and e.part.Parent and e.prompt.Parent and e.prompt.Enabled then
        dbg("Цель выбрана вручную:", e.data.name)
    else
        e = A.pick(State.eggs)
    end
    if not e then
        print("[DEBUG] Яиц нет! Жду появления / респавна.")
        setStatus("подходящих яиц нет")
        task.wait(2)
        return
    end
    local d = e.data
    dbg("Выбрано:", e.part:GetFullName(), "| тип:", e.etype, "| биом:", e.biome, "| имя:", d.name, "| вес:", U.fmt(d.weight),
        "| доход:", U.fmt(d.income), "| редкость:", d.rarity or "Неизвестно", "| данные:", e.source)

    State.farming = true
    if e.etype == "halloween" and A.inTrainEvent() then
        setStatus("возвращаюсь в Хэллоуин (Train-ивент)")
        A.returnToHalloween(cond)
    end
    if e.etype == "halloween" and A.needPortal(e) then
        setStatus("иду в портал Хэллоуина")
        if not A.enterPortal(cond) then
            dbg("ХЭЛЛОУИН: попасть в измерение не удалось → блэклист 30 сек")
            State.blacklist[e.part] = tick() + 30
            State.farming = false
            return
        end
    end

    setStatus("иду к яйцу")
    print("[DEBUG] Иду к яйцу: ", e.part.Name, e.biome)
    local tStart = tick()
    local function condA() return cond() and not A.hitSince(tStart) end        -- удар по пути = отмена
    local arrived = M.moveTo(e.pos, 4, condA)
    if not cond() then State.farming = false; return end
    if A.hitSince(tStart) then State.farming = false; A.backOff(e, "ударили по пути к яйцу"); return end
    if not arrived then
        dbg("НЕ ДОШЁЛ до яйца → блэклист 30 сек")
        State.blacklist[e.part] = tick() + 30
        State.stats.fails += 1; State.farming = false
        return
    end

    setStatus("краду")
    local res = A.steal(e, cond)
    if res == "abort" then State.farming = false; return end
    if res == "hit" then
        State.farming = false
        State.stats.fails += 1
        A.backOff(e, "урон/Ragdoll во время кражи")
        return
    end
    if res ~= "ok" then
        dbg("КРАЖА НЕ УДАЛАСЬ после 2 попыток → блэклист 30 сек, переключаюсь на другое яйцо. На базу НЕ иду.")
        State.blacklist[e.part] = tick() + 30
        State.stats.fails += 1; State.farming = false
        return
    end
    State.hitCount[e.part] = nil
    State.expectCarry, State.carryType = true, e.etype

    setStatus("несу на базу")
    if A.deliver(e.etype, cond) then
        State.stats.eggs += 1
        setStatus("сдано! всего: " .. State.stats.eggs)
    else
        State.stats.fails += 1
        setStatus("не удалось донести")
    end
    State.expectCarry = false
    State.farming = false
end

function A.startFarm(once)
    State.gen += 1
    local my = State.gen
    if once then State.oneShot = true else State.running = true end
    dbg("СТАРТ", once and "(одно яйцо)" or "автокражи", "| режим:", Config.MoveMode, "| приоритет:", Config.Priority, "| биом:", Config.StartBiome)
    task.spawn(function()
        while IH.Alive and State.gen == my and (State.running or State.oneShot) do
            local ok, err = xpcall(A.cycle, tb, my)
            State.farming = false
            if not ok then dbg("ОШИБКА В ЦИКЛЕ:", err); task.wait(1) end
            if State.oneShot and not State.running then State.oneShot = false; break end
            task.wait(Config.Cooldown)
        end
        State.farming = false
        State.noclip = false
    end)
end
function A.stopFarm()
    State.running = false; State.oneShot = false; State.gen += 1; State.farming = false; State.noclip = false
    dbg("СТОП автокражи")
    local hum, hrp = getHum(), getHRP()
    if hum and hrp then hum:MoveTo(hrp.Position) end
end
function A.farmBusy() return State.running or State.oneShot or State.farming end

-- ============================== A: REMOTE / ПИТОМЦЫ / ПРОГРЕСС ==========
function A.scanRemotes()
    local names = { "claim", "speed" }
    for _, pats in pairs(P.Remotes) do for _, p in ipairs(pats) do names[#names + 1] = p end end
    local list = {}
    for _, d in ipairs(Svc.ReplicatedStorage:GetDescendants()) do
        if (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) and U.matchAny(d.Name, names) then list[#list + 1] = d end
    end
    State.Remotes = list
end
function A.getRemote(kind)
    local c = State.remoteCache[kind]
    if c and c.Parent then return c end
    local ov = Config.RemoteOverrides[kind]
    local r
    if ov and ov ~= "" then
        if ov:find("%.") then r = U.resolvePath(ov)
        else
            for _, d in ipairs(Svc.ReplicatedStorage:GetDescendants()) do
                if d.Name == ov and (d:IsA("RemoteEvent") or d:IsA("RemoteFunction")) then r = d; break end
            end
        end
    end
    if not r then
        for _, d in ipairs(State.Remotes) do
            if d.Parent and U.matchAny(d.Name, P.Remotes[kind] or {}) then r = d; break end
        end
    end
    State.remoteCache[kind] = r
    return r
end
function A.fire(r, ...)
    U.throttle()
    local args = table.pack(...)
    return pcall(function()
        if r:IsA("RemoteFunction") then return r:InvokeServer(table.unpack(args, 1, args.n)) end
        r:FireServer(table.unpack(args, 1, args.n))
    end)
end
function A.call(kind, variants)
    local r = A.getRemote(kind)
    if not r then return false end
    for _, args in ipairs(variants or { {} }) do A.fire(r, table.unpack(args)) end
    return true
end
function A.usePrompt(prompt)
    U.throttle()
    pcall(function() prompt.HoldDuration = 0; prompt.RequiresLineOfSight = false end)
    local ok = false
    if fireproximityprompt then ok = pcall(fireproximityprompt, prompt) end
    if not ok then pcall(function() prompt:InputHoldBegin(); task.wait(0.2); prompt:InputHoldEnd() end) end
end

function A.readPets()
    local conts = {}
    for _, root in ipairs({ LP, LP:FindFirstChild("PlayerGui") }) do
        if root then
            for _, d in ipairs(root:GetDescendants()) do
                if U.matchAny(d.Name, P.petContainers) and #d:GetChildren() > 0 and not (UI.gui and d:IsDescendantOf(UI.gui)) then conts[#conts + 1] = d end
            end
        end
    end
    local function attr(inst, ...)
        for _, k in ipairs({ ... }) do
            local v = inst:GetAttribute(k)
            if v ~= nil then return v end
            local c = inst:FindFirstChild(k)
            if c and c:IsA("ValueBase") then return c.Value end
        end
    end
    local byKey, order = {}, {}
    for _, cont in ipairs(conts) do
        for _, c in ipairs(cont:GetChildren()) do
            if not c.ClassName:find("^UI") then
                local name = tostring(c:GetAttribute("PetName") or c.Name)
                local clean = name:gsub("[_%s]*%d+$", "")
                local mut = attr(c, "Mutation", "Mutations", "Mutated")
                local mutated = mut ~= nil and mut ~= false and mut ~= "" and mut ~= "None" and mut ~= 0
                if not mutated then
                    local l = name:lower()
                    for _, w in ipairs(MutationWords) do if l:find(w, 1, true) then mutated = true; break end end
                end
                local equipped = (attr(c, "Equipped", "IsEquipped") == true) or U.matchAny(cont.Name, { "equipped" })
                local rarity = attr(c, "Rarity") or rarityOf(name) or "?"
                local income = U.parseNum(attr(c, "Income", "IncomePerSecond", "Cost")) or KnownPets[name] or KnownPets[clean]
                local count = (c:IsA("NumberValue") or c:IsA("IntValue")) and math.max(1, c.Value) or 1
                local key = c.Name .. "|" .. tostring(c:GetAttribute("Id") or "")
                if byKey[key] then byKey[key].count += count
                else
                    byKey[key] = { name = name, id = c:GetAttribute("Id") or c.Name, inst = c, rarity = tostring(rarity), income = income,
                        count = count, mutated = mutated, equipped = equipped }
                    order[#order + 1] = byKey[key]
                    if #order >= 400 then return order end
                end
            end
        end
    end
    return order
end

local argBuilders = { function(it) return { it.id } end, function(it) return { it.name } end, function(it) return { it.inst } end }
function A.itemAction(kind, it)
    local r = A.getRemote(kind)
    if not r then return false end
    local idx = State.variantIdx[kind] or 1
    A.fire(r, table.unpack(argBuilders[idx](it)))
    task.wait(0.4)
    local gone = (not it.inst.Parent) or (it.inst:IsA("ValueBase") and it.inst.Value <= 0)
    if not gone then State.variantIdx[kind] = idx % #argBuilders + 1 end
    return gone
end
function A.passItem(it, rarSet, neverMut, neverEq)
    return rarSet[it.rarity] and not (neverMut and it.mutated) and not (neverEq and it.equipped)
end
function A.sellOrDelete(kind, items, rarSet, neverMut, neverEq, cap)
    local n = 0
    for _, it in ipairs(items) do
        if n >= (cap or 8) or not IH.Alive then break end
        if A.passItem(it, rarSet, neverMut, neverEq) then dbg("Действие", kind, "→", it.name); A.itemAction(kind, it); n += 1 end
    end
end
function A.fusePets()
    local r = A.getRemote("fuse")
    if not r then return end
    local groups = {}
    for _, it in ipairs(A.readPets()) do
        if A.passItem(it, Config.FuseRarities, Config.NeverFuseMutated, Config.NeverFuseEquipped) then
            groups[it.name] = groups[it.name] or {}
            table.insert(groups[it.name], it)
        end
    end
    for name, g in pairs(groups) do
        if #g >= Config.FuseCount then
            local ids = {}
            for i = 1, Config.FuseCount do ids[i] = g[i].id end
            dbg("Слияние:", name, "x", Config.FuseCount)
            A.fire(r, table.unpack(ids)); A.fire(r, ids)
            task.wait(0.5)
        end
    end
end
function A.equipBest()
    local best
    for _, p in ipairs(A.readPets()) do
        if p.income and (not best or p.income > best.income) then best = p end
    end
    dbg("Auto Equip Best:", best and best.name or "данных о доходе нет")
    A.call("equipBest", best and { {}, { best.name }, { best.id } } or { {} })
end
function A.refreshPets()
    local ok, pets = pcall(A.readPets)
    if not ok then return {} end
    local counts = {}
    for _, p in ipairs(pets) do counts[p.name] = (counts[p.name] or 0) + p.count end
    for name, c in pairs(counts) do
        if not State.firstPets and c > (State.petCounts[name] or 0) then State.stats.pets += c - (State.petCounts[name] or 0) end
    end
    State.petCounts, State.firstPets, State.lastPets = counts, false, pets
    if UI.renderPets then UI.renderPets(pets) end
    return pets
end
function A.petsTick()
    if A.farmBusy() then return end
    if Config.AutoSell then A.sellOrDelete("sell", A.readPets(), Config.SellRarities, Config.NeverSellMutated, Config.NeverSellEquipped) end
    if Config.AutoDelete then A.sellOrDelete("delete", A.readPets(), Config.DeleteRarities, true, true, 4) end
    if Config.AutoFuse then A.fusePets() end
end
function A.indexTick()
    if not Config.AutoClaimIndex then return end
    dbg("Auto Claim Index")
    A.call("index", { {}, { "All" }, { "ClaimAll" } })
    local n = 0
    for name in pairs(State.petCounts) do
        if n >= 10 then break end
        A.call("index", { { name } }); n += 1
    end
end
function A.upgradesTick()
    if not Config.AutoBuyUpgrades or A.farmBusy() then return end
    local plot = A.myPlot()
    if plot then
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.Enabled then
                local txt = d.Name .. " " .. d.ActionText .. " " .. d.ObjectText .. " " .. (d.Parent and d.Parent.Name or "")
                if U.matchAny(txt, P.upgradePrompts) then
                    local p = d.Parent and U.posOf(d.Parent)
                    local hrp = getHRP()
                    if p and hrp and (p - hrp.Position).Magnitude < (d.MaxActivationDistance or 10) + 20 then A.usePrompt(d) end
                end
            end
        end
    end
    A.call("upgrade", { {} })
end

-- ============================== A: ДОРОЖКА ==============================
function A.myPlot()
    if State.plotCache and State.plotCache.Parent then return State.plotCache end
    local pf = workspace:FindFirstChild("Plots")
    if not pf then dbg("ДОРОЖКА: Workspace.Plots не найден"); return nil end
    local dump = not State.plotDumped
    State.plotDumped = true
    local function mine(plot)
        if plot.Name == LP.Name or plot.Name == LP.DisplayName then return true, "имя плота" end
        for k, v in pairs(plot:GetAttributes()) do
            local s = tostring(v)
            if k:lower():find("owner") and (s == LP.Name or s == tostring(LP.UserId) or s == LP.DisplayName) then return true, "атрибут " .. k end
        end
        for _, ch in ipairs(plot:GetChildren()) do
            if ch:IsA("ValueBase") and ch.Name:lower():find("owner") and
                (ch.Value == LP or tostring(ch.Value) == LP.Name or tostring(ch.Value) == tostring(LP.UserId)) then return true, "значение " .. ch.Name end
        end
        local n = 0
        for _, d in ipairs(plot:GetDescendants()) do
            if d:IsA("TextLabel") and (d.Text:find(LP.Name, 1, true) or d.Text:find(LP.DisplayName, 1, true)) then return true, "табличка с именем" end
            n += 1
            if n > 600 then break end
        end
        return false
    end
    local found
    for _, plot in ipairs(pf:GetChildren()) do
        local ok, why = mine(plot)
        if dump then dbg("  плот", plot.Name, "| мой =", ok and ("да, " .. why) or "нет") end
        if ok and not found then found = plot end
    end
    if not found and State.spawnPos then
        local bd
        for _, plot in ipairs(pf:GetChildren()) do
            local p = U.posOf(plot)
            if p then
                local d = (p - State.spawnPos).Magnitude
                if not bd or d < bd then found, bd = plot, d end
            end
        end
        if found then dbg("ДОРОЖКА: владелец не определён — беру плот, ближайший к месту появления:", found.Name) end
    end
    State.plotCache = found
    if found then dbg("ДОРОЖКА: мой плот =", found:GetFullName()) else dbg("ДОРОЖКА: плот не найден") end
    return found
end
function A.onTreadmill(tm)
    local hrp = getHRP()
    if not hrp then return false end
    local rel = tm.CFrame:PointToObjectSpace(hrp.Position)
    return math.abs(rel.X) <= tm.Size.X / 2 + 1.5 and math.abs(rel.Z) <= tm.Size.Z / 2 + 1.5
        and rel.Y >= -tm.Size.Y / 2 - 2 and rel.Y <= tm.Size.Y / 2 + 8
end
-- 1) MoveTo в центр  2) firetouchinterest(0/1)  3) пауза 0.5 c  4) fireproximityprompt
function A.enterTreadmill(tm, plot, cond)
    local center = tm.Position + Vector3.new(0, tm.Size.Y / 2 + 3, 0)
    for attempt = 1, 3 do
        if not cond() or not alive() then return false end
        dbg("ДОРОЖКА: встаю в центр через MoveTo, попытка", attempt)
        if hdist(getHRP().Position, center) > 3 then M.walkTo(center, 2.5, cond) end
        if not cond() or not alive() then return false end
        getHum():MoveTo(center)
        task.wait(0.4)
        if not A.onTreadmill(tm) and attempt == 3 then
            dbg("ДОРОЖКА: MoveTo не помог 3 раза → PivotTo в центр (запасной вариант)")
            local hrp = getHRP()
            pcall(function() getChar():PivotTo(CFrame.new(center) * (hrp.CFrame - hrp.CFrame.Position)) end)
            task.wait(0.3)
        end
        if A.onTreadmill(tm) then
            dbg("ДОРОЖКА: стою на дорожке")
            if firetouchinterest then
                dbg("ДОРОЖКА: firetouchinterest(HRP, TreadmillBottom, 0 → 1)")
                pcall(function() firetouchinterest(getHRP(), tm, 0); task.wait(0.1); firetouchinterest(getHRP(), tm, 1) end)
            else
                dbg("ДОРОЖКА: firetouchinterest недоступен в этом экзекьюторе")
            end
            task.wait(0.5)
            local pr = tm:FindFirstChildWhichIsA("ProximityPrompt", true)
            if not pr and tm.Parent and tm.Parent ~= plot then pr = tm.Parent:FindFirstChildWhichIsA("ProximityPrompt", true) end
            if Config.TreadmillUsePrompt and pr and fireproximityprompt then
                dbg("ДОРОЖКА: fireproximityprompt →", pr:GetFullName())
                pcall(fireproximityprompt, pr)
                task.wait(0.3)
            else
                dbg("ДОРОЖКА: prompt не найден или отключён — просто бегу")
            end
            return true
        end
        dbg("ДОРОЖКА: всё ещё не на дорожке — повторяю")
    end
    dbg("ДОРОЖКА: встать не удалось → prompt НЕ вызываю (иначе: Not at treadmill!)")
    return false
end
function A.treadmillTick()
    if not Config.AutoTreadmill or not alive() or A.farmBusy() then State.treadEntered = false; return end
    local plot = A.myPlot()
    local tm = plot and plot:FindFirstChild("TreadmillBottom", true)
    if not tm then
        if not State.warnedTread then dbg("ДОРОЖКА: TreadmillBottom не найден в", plot and plot.Name or "?"); State.warnedTread = true end
        return
    end
    local cond = function() return IH.Alive and Config.AutoTreadmill and not A.farmBusy() end
    local center = tm.Position + Vector3.new(0, tm.Size.Y / 2 + 3, 0)
    local d = hdist(getHRP().Position, center)
    if not State.treadEntered or d > 30 or not A.onTreadmill(tm) then
        if State.treadEntered then dbg(("ДОРОЖКА: слетел (%.0f studs от центра) — возвращаюсь"):format(d)) end
        State.treadEntered = A.enterTreadmill(tm, plot, cond)
        if not State.treadEntered then task.wait(2) end
        return
    end
    getHum():MoveTo(center + tm.CFrame.LookVector * Config.TreadmillDir * 50)          -- бежим по LookVector
end

-- ============================== A: ХЭЛЛОУИН =============================
function A.findSwingTool()
    local bp = LP:FindFirstChildOfClass("Backpack")
    for _, root in ipairs({ LP.Character, bp }) do
        if root then
            for _, t in ipairs(root:GetChildren()) do
                if t:IsA("Tool") and U.matchAny(t.Name, P.swingTool) then return t end
            end
        end
    end
    return (bp and bp:FindFirstChildOfClass("Tool")) or (LP.Character and LP.Character:FindFirstChildOfClass("Tool"))
end
function A.swing(target)
    local tool = A.findSwingTool()
    local hum = getHum()
    if tool then
        if tool.Parent ~= LP.Character and hum then pcall(function() hum:EquipTool(tool) end); task.wait(0.1) end
        pcall(function() tool:Activate() end)
    end
    if target then A.call("swing", { { target } }) end
end
function A.nearestIn(root, pats, needHumanoid)
    local hrp, best, bd = getHRP(), nil, nil
    if not hrp or not root then return nil end
    for _, d in ipairs(root:GetDescendants()) do
        if (d:IsA("Model") or d:IsA("BasePart")) and U.matchAny(d.Name, pats) and not Svc.Players:GetPlayerFromCharacter(d)
            and (not needHumanoid or (d:IsA("Model") and d:FindFirstChildOfClass("Humanoid"))) then
            local p = U.posOf(d)
            if p then
                local dd = (p - hrp.Position).Magnitude
                if not bd or dd < bd then best, bd = d, dd end
            end
        end
    end
    return best
end
function A.goNear(target, extra, cond)
    local p = U.posOf(target)
    if not p then return false end
    return M.moveTo(p + (extra or Vector3.new(0, 3, 4)), 6, cond)
end
function A.halloweenTick()
    if A.farmBusy() or not alive() then return end
    local root = W.hRoot()
    if not root then return end
    local function cond() return IH.Alive and not A.farmBusy() end
    if Config.AutoPhantom then
        local p = A.nearestIn(root, P.phantom)
        if p then
            dbg("Phantom Express:", p:GetFullName())
            A.goNear(p, Vector3.new(0, 4, 4), cond)
            local pr = p:FindFirstChildWhichIsA("ProximityPrompt", true)
            if pr then A.usePrompt(pr) else A.swing(p) end
        end
    end
    if Config.AutoMonsters then
        local m = A.nearestIn(root, { ".*" }, true)
        if m then
            dbg("Монстр:", m:GetFullName())
            A.goNear(m, Vector3.new(0, 3, 5), cond)
            A.swing(m)
        end
    end
end
function A.fishingTick()
    if not Config.AutoFishing or not alive() or A.farmBusy() then return end
    local root = W.hRoot()
    if not root then return end
    local fm = A.nearestIn(root, P.fisherman)
    if fm then
        local p = U.posOf(fm)
        local hrp = getHRP()
        if p and (p - hrp.Position).Magnitude > 14 then A.goNear(fm, Vector3.new(0, 3, 8), function() return IH.Alive and Config.AutoFishing end) end
        local pr = fm:FindFirstChildWhichIsA("ProximityPrompt", true)
        if pr then A.usePrompt(pr) end
    end
    local rod
    for _, r in ipairs({ LP.Character, LP:FindFirstChildOfClass("Backpack") }) do
        if r then for _, t in ipairs(r:GetChildren()) do if t:IsA("Tool") and U.matchAny(t.Name, P.rod) then rod = t end end end
    end
    if not rod then setStatus("рыбалка: нет удочки (Haunted Rod)"); return end
    local hum = getHum()
    if rod.Parent ~= LP.Character and hum then pcall(function() hum:EquipTool(rod) end); task.wait(0.2) end
    dbg("Рыбалка: заброс")
    pcall(function() rod:Activate() end)
    A.call("fish", { { "Cast" } })
    task.wait(2.5)
    A.call("fish", { { "Reel" }, { "Catch" } })
    pcall(function() rod:Activate() end)
end

-- ============================== M: ИГРОК (Heartbeat) ====================
function M.setFly(on)
    if State.flyObjs then for _, o in ipairs(State.flyObjs) do pcall(function() o:Destroy() end) end end
    State.flyObjs, State.flyTarget = nil, nil
    if not on then return end
    local hrp = getHRP()
    if not hrp then return end
    local a0 = Instance.new("Attachment"); a0.Parent = hrp
    local ap = Instance.new("AlignPosition")
    ap.Attachment0 = a0; ap.Mode = Enum.PositionAlignmentMode.OneAttachment; ap.MaxForce = 1e9
    ap.Responsiveness = 100; ap.MaxVelocity = Config.PlayerFlySpeed * 1.5; ap.RigidityEnabled = false; ap.Position = hrp.Position; ap.Parent = hrp
    local ao = Instance.new("AlignOrientation")
    ao.Attachment0 = a0; ao.Mode = Enum.OrientationAlignmentMode.OneAttachment; ao.MaxTorque = 1e9; ao.Responsiveness = 100
    ao.CFrame = hrp.CFrame; ao.Parent = hrp
    State.flyObjs = { a0, ap, ao }
    State.flyTarget = hrp.Position
end
function M.heartbeat(dt)
    local hum, hrp = getHum(), getHRP()
    if not hum or not hrp then return end
    -- детектор ударов стража: здоровье упало или сработал Ragdoll (нужен для отмены кражи)
    local hp = hum.Health
    if State.lastHealth and hp < State.lastHealth - 0.5 then State.hitAt = tick() end
    State.lastHealth = hp
    local st0 = hum:GetState()
    local rag = (st0 == Enum.HumanoidStateType.Ragdoll or st0 == Enum.HumanoidStateType.FallingDown or hum.PlatformStand)
    if rag and not State.wasRag then State.hitAt = tick() end
    State.wasRag = rag
    -- WalkSpeed / JumpPower
    local cur = hum.WalkSpeed
    if State.lastSet == nil or math.abs(cur - State.lastSet) > 0.01 then State.baseWalk = cur end
    local wantWS = State.returnSpeed or (Config.WalkSpeedOverride and Config.WalkSpeed) or nil
    if wantWS then
        if math.abs(hum.WalkSpeed - wantWS) > 0.01 then hum.WalkSpeed = wantWS end
        State.lastSet = wantWS
    elseif State.lastSet ~= nil then
        hum.WalkSpeed = State.baseWalk; State.lastSet = nil
    end
    if Config.JumpPowerOverride then hum.UseJumpPower = true; hum.JumpPower = Config.JumpPower end
    -- Anti-Ragdoll
    if Config.AntiRagdoll then
        local st = hum:GetState()
        if st == Enum.HumanoidStateType.Ragdoll or st == Enum.HumanoidStateType.FallingDown then hum:ChangeState(Enum.HumanoidStateType.GettingUp) end
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
        for _, d in ipairs(getChar():GetDescendants()) do
            if d:IsA("BallSocketConstraint") then d:Destroy()
            elseif d:IsA("Motor6D") and not d.Enabled then d.Enabled = true end
        end
    end
    -- Anti-Knockback: PlatformStand = false каждый кадр, гасим скорость только при сильном импульсе
    if Config.AntiKnockback then
        if hum.PlatformStand then hum.PlatformStand = false end
        if not State.moving and not Config.Fly then
            local v = hrp.AssemblyLinearVelocity
            if Vector3.new(v.X, 0, v.Z).Magnitude > hum.WalkSpeed * 1.5 + 15 then
                hrp.AssemblyLinearVelocity = Vector3.new(v.X * 0.1, v.Y, v.Z * 0.1)
            end
        end
    end
    -- Fly (AlignPosition)
    if Config.Fly and not (State.flyObjs and State.flyObjs[2].Parent) then M.setFly(true)
    elseif not Config.Fly and State.flyObjs then M.setFly(false) end
    if Config.Fly and State.flyObjs and State.flyTarget then
        local cam = workspace.CurrentCamera
        local d = hum.MoveDirection
        if Svc.UserInputService:IsKeyDown(Enum.KeyCode.Space) then d += Vector3.yAxis end
        if Svc.UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then d -= Vector3.yAxis end
        if d.Magnitude > 0 then State.flyTarget += d.Unit * Config.PlayerFlySpeed * dt end
        local off = State.flyTarget - hrp.Position
        if off.Magnitude > 40 then State.flyTarget = hrp.Position + off.Unit * 40 end
        State.flyObjs[2].Position = State.flyTarget
        State.flyObjs[2].MaxVelocity = Config.PlayerFlySpeed * 1.5
        local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
        if look.Magnitude > 0.1 then State.flyObjs[3].CFrame = CFrame.lookAt(Vector3.zero, look) end
    end
end

-- ============================== A: СЕРВИС ===============================
-- Server Hop: сервер с 1-2 игроками (API games.roblox.com, sortOrder=Asc, limit=100)
function A.serverHop()
    dbg("SERVER HOP: ищу сервер с 1-2 игроками...")
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)
    local body
    local ok, res = pcall(function() return game:HttpGet(url) end)
    if ok and type(res) == "string" then
        body = res
    else
        local req = (syn and syn.request) or http_request or request or (http and http.request) or (fluxus and fluxus.request)
        if req then
            local ok2, r2 = pcall(req, { Url = url, Method = "GET" })
            if ok2 and type(r2) == "table" then body = r2.Body end
        end
    end
    if not body then dbg("SERVER HOP: не удалось получить список серверов"); return end
    local okd, data = pcall(function() return Svc.HttpService:JSONDecode(body) end)
    if not okd or type(data) ~= "table" or not data.data then dbg("SERVER HOP: ответ API не разобран"); return end
    local cands = {}
    for _, sv in ipairs(data.data) do
        if sv.id ~= game.JobId and sv.playing and sv.maxPlayers and sv.playing <= 2 and sv.playing < sv.maxPlayers then cands[#cands + 1] = sv end
    end
    print("[DEBUG] Найдено серверов:", #cands)
    if #cands == 0 then dbg("SERVER HOP: подходящих серверов (≤ 2 игроков) нет"); return end
    local pick = cands[math.random(1, #cands)]
    dbg("SERVER HOP: телепорт на сервер", pick.id, "| игроков:", pick.playing)
    pcall(function() Svc.TeleportService:TeleportToPlaceInstance(game.PlaceId, pick.id, LP) end)
end

-- Anti-Traps: Trap / Spike / Beartrap / Snare → CanTouch = false (список обновляется раз в 5 c, применяется каждую секунду)
local trapPats = { "trap", "spike", "beartrap", "snare" }
function A.antiTrapsTick()
    if not Config.AntiTraps then return end
    if os.clock() - State.trapScanAt > 5 then
        State.trapScanAt = os.clock()
        local list = {}
        local all = workspace:GetDescendants()
        for i = 1, #all do
            local d = all[i]
            if i % 4000 == 0 then task.wait() end
            if (d:IsA("BasePart") or d:IsA("Model")) and U.matchAny(d.Name, trapPats) then
                if d:IsA("BasePart") then list[#list + 1] = d
                else
                    for _, pp in ipairs(d:GetDescendants()) do if pp:IsA("BasePart") then list[#list + 1] = pp end end
                end
            end
        end
        State.traps = list
        dbg("Anti-Traps: найдено частей-ловушек:", #list)
    end
    for _, pp in ipairs(State.traps) do
        if pp.Parent and pp.CanTouch then pcall(function() pp.CanTouch = false end) end
    end
end

-- ============================== E: ESP (Highlight) ======================
E.objs = {}
function E.collect()
    local list = {}
    local hrp = getHRP()
    local origin = hrp and hrp.Position or Vector3.zero
    local function add(key, adornee, color, title, sub)
        local pos = U.posOf(adornee)
        if not pos then return end
        list[#list + 1] = { key = key, adornee = adornee, color = color, title = title, sub = sub, dist = (pos - origin).Magnitude }
    end
    if Config.ESPEggs then
        for _, e in ipairs(State.eggs) do
            local d = e.data
            local col = RarityColor[d.rarity or ""] or Color3.fromRGB(255, 220, 80)
            add(e.prompt, e.holder or e.part, col, "🥚 " .. d.name .. " · " .. (d.rarity and (RarityRU[d.rarity] or d.rarity) or "Неизвестно"),
                ("Вес: %s · Доход: %s"):format(d.weight and (U.fmt(d.weight) .. " kg") or "—",
                    d.incomeText and ("$" .. d.incomeText .. "/s") or (d.income and ("$" .. U.fmt(d.income) .. "/s") or "—")))
        end
    end
    if Config.ESPGuards then
        local ga = W.guardAreas()
        if ga then
            for _, area in ipairs(ga:GetChildren()) do
                for _, c in ipairs(area:GetChildren()) do
                    if c.Name ~= "Nests" and c:IsA("Model") and (c:FindFirstChildOfClass("Humanoid") or U.matchAny(c.Name, P.guard)) then
                        add(c, c, Color3.fromRGB(255, 70, 70), "⚠ Страж: " .. c.Name, area.Name)
                    end
                end
            end
        end
    end
    if Config.ESPPets then
        local pf = workspace:FindFirstChild("Plots")
        if pf then
            local n = 0
            for _, d in ipairs(pf:GetDescendants()) do
                n += 1
                if n > 4000 then break end
                if d:IsA("Model") and KnownPets[d.Name] then add(d, d, Color3.fromRGB(120, 255, 160), "🐾 " .. d.Name, "$" .. U.fmt(KnownPets[d.Name]) .. "/s") end
            end
        end
    end
    if Config.ESPPlayers then
        for _, pl in ipairs(Svc.Players:GetPlayers()) do
            if pl ~= LP and pl.Character and pl.Character:FindFirstChild("HumanoidRootPart") then
                add(pl.Character, pl.Character, Color3.new(1, 1, 1), "👤 " .. pl.DisplayName, "")
            end
        end
    end
    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end
function E.tick()
    if not UI.espFolder then return end
    local list = (Config.ESPEggs or Config.ESPGuards or Config.ESPPets or Config.ESPPlayers) and E.collect() or {}
    local seen, hl = {}, 0
    for i, e in ipairs(list) do
        if i > 80 then break end
        seen[e.key] = true
        local o = E.objs[e.key]
        local anchor = e.adornee:IsA("BasePart") and e.adornee or e.adornee:FindFirstChildWhichIsA("BasePart", true)
        if anchor then
            if not o or not o.bb.Parent then
                local bb = Instance.new("BillboardGui")
                bb.Adornee = anchor; bb.AlwaysOnTop = true; bb.Size = UDim2.fromOffset(200, 58); bb.StudsOffset = Vector3.new(0, 4, 0)
                bb.MaxDistance = math.huge; bb.Parent = UI.espFolder
                local tl = Instance.new("TextLabel")
                tl.BackgroundTransparency = 1; tl.Size = UDim2.fromScale(1, 1); tl.Font = Enum.Font.GothamBold; tl.TextSize = 12
                tl.TextStrokeTransparency = 0.3; tl.Parent = bb
                o = { bb = bb, tl = tl }
                E.objs[e.key] = o
            end
            o.tl.Text = ("%s\n%s\n%d studs"):format(e.title, e.sub, math.floor(e.dist))
            o.tl.TextColor3 = e.color
            if hl < 28 then
                hl += 1
                if not o.hl or not o.hl.Parent then
                    local h = Instance.new("Highlight")
                    h.Adornee = e.adornee; h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; h.FillTransparency = 0.55
                    h.OutlineColor = Color3.new(1, 1, 1); h.Parent = UI.espFolder
                    o.hl = h
                end
                o.hl.FillColor = e.color
            elseif o.hl then o.hl:Destroy(); o.hl = nil end
        end
    end
    for k, o in pairs(E.objs) do
        if not seen[k] then
            pcall(function() o.bb:Destroy() end)
            if o.hl then pcall(function() o.hl:Destroy() end) end
            E.objs[k] = nil
        end
    end
end

-- ============================== МУЗЫКА ==================================
local sound = nil
local function resolveSoundId(id)
    id = tostring(id or "")
    if id:match("^%d+$") then return "rbxassetid://" .. id end
    if id:match("^rbxassetid://") or id:match("^rbxasset://") or id:match("^rbxplay://") then return id end
    if getcustomasset and isfile and isfile(id) then
        local ok, a = pcall(getcustomasset, id)
        if ok then return a end
    end
    return id
end
-- каждый запуск = новый чистый Sound в SoundService
function A.playId(id, name)
    if sound then pcall(function() sound:Stop(); sound:Destroy() end) end
    local snd = Instance.new("Sound")
    snd.Name = "IvanHubMusic"; snd.Volume = Config.Volume; snd.Looped = (#State.queue == 0); snd.Parent = Svc.SoundService
    snd.SoundId = resolveSoundId(id)
    sound = snd
    snd.Ended:Connect(function()                                           -- следующий трек из очереди
        if sound == snd and #State.queue > 0 then
            local nx = table.remove(State.queue, 1)
            A.playId(nx.id, nx.name)
        end
    end)
    snd:Play()
    dbg("МУЗЫКА: играю", name or id, "|", snd.SoundId)
    if ui.musicStatus then ui.musicStatus.Text = "Играет: " .. tostring(name or id) .. (#State.queue > 0 and (" · в очереди: " .. #State.queue) or "") end
    task.delay(3, function()                                               -- проверка загрузки через 3 секунды
        if IH.Alive and sound == snd and snd.TimeLength == 0 then
            print("[DEBUG] Трек заблокирован или удален")
            if ui.musicStatus then ui.musicStatus.Text = "Трек заблокирован или удалён — введи другой ID / открой YouTube Player" end
        end
    end)
end
function A.playTrack(i)
    local tr = Config.Music[i]
    if not tr then return end
    State.queue = {}
    A.playId(tr.id, tr.name)
end
-- Стоп: чистим очередь, останавливаем и уничтожаем Sound
function A.stopMusic()
    State.queue = {}
    if sound then pcall(function() sound:Stop(); sound:Destroy() end) end
    sound = nil
    for _, d in ipairs(Svc.SoundService:GetChildren()) do
        if d.Name == "IvanHubMusic" then pcall(function() d:Stop(); d:Destroy() end) end
    end
    dbg("МУЗЫКА: стоп, очередь очищена")
    if ui.musicStatus then ui.musicStatus.Text = "Остановлено" end
end

-- ============================== UI: ИНТЕРФЕЙС ===========================
function UI.build()
    local TS, UIS = Svc.TweenService, Svc.UserInputService
    local BG, SIDE, PANEL = Color3.fromRGB(14, 10, 26), Color3.fromRGB(22, 15, 42), Color3.fromRGB(34, 24, 60)
    local ACC, ACC2 = Color3.fromRGB(138, 92, 255), Color3.fromRGB(255, 140, 40)
    local TXT, SUB, OFF = Color3.fromRGB(240, 235, 252), Color3.fromRGB(165, 155, 195), Color3.fromRGB(70, 60, 100)
    local GREEN, RED = Color3.fromRGB(50, 170, 90), Color3.fromRGB(190, 60, 60)
    local function tw(i, t, p) TS:Create(i, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), p):Play() end
    local function corner(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = i end
    local function stroke(i, col, th, tr) local s = Instance.new("UIStroke"); s.Color = col; s.Thickness = th or 1.3; s.Transparency = tr or 0.35; s.Parent = i end
    local function grad(i, c1, c2, rot) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(c1, c2); g.Rotation = rot or 0; g.Parent = i end
    local function txt(parent, text, size, pos, fs, bold, color, xa)
        local l = Instance.new("TextLabel")
        l.BackgroundTransparency = 1; l.Size = size; l.Position = pos or UDim2.new(); l.Text = text; l.TextColor3 = color or TXT
        l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham; l.TextSize = fs or 13; l.TextWrapped = true
        l.TextXAlignment = xa or Enum.TextXAlignment.Left; l.TextYAlignment = Enum.TextYAlignment.Top; l.Parent = parent
        return l
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "IvanHubV12"; gui.ResetOnSpawn = false; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; gui.DisplayOrder = 999
    pcall(function() if syn and syn.protect_gui then syn.protect_gui(gui) end end)
    local okp = pcall(function() gui.Parent = (gethui and gethui()) or Svc.CoreGui end)
    if not okp or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
    UI.gui = gui
    UI.espFolder = Instance.new("Folder"); UI.espFolder.Name = "ESP"; UI.espFolder.Parent = gui

    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
    local fit = math.min(1, (vp.X - 16) / 920, (vp.Y - 16) / 470)

    -- перетаскивание: каждая панель тянется отдельно за свою шапку
    local function drag(handle, target)
        local dragging, ds, sp
        handle.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                dragging, ds, sp = true, i.Position, target.Position
                i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
            end
        end)
        U.connect(UIS.InputChanged, function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - ds
                target.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
            end
        end)
    end
    local function panelFrame(w, h, pos, title, c1, c2, strokeCol)
        local f = Instance.new("Frame")
        f.Size = UDim2.fromOffset(w, h); f.Position = pos; f.BackgroundColor3 = BG; f.BorderSizePixel = 0; f.ClipsDescendants = true; f.Parent = gui
        corner(f, 12); stroke(f, strokeCol)
        local sc = Instance.new("UIScale"); sc.Scale = fit; sc.Parent = f
        local head = Instance.new("TextButton")
        head.Size = UDim2.new(1, 0, 0, 36); head.Text = ""; head.AutoButtonColor = false; head.BorderSizePixel = 0
        head.BackgroundColor3 = Color3.new(1, 1, 1); head.Parent = f; corner(head, 12); grad(head, c1, c2)
        txt(head, title, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(12, 9), 15, true, Color3.new(1, 1, 1))
        drag(head, f)
        return f
    end

    local menu = panelFrame(480, 440, UDim2.new(0, 70, 0.5, -220 * fit), "Иван Хаб  ·  Steal an Egg  ·  v12", ACC, ACC2, ACC)
    local panel = panelFrame(450, 440, UDim2.new(1, -(470 * fit), 0.5, -220 * fit), "⚙  Панель кражи", ACC2, Color3.fromRGB(255, 90, 40), ACC2)
    ui.menu, ui.panel = menu, panel

    -- показ/скрытие обеих панелей: RightShift и круглая кнопка
    local shown = true
    local function setShown(v)
        shown = v
        menu.Visible = v; panel.Visible = v
    end
    U.connect(UIS.InputBegan, function(i, gp)
        if not gp and i.KeyCode == Enum.KeyCode.RightShift then setShown(not shown) end
    end)
    local orb = Instance.new("TextButton")
    orb.Size = UDim2.fromOffset(48, 48); orb.Position = UDim2.new(0, 12, 0.5, -24); orb.Text = "ИХ"; orb.Font = Enum.Font.GothamBold
    orb.TextSize = 16; orb.TextColor3 = Color3.new(1, 1, 1); orb.AutoButtonColor = false; orb.BackgroundColor3 = Color3.new(1, 1, 1)
    orb.ZIndex = 100; orb.Parent = gui; corner(orb, 24); stroke(orb, ACC2, 2, 0.15); grad(orb, ACC, ACC2, 45)
    do
        local down, moved, ds, sp = false, false, nil, nil
        orb.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
                down, moved, ds, sp = true, false, i.Position, orb.Position
                tw(orb, 0.1, { Size = UDim2.fromOffset(42, 42) })
            end
        end)
        U.connect(UIS.InputChanged, function(i)
            if down and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
                local d = i.Position - ds
                if d.Magnitude > 6 then moved = true end
                if moved then orb.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y) end
            end
        end)
        U.connect(UIS.InputEnded, function(i)
            if down and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then
                down = false
                tw(orb, 0.1, { Size = UDim2.fromOffset(48, 48) })
                if not moved then setShown(not shown) end
            end
        end)
    end

    -- ---------- левое меню: вкладки ----------
    local sideBar = Instance.new("ScrollingFrame")
    sideBar.Size = UDim2.new(0, 108, 1, -44); sideBar.Position = UDim2.fromOffset(6, 40); sideBar.BackgroundTransparency = 1
    sideBar.BorderSizePixel = 0; sideBar.ScrollBarThickness = 2; sideBar.AutomaticCanvasSize = Enum.AutomaticSize.Y; sideBar.CanvasSize = UDim2.new(); sideBar.Parent = menu
    do local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 4); l.Parent = sideBar end
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, -126, 1, -46); holder.Position = UDim2.fromOffset(120, 42); holder.BackgroundTransparency = 1; holder.Parent = menu

    local pages, tabBtns = {}, {}
    local function selectTab(name)
        for n, p in pairs(pages) do p.Visible = (n == name) end
        for n, b in pairs(tabBtns) do tw(b, 0.15, { BackgroundColor3 = n == name and ACC or PANEL, TextColor3 = n == name and Color3.new(1, 1, 1) or SUB }) end
    end
    local function page(name)
        local p = Instance.new("ScrollingFrame")
        p.Size = UDim2.fromScale(1, 1); p.BackgroundTransparency = 1; p.BorderSizePixel = 0; p.ScrollBarThickness = 3
        p.AutomaticCanvasSize = Enum.AutomaticSize.Y; p.CanvasSize = UDim2.new(); p.Visible = false; p.Parent = holder
        local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 6); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = p
        pages[name] = p
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -4, 0, 30); b.Text = name; b.Font = Enum.Font.GothamMedium; b.TextSize = 13; b.TextColor3 = SUB
        b.BackgroundColor3 = PANEL; b.AutoButtonColor = false; b.Parent = sideBar; corner(b, 7)
        tabBtns[name] = b
        b.MouseButton1Click:Connect(function() selectTab(name) end)
        return p
    end
    local function row(pg, h)
        local f = Instance.new("Frame")
        f.Size = UDim2.new(1, -6, 0, h or 32); f.BackgroundColor3 = PANEL; f.BorderSizePixel = 0; f.Parent = pg; corner(f, 7)
        return f
    end
    local function section(pg, text) txt(pg, text, UDim2.new(1, -6, 0, 20), nil, 13, true, ACC2) end
    local function label(pg, text, h) local r = row(pg, h or 30); return txt(r, text, UDim2.new(1, -14, 1, -4), UDim2.fromOffset(8, 4), 12) end
    local function toggle(pg, text, key, cb)
        local r = row(pg, 32)
        txt(r, text, UDim2.new(1, -62, 1, 0), UDim2.fromOffset(10, 8), 13)
        local sw = Instance.new("TextButton")
        sw.Size = UDim2.fromOffset(40, 20); sw.Position = UDim2.new(1, -48, 0.5, -10); sw.Text = ""; sw.AutoButtonColor = false; sw.Parent = r; corner(sw, 10)
        local knob = Instance.new("Frame")
        knob.Size = UDim2.fromOffset(16, 16); knob.BackgroundColor3 = Color3.new(1, 1, 1); knob.Parent = sw; corner(knob, 8)
        local function show(anim)
            local v = Config[key]
            local c, pos = v and ACC or OFF, v and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
            if anim then tw(sw, 0.15, { BackgroundColor3 = c }); tw(knob, 0.15, { Position = pos }) else sw.BackgroundColor3 = c; knob.Position = pos end
        end
        sw.MouseButton1Click:Connect(function()
            Config[key] = not Config[key]; show(true)
            dbg("НАСТРОЙКА:", key, "=", Config[key])
            if cb then task.spawn(cb, Config[key]) end
        end)
        show(false)
    end
    local function button(pg, text, fn, colorful)
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, -6, 0, 32); b.Text = text; b.TextColor3 = Color3.new(1, 1, 1); b.Font = Enum.Font.GothamBold; b.TextSize = 13
        b.BackgroundColor3 = colorful and Color3.new(1, 1, 1) or PANEL; b.Parent = pg; corner(b, 7)
        if colorful then grad(b, ACC, ACC2) end
        b.MouseButton1Click:Connect(function() task.spawn(function() local ok, e = xpcall(fn, tb, b); if not ok then dbg("ОШИБКА кнопки:", e) end end) end)
        return b
    end
    local function cycler(pg, label_, key, options, cb)
        local b
        b = button(pg, "", function()
            local idx = 1
            for i, o in ipairs(options) do if o == Config[key] then idx = i end end
            Config[key] = options[idx % #options + 1]
            b.Text = label_ .. ": " .. tostring(Config[key]) .. "  ›"
            dbg("НАСТРОЙКА:", label_, "=", Config[key])
            if cb then cb(Config[key]) end
        end)
        b.Text = label_ .. ": " .. tostring(Config[key]) .. "  ›"
    end
    -- выпадающий список (раскрывается под кнопкой)
    local function dropdown(pg, label_, key, options)
        local box = Instance.new("Frame")
        box.Size = UDim2.new(1, -6, 0, 0); box.AutomaticSize = Enum.AutomaticSize.Y; box.BackgroundTransparency = 1; box.Parent = pg
        local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0, 3); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = box
        local head = Instance.new("TextButton")
        head.Size = UDim2.new(1, 0, 0, 32); head.BackgroundColor3 = PANEL; head.TextColor3 = TXT; head.Font = Enum.Font.GothamBold; head.TextSize = 13
        head.LayoutOrder = 1; head.Parent = box; corner(head, 7)
        local list = Instance.new("Frame")
        list.Size = UDim2.new(1, 0, 0, 0); list.AutomaticSize = Enum.AutomaticSize.Y; list.BackgroundColor3 = SIDE; list.Visible = false
        list.LayoutOrder = 2; list.Parent = box; corner(list, 7)
        local ll = Instance.new("UIListLayout"); ll.SortOrder = Enum.SortOrder.LayoutOrder; ll.Parent = list
        local function show() head.Text = label_ .. ": " .. tostring(Config[key]) .. (list.Visible and "  ▴" or "  ▾") end
        for i, o in ipairs(options) do
            local ob = Instance.new("TextButton")
            ob.Size = UDim2.new(1, 0, 0, 26); ob.BackgroundTransparency = 1; ob.Font = Enum.Font.Gotham; ob.TextSize = 13; ob.TextColor3 = TXT
            ob.TextXAlignment = Enum.TextXAlignment.Left; ob.Text = "   " .. o; ob.LayoutOrder = i; ob.Parent = list
            ob.MouseButton1Click:Connect(function()
                Config[key] = o; list.Visible = false; show()
                dbg("НАСТРОЙКА:", label_, "=", o)
            end)
        end
        head.MouseButton1Click:Connect(function() list.Visible = not list.Visible; show() end)
        show()
    end
    local function slider(pg, text, key, min, max, step)
        local r = row(pg, 46)
        local lbl = txt(r, "", UDim2.new(1, -14, 0, 20), UDim2.fromOffset(10, 4), 13)
        local bar = Instance.new("Frame")
        bar.Size = UDim2.new(1, -24, 0, 6); bar.Position = UDim2.new(0, 12, 0, 32); bar.BackgroundColor3 = OFF; bar.Parent = r; corner(bar, 3)
        local fill = Instance.new("Frame"); fill.Size = UDim2.new(0, 0, 1, 0); fill.BackgroundColor3 = Color3.new(1, 1, 1); fill.Parent = bar; corner(fill, 3)
        grad(fill, ACC, ACC2)
        local function show()
            local v = Config[key]
            fill.Size = UDim2.new(math.clamp((v - min) / (max - min), 0, 1), 0, 1, 0)
            lbl.Text = text .. ": " .. tostring(math.floor(v * 100 + 0.5) / 100)
        end
        local dragging = false
        local function fromX(x)
            local v = min + math.clamp((x - bar.AbsolutePosition.X) / math.max(1, bar.AbsoluteSize.X), 0, 1) * (max - min)
            Config[key] = math.clamp(math.floor(v / step + 0.5) * step, min, max)
            show()
        end
        bar.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true; fromX(i.Position.X) end
        end)
        U.connect(UIS.InputChanged, function(i)
            if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then fromX(i.Position.X) end
        end)
        U.connect(UIS.InputEnded, function(i)
            if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end
        end)
        show()
    end
    local function input(pg, placeholder, default, cb)
        local tb_ = Instance.new("TextBox")
        tb_.Size = UDim2.new(1, -6, 0, 28); tb_.BackgroundColor3 = PANEL; tb_.Text = default or ""; tb_.TextColor3 = TXT; tb_.Font = Enum.Font.Gotham
        tb_.TextSize = 12; tb_.ClearTextOnFocus = false; tb_.PlaceholderText = placeholder; tb_.PlaceholderColor3 = SUB
        tb_.TextXAlignment = Enum.TextXAlignment.Left; tb_.Parent = pg; corner(tb_, 6)
        tb_.FocusLost:Connect(function() cb(tb_.Text) end)
    end
    -- «чипсы» редкостей: нажми, чтобы включить/выключить редкость в фильтре
    local function chips(pg, title, key)
        local r = row(pg, 118)
        txt(r, title, UDim2.new(1, -14, 0, 18), UDim2.fromOffset(8, 3), 12, true)
        local wrap = Instance.new("Frame")
        wrap.Size = UDim2.new(1, -12, 1, -24); wrap.Position = UDim2.fromOffset(6, 22); wrap.BackgroundTransparency = 1; wrap.Parent = r
        local l = Instance.new("UIGridLayout"); l.CellSize = UDim2.fromOffset(78, 22); l.CellPadding = UDim2.fromOffset(4, 4); l.Parent = wrap
        for _, rar in ipairs(Rarities) do
            local c = Instance.new("TextButton")
            c.Text = RarityRU[rar]; c.Font = Enum.Font.Gotham; c.TextSize = 10; c.TextColor3 = Color3.new(1, 1, 1); c.AutoButtonColor = false; c.Parent = wrap; corner(c, 5)
            local function show() c.BackgroundColor3 = Config[key][rar] and RarityColor[rar] or OFF; c.TextColor3 = Config[key][rar] and Color3.new(0, 0, 0) or Color3.new(1, 1, 1) end
            c.MouseButton1Click:Connect(function() Config[key][rar] = (not Config[key][rar]) or nil; show() end)
            show()
        end
    end

    -- ===== Главная =====
    local pMain = page("Главная")
    ui.status = txt(pMain, "Статус: сканирую карту...", UDim2.new(1, -6, 0, 32), nil, 12, true)
    ui.stats = label(pMain, "Статистика", 34)
    section(pMain, "Кража")
    local bOpts = { "All", "Auto" }
    for _, b in ipairs(Biomes) do bOpts[#bOpts + 1] = b.name end
    bOpts[#bOpts + 1] = "Хэллоуин"
    dropdown(pMain, "Откуда брать", "StartBiome", bOpts)
    dropdown(pMain, "Куда нести", "TargetZone", bOpts)
    cycler(pMain, "Приоритет", "Priority", { "Closest", "Income", "Rarity", "Weight" })
    cycler(pMain, "Движение", "MoveMode", { "Walk", "Fly" })
    toggle(pMain, "Хэллоуин: брать яйца (через портал)", "HalloweenEggs")
    button(pMain, "Повторно вывести ВСЕ промпты в консоль", function()
        State.promptLogged = {}
        dbg("Список промптов будет выведен целиком при ближайшем скане (≈2 c)")
    end)
    button(pMain, "Дамп SmartPromptPart (в консоль)", function()
        print("[DEBUG] ===== ДАМП SmartPromptPart =====")
        local n = 0
        for _, d in ipairs(workspace:GetDescendants()) do
            if d.Name == "SmartPromptPart" and d:IsA("BasePart") then
                n += 1
                if n <= 15 then
                    local pr = d:FindFirstChildWhichIsA("ProximityPrompt")
                    print("[DEBUG]", d:GetFullName(), "| prompt:", pr and (pr.ActionText .. " / " .. pr.ObjectText) or "нет", "| enabled:", pr and pr.Enabled)
                end
            end
        end
        print("[DEBUG] всего SmartPromptPart:", n, "| NestModel:", #State.nests, "| HalloweenEgg:", #W.halloweenEggs())
        print("[DEBUG] fireproximityprompt:", fireproximityprompt ~= nil, "| firetouchinterest:", firetouchinterest ~= nil)
    end)

    -- ===== Питомцы =====
    local pPets = page("Питомцы")
    local totalLbl = label(pPets, "Общий доход: —", 26)
    local petRows, petsSig = {}, ""
    UI.renderPets = function(pets)
        pets = pets or State.lastPets
        local total = 0
        for _, p in ipairs(pets) do if p.income then total += p.income * p.count end end
        totalLbl.Text = "Общий доход: $" .. U.fmt(total) .. "/s · питомцев: " .. #pets
        local sig = #pets .. "|" .. total
        if sig == petsSig then return end
        petsSig = sig
        for _, r in ipairs(petRows) do r:Destroy() end
        petRows = {}
        table.sort(pets, function(a, b) return (a.income or -1) > (b.income or -1) end)
        for i, p in ipairs(pets) do
            if i > 60 then break end
            local r = row(pPets, 24); r.LayoutOrder = 100 + i
            local l1 = txt(r, p.name .. (p.count > 1 and (" x" .. p.count) or "") .. (p.mutated and " ✦" or "") .. (p.equipped and " ◆" or ""),
                UDim2.new(0.5, 0, 1, 0), UDim2.fromOffset(8, 5), 12)
            l1.TextTruncate = Enum.TextTruncate.AtEnd
            txt(r, p.income and ("$" .. U.fmt(p.income) .. "/s") or "Неизвестно", UDim2.new(0.45, -8, 1, 0), UDim2.new(0.55, 0, 0, 5), 11, false,
                RarityColor[p.rarity] or SUB, Enum.TextXAlignment.Right)
            petRows[#petRows + 1] = r
        end
    end
    button(pPets, "Обновить список", function() A.refreshPets() end)
    toggle(pPets, "Auto Equip Best", "AutoEquipBest")
    button(pPets, "Экипировать лучших сейчас", function() A.equipBest() end)
    section(pPets, "Auto Fuse")
    toggle(pPets, "Auto Fuse", "AutoFuse")
    chips(pPets, "Редкости для слияния", "FuseRarities")
    toggle(pPets, "Never fuse mutated", "NeverFuseMutated")
    toggle(pPets, "Never fuse equipped", "NeverFuseEquipped")
    section(pPets, "Auto Sell")
    toggle(pPets, "Auto Sell", "AutoSell")
    chips(pPets, "Редкости на продажу", "SellRarities")
    toggle(pPets, "Never Sell Mutated", "NeverSellMutated")
    toggle(pPets, "Never Sell Equipped", "NeverSellEquipped")
    section(pPets, "Auto Delete (ОПАСНО, навсегда)")
    toggle(pPets, "Auto Delete", "AutoDelete")
    chips(pPets, "Редкости для удаления", "DeleteRarities")

    -- ===== Прогресс =====
    local pProg = page("Прогресс")
    toggle(pProg, "Auto Treadmill (firetouchinterest)", "AutoTreadmill", function() State.treadEntered = false end)
    button(pProg, "Развернуть направление бега", function() Config.TreadmillDir = -Config.TreadmillDir; dbg("ДОРОЖКА: направление =", Config.TreadmillDir) end)
    toggle(pProg, "Нажимать prompt дорожки после входа", "TreadmillUsePrompt")
    button(pProg, "Найти мой плот (дамп в консоль)", function()
        State.plotCache = nil; State.plotDumped = false; State.warnedTread = false
        local p = A.myPlot()
        if p then dbg("TreadmillBottom:", p:FindFirstChild("TreadmillBottom", true) and "найден" or "НЕ НАЙДЕН") end
    end)
    toggle(pProg, "Auto Buy Upgrades", "AutoBuyUpgrades")
    toggle(pProg, "Auto Claim Index", "AutoClaimIndex")
    label(pProg, "Кража важнее дорожки и апгрейдов: пока идёт кража, они на паузе.", 40)

    -- ===== Хэллоуин =====
    local pHal = page("Хэллоуин")
    ui.hLbl = label(pHal, "Измерение: ...", 30)
    toggle(pHal, "Брать яйца Хэллоуина (через портал)", "HalloweenEggs")
    button(pHal, "Return to Halloween (из Train-ивента)", function() A.returnToHalloween(function() return IH.Alive end) end)
    toggle(pHal, "Auto Phantom Express", "AutoPhantom")
    toggle(pHal, "Auto Monsters", "AutoMonsters")
    toggle(pHal, "Auto Fishing (нужна Haunted Rod)", "AutoFishing")
    label(pHal, "Если яйцо в измерении (Y < -100), а ты в обычном мире, скрипт ищет Portal/Whirlpool и входит в него. Сдача: HalloweenDimension.Zones.SafeZone.", 56)

    -- ===== Игрок =====
    local pPl = page("Игрок")
    toggle(pPl, "WalkSpeed Override", "WalkSpeedOverride")
    slider(pPl, "WalkSpeed", "WalkSpeed", 16, 500, 1)
    toggle(pPl, "JumpPower Override", "JumpPowerOverride")
    slider(pPl, "JumpPower", "JumpPower", 50, 300, 1)
    toggle(pPl, "Fly (AlignPosition)", "Fly")
    slider(pPl, "Скорость полёта", "PlayerFlySpeed", 20, 300, 5)
    toggle(pPl, "Anti-Ragdoll", "AntiRagdoll")
    toggle(pPl, "Anti-Knockback", "AntiKnockback")
    toggle(pPl, "Infinite Jump", "InfJump")
    toggle(pPl, "Noclip", "NoClip")
    toggle(pPl, "Anti-Traps", "AntiTraps")
    button(pPl, "Сбросить скорость (16)", function()
        Config.WalkSpeedOverride = false; Config.WalkSpeed = 16
        local h = getHum(); if h then h.WalkSpeed = 16 end
    end)

    -- ===== ESP =====
    local pEsp = page("ESP")
    toggle(pEsp, "Яйца", "ESPEggs")
    toggle(pEsp, "Стражи", "ESPGuards")
    toggle(pEsp, "Питомцы", "ESPPets")
    toggle(pEsp, "Игроки", "ESPPlayers")
    label(pEsp, "Подсветка через Highlight (до 28 объектов), над яйцами — вес, доход и редкость.", 40)

    -- ===== Музыка =====
    local pMus = page("Музыка")
    ui.musicStatus = txt(pMus, "Остановлено", UDim2.new(1, -6, 0, 18), nil, 13, true)
    input(pMus, "Поиск в списке / ID трека (Enter)", "", function(t)
        t = t or ""
        if t == "" then return end
        if t:match("^%d+$") or t:match("^rbxassetid://") or t:match("^rbxasset://") or t:match("^rbxplay://") then
            if sound and sound.IsPlaying then                                  -- что-то уже играет → в очередь
                State.queue[#State.queue + 1] = { id = t, name = "Трек " .. t }
                sound.Looped = false
                dbg("МУЗЫКА: добавлено в очередь:", t, "| в очереди:", #State.queue)
                ui.musicStatus.Text = "В очереди: " .. #State.queue
            else
                Config.Music[#Config.Music + 1] = { name = "Свой трек", id = t }
                A.playTrack(#Config.Music)
            end
            return
        end
        local low = t:lower()
        for i, tr in ipairs(Config.Music) do
            if tr.name:lower():find(low, 1, true) then A.playTrack(i); return end
        end
        dbg("МУЗЫКА: «" .. t .. "» нет в списке. Для поиска по YouTube открой YouTube Player ниже.")
        ui.musicStatus.Text = "Нет в списке — открой YouTube Player"
    end)
    for i, tr in ipairs(Config.Music) do
        button(pMus, "▶ " .. tr.name, function() A.playTrack(i) end, true)
        input(pMus, "ID / rbxassetid://... / путь к файлу", tr.id, function(t) Config.Music[i].id = t; dbg("МУЗЫКА: ID трека", i, "=", t) end)
    end
    button(pMus, "■ Стоп", function() A.stopMusic() end)
    do
        local vols = { 0.2, 0.5, 0.8, 1 }
        local b
        b = button(pMus, "", function()
            local idx = 1
            for i, v in ipairs(vols) do if v == Config.Volume then idx = i end end
            Config.Volume = vols[idx % #vols + 1]; if sound then sound.Volume = Config.Volume end
            b.Text = "Громкость: " .. Config.Volume .. "  ›"
        end)
        b.Text = "Громкость: " .. Config.Volume .. "  ›"
    end
    -- YouTube Player: ВНЕШНИЙ скрипт с GitHub. Загружается только после второго нажатия (подтверждение).
    local ytBtn
    ytBtn = button(pMus, "Открыть YouTube Player", function()
        if not State.ytArmed then
            State.ytArmed = true
            ytBtn.Text = "⚠ Загрузит внешний скрипт с GitHub — нажми ещё раз"
            task.delay(6, function() State.ytArmed = false; ytBtn.Text = "Открыть YouTube Player" end)
            return
        end
        State.ytArmed = false
        ytBtn.Text = "Открыть YouTube Player"
        dbg("YouTube Player: загружаю", Config.YouTubeURL)
        local ok, err = pcall(function() loadstring(game:HttpGet(Config.YouTubeURL))() end)
        dbg("YouTube Player результат:", ok, err)
    end, true)

    -- ===== Настройки =====
    local pSet = page("Настройки")
    toggle(pSet, "DEBUG (консоль)", "Debug")
    toggle(pSet, "Anti-AFK", "AntiAFK")
    button(pSet, "Найти пустой сервер (1-2 игрока)", function() A.serverHop() end, true)
    input(pSet, "Ручная «скорость» для режима Auto (0 = авто)", tostring(Config.SpeedOverride), function(t) Config.SpeedOverride = U.parseNum(t) or 0 end)
    cycler(pSet, "Запас к скорости", "SpeedMargin", { 1, 1.25, 1.5, 2 })
    cycler(pSet, "Скорость авто-полёта", "FlySpeed", { 50, 80, 120, 200 })
    section(pSet, "Ручные remote-ы (имя или путь, Enter)")
    for _, kind in ipairs({ "equipBest", "sell", "fuse", "delete", "index", "upgrade" }) do
        input(pSet, "remote: " .. kind, Config.RemoteOverrides[kind] or "", function(t)
            Config.RemoteOverrides[kind] = (t ~= "" and t) or nil
            State.remoteCache[kind] = nil
        end)
    end
    button(pSet, "ВЫГРУЗИТЬ СКРИПТ", function() IH.Unload() end, true)

    local order = { "Главная", "Питомцы", "Прогресс", "Хэллоуин", "Игрок", "ESP", "Музыка", "Настройки" }
    for i, n in ipairs(order) do tabBtns[n].LayoutOrder = i end
    selectTab("Главная")

    -- ---------- правая панель «Кража» ----------
    local startBtn = Instance.new("TextButton")
    startBtn.Size = UDim2.new(1, -16, 0, 34); startBtn.Position = UDim2.fromOffset(8, 42); startBtn.Font = Enum.Font.GothamBold
    startBtn.TextSize = 14; startBtn.TextColor3 = Color3.new(1, 1, 1); startBtn.Parent = panel; corner(startBtn, 8)
    function UI.refreshStart()
        startBtn.Text = "Автокража: " .. (State.running and "ВКЛ" or "ВЫКЛ")
        tw(startBtn, 0.15, { BackgroundColor3 = State.running and GREEN or OFF })
    end
    startBtn.MouseButton1Click:Connect(function()
        if State.running then A.stopFarm() else A.startFarm(false) end
        UI.refreshStart()
    end)
    UI.refreshStart()
    ui.count = txt(panel, "Найдено яиц: 0", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(10, 82), 12, false, SUB)

    -- шапка колонок
    local cols = Instance.new("Frame")
    cols.Size = UDim2.new(1, -12, 0, 18); cols.Position = UDim2.fromOffset(6, 100); cols.BackgroundTransparency = 1; cols.Parent = panel
    local function colLabel(text, x, w, xa) txt(cols, text, UDim2.fromOffset(w, 18), UDim2.fromOffset(x, 0), 11, true, SUB, xa) end
    colLabel("Имя", 8, 120); colLabel("Вес", 132, 62); colLabel("Доход", 196, 78); colLabel("Редкость", 276, 90)

    ui.list = Instance.new("ScrollingFrame")
    ui.list.Size = UDim2.new(1, -12, 1, -126); ui.list.Position = UDim2.fromOffset(6, 120); ui.list.BackgroundTransparency = 1
    ui.list.BorderSizePixel = 0; ui.list.ScrollBarThickness = 3; ui.list.AutomaticCanvasSize = Enum.AutomaticSize.Y; ui.list.CanvasSize = UDim2.new()
    ui.list.Parent = panel
    do local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 4); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Parent = ui.list end

    local rows = {}
    function UI.updatePanel()
        local hrp = getHRP()
        local eggs = {}
        for _, e in ipairs(State.eggs) do eggs[#eggs + 1] = e end
        table.sort(eggs, function(a, b)
            local ra, rb = RarityRank[a.data.rarity or ""] or 0, RarityRank[b.data.rarity or ""] or 0
            if ra ~= rb then return ra > rb end
            local ia, ib = a.data.income or 0, b.data.income or 0
            if ia ~= ib then return ia > ib end
            return a.part:GetFullName() < b.part:GetFullName()
        end)
        ui.count.Text = ("Найдено яиц: %d"):format(#eggs)
        local seen = {}
        for i, e in ipairs(eggs) do
            if i > 80 then break end
            seen[e.key] = true
            local r = rows[e.key]
            if not r then
                local f = Instance.new("Frame")
                f.Size = UDim2.new(1, -6, 0, 40); f.BackgroundColor3 = Color3.fromRGB(30, 22, 52); f.BorderSizePixel = 0; f.Parent = ui.list; corner(f, 8)
                local function lb(x, w, ts, bold, xa)
                    return txt(f, "", UDim2.fromOffset(w, 18), UDim2.fromOffset(x, 4), ts, bold, TXT, xa)
                end
                local nm = lb(8, 118, 12, true); nm.TextTruncate = Enum.TextTruncate.AtEnd
                local wt, inc, rar = lb(132, 62, 11), lb(196, 78, 11), lb(276, 90, 11, true)
                local sub = txt(f, "", UDim2.new(1, -96, 0, 14), UDim2.fromOffset(8, 22), 10, false, SUB)
                sub.TextTruncate = Enum.TextTruncate.AtEnd
                local btn = Instance.new("TextButton")
                btn.Size = UDim2.fromOffset(62, 30); btn.Position = UDim2.new(1, -68, 0, 5); btn.BackgroundColor3 = GREEN
                btn.Text = "Красть"; btn.Font = Enum.Font.GothamBold; btn.TextSize = 12; btn.TextColor3 = Color3.new(1, 1, 1); btn.Parent = f; corner(btn, 6)
                r = { frame = f, nm = nm, wt = wt, inc = inc, rar = rar, sub = sub, cur = e }
                btn.MouseButton1Click:Connect(function()
                    State.forced = r.cur
                    dbg("ПАНЕЛЬ: «Красть» →", r.cur.data.name, r.cur.biome)
                    if not State.running then A.startFarm(true) end
                end)
                rows[e.key] = r
            end
            r.cur = e
            local d = e.data
            r.frame.LayoutOrder = i
            r.nm.Text = d.name
            r.wt.Text = d.weight and (U.fmt(d.weight) .. " kg") or "—"
            r.inc.Text = d.incomeText and ("$" .. d.incomeText .. "/s") or (d.income and ("$" .. U.fmt(d.income) .. "/s") or "—")
            r.rar.Text = d.rarity and (RarityRU[d.rarity] or d.rarity) or "Неизвестно"
            r.rar.TextColor3 = RarityColor[d.rarity or ""] or SUB
            r.sub.Text = ("%s · %s · %d studs · %s%s"):format(e.etype == "halloween" and "Хэллоуин" or "обычное", e.biome,
                hrp and math.floor((e.pos - hrp.Position).Magnitude) or 0, e.source or "?", d.mutation and (" · ✦" .. d.mutation) or "")
        end
        for k, r in pairs(rows) do
            if not seen[k] then r.frame:Destroy(); rows[k] = nil end
        end
    end
end

-- ============================== ЗАПУСК ==================================
U.connect(Svc.RunService.Heartbeat, M.heartbeat)
U.connect(Svc.RunService.Stepped, function()
    if (State.noclip or Config.NoClip) and getChar() then
        for _, p in ipairs(getChar():GetDescendants()) do
            if p:IsA("BasePart") then p.CanCollide = false end
        end
    end
end)
U.connect(Svc.UserInputService.JumpRequest, function()
    if Config.InfJump then
        local h = getHum()
        if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)
U.connect(LP.Idled, function()
    if Config.AntiAFK then
        Svc.VirtualUser:CaptureController()
        Svc.VirtualUser:ClickButton2(Vector2.new())
    end
end)
U.connect(LP.CharacterAdded, function()
    task.wait(1.5)
    State.noclip = false; State.moving = false; State.expectCarry = false; State.treadEntered = false
    State.hitAt = nil; State.lastHealth = nil; State.wasRag = false; State.returnSpeed = nil
    M.setFly(false)
    dbg("Респавн: персонаж создан заново")
end)

IH.Unload = function()
    IH.Alive = false
    State.running = false; State.oneShot = false; State.gen += 1; State.noclip = false
    for _, c in ipairs(IH.Conns) do pcall(function() c:Disconnect() end) end
    pcall(M.setFly, false)
    pcall(function() sound:Stop(); sound:Destroy() end)
    pcall(function() if UI.espFolder then UI.espFolder:ClearAllChildren() end end)
    local h = getHum()
    if h then pcall(function() h.WalkSpeed = 16; h.PlatformStand = false end) end
    pcall(function() if UI.gui then UI.gui:Destroy() end end)
    env.IvanHubV12 = nil
    print("[DEBUG] Скрипт выгружен")
end

dbg("Скрипт v8 запущен. Игрок:", LP.Name)
local okGui, errGui = xpcall(UI.build, tb)
if not okGui then print("[DEBUG] ОШИБКА ПОСТРОЕНИЯ GUI:", errGui) end

task.spawn(function()
    local ok, err = xpcall(function()
        for _ = 1, 40 do if getHRP() then break end; task.wait(0.25) end
        State.spawnPos = getHRP() and getHRP().Position
        dbg("Функции экзекьютора: fireproximityprompt =", fireproximityprompt ~= nil, "| fireclickdetector =", fireclickdetector ~= nil,
            "| firetouchinterest =", firetouchinterest ~= nil)
        dbg("Пути: GuardAreas =", W.guardAreas() and "есть" or "НЕТ", "| SafeZone =", W.safeZone("normal") and "есть" or "НЕТ",
            "| HalloweenDimension =", W.hRoot() and "есть" or "нет", "| Plots =", workspace:FindFirstChild("Plots") and "есть" or "НЕТ")
        pcall(A.scanRemotes)
        A.refreshPets()
    end, tb)
    if not ok then dbg("ОШИБКА СТАРТА:", err) end
end)

-- сканер яиц (каждые ScanInterval секунд) + обновление панели
U.loop(function() return Config.ScanInterval end, function()
    W.scan()
    State.scanning = false
    if UI.updatePanel then UI.updatePanel() end
    if UI.refreshStart then UI.refreshStart() end
    if ui.stats then
        local el = os.clock() - (State.t0 or os.clock())
        ui.stats.Text = ("Сдано яиц: %d · неудач: %d · питомцев получено: %d"):format(State.stats.eggs, State.stats.fails, State.stats.pets)
    end
    if ui.hLbl then
        local hz = W.hZoneAt()
        ui.hLbl.Text = "Измерение: " .. (hz and ("ДА — " .. hz) or "нет")
    end
    if not State.running and not State.farming then setStatus(#State.eggs > 0 and "готов (нажми «Автокража»)" or "яиц не найдено") end
end)
U.loop(0.3, A.treadmillTick)
U.loop(6, A.upgradesTick)
U.loop(15, A.indexTick)
U.loop(10, A.petsTick)
U.loop(20, function() if Config.AutoEquipBest and not A.farmBusy() then A.equipBest() end end)
U.loop(30, function() A.refreshPets(); pcall(A.scanRemotes); State.remoteCache = {} end)
U.loop(1.5, A.halloweenTick)
U.loop(1, A.fishingTick)
U.loop(1, A.antiTrapsTick)
U.loop(1.5, E.tick)

end

local okMain, errMain = xpcall(IvanHubMain, function(e)
    return tostring(e) .. " | " .. ((debug and debug.traceback) and debug.traceback("", 2) or "")
end)
if not okMain then print("[DEBUG] КРИТИЧЕСКАЯ ОШИБКА СКРИПТА (моего кода):", errMain) end
