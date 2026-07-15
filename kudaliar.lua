--[[
╔══════════════════════════════════════════════════════════════════════╗
║        CDID AUTO-FARM  |  Jawa Timur  |  Rayfield  |  v7.0        ║
║                                                                      ║
║  WORKFLOW LOOP (tidak pernah rejoin, jalan terus dalam 1 server):   ║
║                                                                      ║
║  ┌─────────────────────────────────────────────────────────────┐    ║
║  │  LANGKAH 1 → Teleport ke Titik A (ambil misi), tunggu 2s   │    ║
║  │  LANGKAH 2 → Teleport ke Titik B, spawn truck              │    ║
║  │  LANGKAH 3 → Auto Enter Vehicle (duduk di DriveSeat)        │    ║
║  │  LANGKAH 4 → Tween melalui 7 waypoint transit B → C        │    ║
║  │  LANGKAH 5 → Sampai Titik C, tunggu 3s → ulangi lagi       │    ║
║  └─────────────────────────────────────────────────────────────┘    ║
║                                                                      ║
║  KOORDINAT:                                                          ║
║  A (34937.21, 135.64, -54576.89) — ambil misi                      ║
║  B (35160.10, 135.64, -54683.03) — spawn truck                     ║
║  C (27153.66, 388.50,  37788.97) — CDID CARGO Surabaya (delivery)  ║
║                                                                      ║
║  ATURAN:                                                             ║
║  • NO REJOIN — TeleportService TIDAK digunakan                      ║
║  • TeleportSpeed = 49.5 stud/s (aman anti-deteksi)                 ║
║  • SafeY +3 stud di setiap titik                                    ║
║  • pcall berlapis per titik & per cycle                             ║
║  • task.spawn untuk farming agar UI tidak freeze                    ║
╚══════════════════════════════════════════════════════════════════════╝
]]

-- ════════════════════════════════════════════════════════════════════
-- BLOK 1 — SERVICES
-- Semua service di-cache di sini, tidak ada yang dipanggil ulang
-- ════════════════════════════════════════════════════════════════════

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local TwnSvc    = game:GetService("TweenService")
local RunSvc    = game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local HttpSvc   = game:GetService("HttpService")
local MktSvc    = game:GetService("MarketplaceService")
local VIM       = game:GetService("VirtualInputManager")

local LP        = Players.LocalPlayer

-- ════════════════════════════════════════════════════════════════════
-- BLOK 2 — KONSTANTA  (tidak berubah selama runtime)
-- ════════════════════════════════════════════════════════════════════

local VERSION       = "7.0-LOOP"
local MAP_NAME      = "Jawa Timur"
local UI_TITLE      = "CDID Jawa Timur"
local UI_SUB        = "Auto-Farm v7  |  No-Rejoin Loop"

local SPEED         = 49.5   -- stud/detik → TweenService duration
local SAFE_Y        = 3      -- offset Y agar tidak tertanam aspal
local CYCLE_DELAY   = 0.2    -- detik antar micro-step dalam loop
local WAIT_A        = 2      -- detik tunggu di Titik A (ambil misi)
local WAIT_C        = 3      -- detik tunggu di Titik C sebelum loop ulang

local WH_MIN        = 300    -- webhook interval minimum (5 menit)
local WH_MAX        = 600    -- webhook interval maksimum (10 menit)

-- ── Tiga titik utama (plus SafeY) ────────────────────────────────

local PT_A = Vector3.new(34937.21, 135.64 + SAFE_Y, -54576.89)  -- ambil misi
local PT_B = Vector3.new(35160.10, 135.64 + SAFE_Y, -54683.03)  -- spawn truck
local PT_C = Vector3.new(27153.66, 388.50 + SAFE_Y,  37788.97)  -- delivery Surabaya

--[[
  ═══════════════════════════════════════════════════════════════════
  KALKULASI 7 WAYPOINT TRANSIT  (Titik B → Titik C)
  ═══════════════════════════════════════════════════════════════════

  B = (35160.10, 135.64, -54683.03)
  C = (27153.66, 388.50,  37788.97)

  Delta XZ = (27153.66-35160.10,  37788.97-(-54683.03))
           = (-8006.44, 92472.00)

  Interpolasi 7 titik pada t = 1/8 … 7/8:

  t    X = 35160.10 + t*(-8006.44)    Z = -54683.03 + t*(92472.00)
  1/8  34160.30                        -43110.53
  2/8  33160.51                        -31538.03
  3/8  32160.72                        -19965.53
  4/8  31160.92                         -8393.03
  5/8  30161.13                          3179.47
  6/8  29161.33                         14751.97
  7/8  28161.54                         26324.47

  Kurva Y (naik melewati dataran → turun menuju Surabaya):
  t=1/8 → 180   (mulai naik dari dataran rendah B)
  t=2/8 → 280   (perbukitan awal)
  t=3/8 → 400   (mendekati pegunungan)
  t=4/8 → 460   (puncak tertinggi)
  t=5/8 → 430   (turunan barat)
  t=6/8 → 420   (plateau menengah)
  t=7/8 → 400   (mendekat elevasi Surabaya 388.50)

  Semua nilai sudah termasuk SAFE_Y di definisi koordinat.
]]

-- Tabel waypoint transit (SafeY ditambahkan di sini)
local TRANSIT = {
    -- [1] t=1/8
    Vector3.new(34160.30, 180.00 + SAFE_Y, -43110.53),
    -- [2] t=2/8
    Vector3.new(33160.51, 280.00 + SAFE_Y, -31538.03),
    -- [3] t=3/8
    Vector3.new(32160.72, 400.00 + SAFE_Y, -19965.53),
    -- [4] t=4/8  ← puncak
    Vector3.new(31160.92, 460.00 + SAFE_Y,  -8393.03),
    -- [5] t=5/8
    Vector3.new(30161.13, 430.00 + SAFE_Y,   3179.47),
    -- [6] t=6/8
    Vector3.new(29161.33, 420.00 + SAFE_Y,  14751.97),
    -- [7] t=7/8
    Vector3.new(28161.54, 400.00 + SAFE_Y,  26324.47),
}

-- ════════════════════════════════════════════════════════════════════
-- BLOK 3 — STATE GLOBAL  (persistent, tidak reset saat re-execute)
-- ════════════════════════════════════════════════════════════════════

getgenv().GS = getgenv().GS or {
    OnFarming     = false,
    StopFarm      = false,
    InfJump       = false,
    TargetEarning = 0,         -- 0 = tidak ada batas
    WebhookURL    = "",
    SelectedJob   = "Office Worker",
    CycleCount    = 0,
}

getgenv().SS = getgenv().SS or {
    StartMoney  = 0,
    FarmStart   = 0,
    LastWebhook = 0,
}

-- ════════════════════════════════════════════════════════════════════
-- BLOK 4 — NETWORK CACHE
-- ════════════════════════════════════════════════════════════════════

local NetEvents = nil
local NetFuncs  = nil

local function CacheNetwork()
    pcall(function()
        local nc = RS:WaitForChild("NetworkContainer", 20)
        if not nc then return end
        NetEvents = nc:FindFirstChild("RemoteEvents")
        NetFuncs  = nc:FindFirstChild("RemoteFunctions")
    end)
end

-- ════════════════════════════════════════════════════════════════════
-- BLOK 5 — HELPER FUNCTIONS
-- Semua helper didefinisikan DI SINI sebelum siapapun memanggilnya
-- ════════════════════════════════════════════════════════════════════

-- Safe FireServer
local function Fire(evName, ...)
    local a = {...}
    pcall(function()
        if not NetEvents then return end
        local ev = NetEvents:FindFirstChild(evName)
        if ev then ev:FireServer(table.unpack(a)) end
    end)
end

-- Safe InvokeServer
local function Invoke(fnName, ...)
    local a = {...}
    local ok, r = pcall(function()
        if not NetFuncs then return nil end
        local fn = NetFuncs:FindFirstChild(fnName)
        if fn then return fn:InvokeServer(table.unpack(a)) end
    end)
    return ok and r or nil
end

-- Hitung durasi Tween dari jarak horizontal
local function TweenDur(fromV3, toV3)
    local dx   = toV3.X - fromV3.X
    local dz   = toV3.Z - fromV3.Z
    local dist = math.sqrt(dx*dx + dz*dz)
    return math.clamp(dist / SPEED, 0.3, 12.0)
end

-- Teleport karakter (instant, tanpa tween) — untuk Titik A & B
local function WarpChar(targetV3)
    pcall(function()
        local char = LP.Character
        if not char then return end
        local hrp  = char:WaitForChild("HumanoidRootPart", 5)
        if not hrp then return end
        hrp.CFrame = CFrame.new(targetV3)
    end)
end

-- Tween kendaraan ke posisi dengan SafeY (dibungkus pcall)
-- Mengembalikan true jika sukses, false jika gagal
local function MoveCar(car, targetV3)
    local success = false
    local ok, err = pcall(function()
        if not car             then error("car nil")         end
        if not car.PrimaryPart then error("PrimaryPart nil") end

        -- targetV3 sudah termasuk SafeY dari PT_A/B/C atau TRANSIT
        local dest = Vector3.new(
            targetV3.X,
            targetV3.Y,
            targetV3.Z
        )

        -- Pertahankan rotasi kendaraan saat ini
        local curCF  = car.PrimaryPart.CFrame
        local rotCF  = curCF - curCF.Position
        local destCF = CFrame.new(dest) * rotCF

        -- Hitung durasi dari posisi kendaraan saat ini
        local dur = TweenDur(car.PrimaryPart.Position, dest)

        -- Tween vehicle dengan TweenService (anti-detect)
        local tween = TwnSvc:Create(
            car.PrimaryPart,
            TweenInfo.new(dur, Enum.EasingStyle.Linear),
            {CFrame = destCF}
        )
        tween:Play()
        tween.Completed:Wait()
        success = true
    end)

    if not ok then
        warn("[MoveCar] Error:", tostring(err))
    end
    return success
end

-- Cek pemain di dalam kendaraan
local function InVehicle()
    local ok, r = pcall(function()
        local char = LP.Character
        if not char then return false end
        local hum  = char:FindFirstChildOfClass("Humanoid")
        return hum ~= nil and hum.SeatPart ~= nil
    end)
    return ok and r == true
end

-- Cari kendaraan milik pemain
local function FindCar()
    local veh = workspace:FindFirstChild("Vehicles")
    if not veh then return nil end
    return veh:FindFirstChild(LP.Name .. "sCar")
end

-- Baca uang dari GUI
local function GetMoney()
    local ok, v = pcall(function()
        local lbl = LP.PlayerGui.Main.Container.Hub
                       .CashFrame.Frame.TextLabel
        return tonumber(lbl.Text:gsub("[^%d]","")) or 0
    end)
    return (ok and type(v)=="number") and v or 0
end

-- Format angka ke string ribuan
local function Fmt(n)
    if type(n) ~= "number" then return "0" end
    return tostring(math.floor(n))
           :reverse():gsub("(%d%d%d)","%%1."):reverse():gsub("^%.","")
end

-- Progress bar ASCII
local function PBar(cur, tgt)
    local W = 18
    if type(tgt)~="number" or tgt<=0 then
        return "[ ∞  Tanpa Batas ]", 0
    end
    local p = math.min(cur/tgt, 1)
    local f = math.floor(p*W)
    return string.format("[%s%s] %.1f%%",
        string.rep("█",f), string.rep("░",W-f), p*100), p*100
end

-- Rekam koordinat saat ini
local function RecordCoord()
    local ok, r = pcall(function()
        local char = LP.Character
        if not char then return "Karakter tidak ada." end
        local hrp  = char:FindFirstChild("HumanoidRootPart")
        if not hrp then return "HRP tidak ada." end
        local p    = hrp.Position
        return string.format("Vector3.new(%.2f, %.2f, %.2f)", p.X, p.Y, p.Z)
    end)
    return (ok and type(r)=="string") and r or "Error."
end

-- ════════════════════════════════════════════════════════════════════
-- BLOK 6 — ANTI-AFK
-- ════════════════════════════════════════════════════════════════════

local AfkConn = nil

local function StartAntiAFK()
    if AfkConn then
        pcall(function() AfkConn:Disconnect() end)
    end
    AfkConn = LP.Idled:Connect(function()
        pcall(function()
            local keys = {"W","A","S","D"}
            local k    = keys[math.random(1,4)]
            VIM:SendKeyEvent(true,  k, false, game)
            task.wait(0.08 + math.random()*0.15)
            VIM:SendKeyEvent(false, k, false, game)
            VIM:SendMouseMoveEvent(
                math.random(-30,30), math.random(-30,30), game)
        end)
    end)
    LP.CharacterAdded:Once(function()
        task.wait(2)
        StartAntiAFK()
    end)
end

-- ════════════════════════════════════════════════════════════════════
-- BLOK 7 — DISCORD WEBHOOK
-- ════════════════════════════════════════════════════════════════════

local function SendWebhook(isTargetReached)
    local url = type(getgenv().GS.WebhookURL)=="string"
                and getgenv().GS.WebhookURL or ""
    if url=="" then return end
    if not getgenv().GS.OnFarming and not isTargetReached then return end

    local now = os.time()
    if not isTargetReached then
        if (now - getgenv().SS.LastWebhook) < WH_MIN then return end
    end
    getgenv().SS.LastWebhook = now

    local money   = GetMoney()
    local earned  = math.max(0, money - getgenv().SS.StartMoney)
    local tgt     = getgenv().GS.TargetEarning or 0
    local bar, _  = PBar(earned, tgt)
    local elapsed = math.floor((now - getgenv().SS.FarmStart)/60)
    local cycles  = getgenv().GS.CycleCount or 0
    local status  = isTargetReached and "✅ TARGET" or "🟢 Farming"
    local color   = isTargetReached and 5832543 or 3066993

    local payload = {embeds={{
        title = isTargetReached and "✅ TARGET TERCAPAI!" or
                "📊 CDID Farm Log — Jawa Timur",
        color = color,
        description = LP.Name.."  (`"..tostring(LP.UserId).."`)",
        fields = {
            {name="⚡ Status",    value=status,              inline=true},
            {name="🗺️ Map",       value=MAP_NAME,            inline=true},
            {name="🔄 Siklus",    value=tostring(cycles),    inline=true},
            {name="⏱️ Durasi",    value=elapsed.." menit",   inline=true},
            {name="💰 Uang",      value="Rp "..Fmt(money),   inline=true},
            {name="📈 Earned",    value="Rp "..Fmt(earned),  inline=true},
            {name="🎯 Target",
             value=tgt>0 and "Rp "..Fmt(tgt) or "—",        inline=true},
            {name="📊 Progress",
             value="```\n"..bar.."\n```",                    inline=false},
        },
        footer={text="CDID v"..VERSION.."  |  "..os.date("%d/%m %H:%M")},
    }}}

    pcall(function()
        local fn = (syn and syn.request)
                or (http and http.request)
                or (typeof(request)=="function" and request)
        if not fn then return end
        fn({
            Url     = url,
            Method  = "POST",
            Headers = {["Content-Type"]="application/json"},
            Body    = HttpSvc:JSONEncode(payload),
        })
    end)
end

-- Background webhook timer
task.spawn(function()
    while task.wait(60) do
        if getgenv().GS.OnFarming then
            local interval = math.random(WH_MIN, WH_MAX)
            if (os.time()-getgenv().SS.LastWebhook) >= interval then
                pcall(SendWebhook, false)
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════
-- BLOK 8 — STATUS UPDATER (forward-safe wrapper)
-- Wrapper ini aman dipanggil SEBELUM UI ada — tidak akan crash
-- Fungsi internalnya akan diisi setelah UI Rayfield terbuat
-- ════════════════════════════════════════════════════════════════════

local _statusFn  = nil   -- diisi setelah UI dibuat
local _stepFn    = nil   -- diisi setelah UI dibuat
local _cycleFn   = nil   -- diisi setelah UI dibuat

local function SetStatus(txt)
    if type(_statusFn)=="function" then pcall(_statusFn, txt) end
    print("[CDID]", tostring(txt))
end

local function SetStep(txt)
    if type(_stepFn)=="function" then pcall(_stepFn, txt) end
end

local function SetCycle(n)
    if type(_cycleFn)=="function" then pcall(_cycleFn, n) end
end

-- ════════════════════════════════════════════════════════════════════
-- BLOK 9 — FARMING ENGINE
-- ════════════════════════════════════════════════════════════════════

-- ── Stop farming ──────────────────────────────────────────────────
local function StopAll(sendAlert)
    getgenv().GS.OnFarming = false
    getgenv().GS.StopFarm  = true
    SetStatus("⏹️ Farming dihentikan.")
    if sendAlert then
        task.spawn(function() pcall(SendWebhook, true) end)
    end
end

-- ── Cek target earning ────────────────────────────────────────────
local function CheckTarget()
    local tgt = getgenv().GS.TargetEarning or 0
    if tgt <= 0 then return false end
    if (GetMoney() - getgenv().SS.StartMoney) >= tgt then
        StopAll(true)
        return true
    end
    return false
end

-- ── Spawn truck & auto-enter vehicle ─────────────────────────────
-- Mengembalikan model kendaraan atau nil jika gagal
local function SpawnTruck()
    -- Tekan F untuk spawn kendaraan
    local function PressF()
        pcall(function()
            VIM:SendKeyEvent(true,  "F", false, game)
            task.wait(0.2)
            VIM:SendKeyEvent(false, "F", false, game)
        end)
    end

    -- Coba via RemoteEvent "SpawnTruck" jika ada
    -- (placeholder — sesuaikan nama RemoteEvent dengan versi game)
    Fire("SpawnTruck", LP.Name)
    task.wait(1)

    -- Fallback: tekan F
    PressF()
    task.wait(4)

    -- Cari kendaraan di workspace
    local car = nil
    for attempt = 1, 18 do
        car = FindCar()
        if car then break end
        PressF()
        task.wait(0.8)
        SetStatus(string.format("🔑 Spawn truck... percobaan %d/18", attempt))
    end

    if not car then
        warn("[SpawnTruck] Kendaraan tidak muncul setelah 18 percobaan.")
        return nil
    end

    -- Auto-enter vehicle: duduk di DriveSeat
    local seat = car:FindFirstChild("DriveSeat")
    if not seat then
        warn("[SpawnTruck] DriveSeat tidak ada.")
        return nil
    end

    SetStatus("🪑 Duduk di kendaraan...")
    pcall(function()
        local char = LP.Character
        if not char then return end
        local hum  = char:WaitForChild("Humanoid", 5)
        if hum then seat:Sit(hum) end
    end)
    task.wait(1.5)

    -- Retry duduk
    for _ = 1, 12 do
        if InVehicle() then break end
        pcall(function()
            local char = LP.Character
            if not char then return end
            local hum  = char:FindFirstChildOfClass("Humanoid")
            if hum then seat:Sit(hum) end
        end)
        task.wait(0.4)
    end

    if not InVehicle() then
        warn("[SpawnTruck] Gagal duduk setelah 12 percobaan.")
        return nil
    end

    return car
end

-- ════════════════════════════════════════════════════════════════════
-- ── LOOP UTAMA FARM (NO REJOIN) ───────────────────────────────────
--
--   Struktur setiap siklus:
--
--   [L1] Teleport karakter ke Titik A
--        → Fire RemoteEvent ambil misi
--        → tunggu WAIT_A detik
--
--   [L2] Teleport karakter ke Titik B
--        → Spawn truck (SpawnTruck)
--        → Auto-enter vehicle
--
--   [L3] Tween truck melalui 7 waypoint transit  (B → Transit[1..7] → C)
--        → Setiap titik dibungkus pcall tersendiri
--        → Jika truck hilang di tengah jalan → abort siklus, ulangi
--
--   [L4] Sampai Titik C
--        → Fire RemoteEvent delivery
--        → tunggu WAIT_C detik
--        → CycleCount++
--        → ULANGI dari [L1] (TIDAK rejoin)
--
-- ════════════════════════════════════════════════════════════════════

local function FarmLoop()
    while task.wait(CYCLE_DELAY) do
        if not getgenv().GS.OnFarming then break end
        if CheckTarget() then break end

        -- Setiap siklus penuh dibungkus pcall
        -- Error satu siklus tidak menghentikan loop
        local cycOk, cycErr = pcall(function()

            local cycle = (getgenv().GS.CycleCount or 0) + 1
            SetStatus(string.format("🔄 Siklus #%d dimulai...", cycle))

            -- ═══════════════════════════════════════════════════════
            -- LANGKAH 1 — Teleport ke Titik A (ambil misi)
            -- ═══════════════════════════════════════════════════════

            SetStatus("📍 [L1] Menuju Titik A — ambil misi...")
            SetStep("A  →  " .. tostring(math.floor(PT_A.X)) ..
                    ", " .. tostring(math.floor(PT_A.Y)) ..
                    ", " .. tostring(math.floor(PT_A.Z)))

            WarpChar(PT_A)
            task.wait(0.3)

            -- Fire RemoteEvent ambil misi (sesuaikan nama event dengan game)
            Fire("Job", "Truck")

            -- Coba fire proximity prompt jika ada di sekitar Titik A
            pcall(function()
                local parts = workspace:GetPartBoundsInBox(
                    CFrame.new(PT_A), Vector3.new(20, 10, 20)
                )
                for _, p in ipairs(parts) do
                    local pp = p:FindFirstChildOfClass("ProximityPrompt")
                             or (p.Parent and p.Parent:FindFirstChildOfClass("ProximityPrompt"))
                    if pp then
                        fireproximityprompt(pp)
                        task.wait(0.2)
                    end
                end
            end)

            SetStatus("⏳ [L1] Tunggu " .. WAIT_A .. " detik (ambil misi)...")
            task.wait(WAIT_A)

            if not getgenv().GS.OnFarming then return end
            if CheckTarget() then return end

            -- ═══════════════════════════════════════════════════════
            -- LANGKAH 2 — Teleport ke Titik B + Spawn Truck
            -- ═══════════════════════════════════════════════════════

            SetStatus("📍 [L2] Menuju Titik B — spawn truck...")
            SetStep("B  →  " .. tostring(math.floor(PT_B.X)) ..
                    ", " .. tostring(math.floor(PT_B.Y)) ..
                    ", " .. tostring(math.floor(PT_B.Z)))

            WarpChar(PT_B)
            task.wait(0.5)

            -- ═══════════════════════════════════════════════════════
            -- LANGKAH 3 — Auto Enter Vehicle
            -- ═══════════════════════════════════════════════════════

            SetStatus("🚛 [L3] Spawn truck & auto-enter vehicle...")
            local car = SpawnTruck()

            if not car then
                SetStatus("❌ [L3] Truck gagal — ulangi siklus.")
                warn("[FarmLoop] SpawnTruck nil, retry cycle.")
                return   -- pcall menangkap, loop lanjut ke siklus berikutnya
            end

            SetStatus("✅ [L3] Duduk di truck berhasil!")
            task.wait(0.5)

            if not getgenv().GS.OnFarming then return end
            if CheckTarget() then return end

            -- ═══════════════════════════════════════════════════════
            -- LANGKAH 4 — Tween B → Transit[1..7] → C
            -- ═══════════════════════════════════════════════════════

            SetStatus("🛣️ [L4] Memulai tween ke Titik C...")

            -- Buat daftar titik penuh: B → transit → C
            -- (B tidak perlu di-tween lagi karena truck sudah di sana)
            local fullRoute = {}
            for _, v in ipairs(TRANSIT) do
                table.insert(fullRoute, v)
            end
            table.insert(fullRoute, PT_C)

            local totalPts = #fullRoute
            local aborted  = false

            for idx, dest in ipairs(fullRoute) do
                if not getgenv().GS.OnFarming then
                    aborted = true
                    break
                end
                if CheckTarget() then
                    aborted = true
                    break
                end

                -- Label titik
                local isTransit  = idx < totalPts
                local pointLabel = isTransit
                    and string.format("Transit %d/%d", idx, totalPts-1)
                    or  "🏁 CDID CARGO Surabaya (C)"

                SetStatus(string.format(
                    "🚛 [L4] %s  (Y=%d)",
                    pointLabel,
                    math.floor(dest.Y)
                ))
                SetStep(string.format(
                    "[%d/%d] X=%.0f Z=%.0f Y=%d",
                    idx, totalPts, dest.X, dest.Z, math.floor(dest.Y)
                ))

                -- Validasi: kendaraan masih ada?
                local currentCar = FindCar()
                if not currentCar then
                    SetStatus("⚠️ [L4] Truck hilang di titik " ..
                              tostring(idx) .. " — abort siklus.")
                    warn("[FarmLoop] FindCar nil di titik "..idx)
                    aborted = true
                    break
                end
                car = currentCar

                -- Validasi: pemain masih duduk?
                if not InVehicle() then
                    SetStatus("⚠️ [L4] Keluar truck — coba masuk ulang...")
                    pcall(function()
                        local s = car:FindFirstChild("DriveSeat")
                        if s then
                            local h = LP.Character
                                   and LP.Character:FindFirstChildOfClass("Humanoid")
                            if h then s:Sit(h) end
                        end
                    end)
                    task.wait(0.8)
                    if not InVehicle() then
                        SetStatus("❌ [L4] Gagal masuk ulang — abort siklus.")
                        aborted = true
                        break
                    end
                end

                -- Gerakkan truck ke titik ini
                -- pcall internal ada di MoveCar, tidak perlu pcall lagi di sini
                local ok = MoveCar(car, dest)
                if not ok then
                    warn(string.format(
                        "[FarmLoop] MoveCar gagal di titik %d — lanjut ke berikutnya.", idx
                    ))
                    -- Tidak abort — coba titik berikutnya
                end

                -- Aksi di titik delivery (Titik C)
                if not isTransit then
                    SetStatus("🏁 [L4] Tiba di Titik C — tunggu reward...")

                    -- Fire RemoteEvent delivery
                    Fire("Job", "Truck")
                    Fire("Delivery", LP.Name)

                    -- Coba fire proximity prompt di sekitar C
                    pcall(function()
                        local parts = workspace:GetPartBoundsInBox(
                            CFrame.new(PT_C), Vector3.new(40, 15, 40)
                        )
                        for _, p in ipairs(parts) do
                            local pp = p:FindFirstChildOfClass("ProximityPrompt")
                                     or (p.Parent and
                                         p.Parent:FindFirstChildOfClass("ProximityPrompt"))
                            if pp then
                                fireproximityprompt(pp)
                                task.wait(0.3)
                            end
                        end
                    end)
                end

                task.wait(CYCLE_DELAY)
            end

            if aborted then
                SetStatus("🔁 Siklus dibatalkan — ulangi dari L1...")
                return
            end

            -- ═══════════════════════════════════════════════════════
            -- LANGKAH 5 — Tunggu di C, lalu ulangi (NO REJOIN)
            -- ═══════════════════════════════════════════════════════

            SetStatus(string.format(
                "⏳ [L5] Tunggu %d detik di Titik C...", WAIT_C
            ))
            task.wait(WAIT_C)

            -- Tambah counter siklus
            getgenv().GS.CycleCount = (getgenv().GS.CycleCount or 0) + 1
            SetCycle(getgenv().GS.CycleCount)
            SetStatus(string.format(
                "✅ Siklus #%d selesai! Ulangi dari Titik A...",
                getgenv().GS.CycleCount
            ))

            -- Tidak ada TeleportService di sini — loop langsung ulang
        end)

        if not cycOk then
            warn("[FarmLoop] Cycle error:", tostring(cycErr))
            SetStatus("⚠️ Error: " .. tostring(cycErr):sub(1, 70))
            pcall(function() RunSvc:Set3dRenderingEnabled(true) end)
            task.wait(3)
        end
    end

    SetStatus("⏹️ Farm loop selesai.")
end

-- ── Side Jobs ─────────────────────────────────────────────────────

local function QuestOffice()
    for _ = 1, 5 do
        if getgenv().GS.StopFarm then break end
        pcall(function()
            local gui  = LP.PlayerGui:FindFirstChild("Job")
            if not gui then return end
            local fr   = gui.Components.Container.Office.Frame
            local box  = fr.TextBox
            local sub  = fr.SubmitButton
            local pts  = fr.Question.Text:split(" ")
            local n1   = tonumber(pts[1])
            local op   = pts[2]
            local n2   = tonumber(pts[3])
            if not (n1 and op and n2) then return end
            local ans  = op=="+" and (n1+n2) or (n1-n2)
            local str  = tostring(math.floor(ans))
            box.Text   = str
            repeat task.wait(CYCLE_DELAY) until box.Text==str
            if sub.Visible then
                local GuiSvc = game:GetService("GuiService")
                GuiSvc.SelectedObject = sub
                VIM:SendKeyEvent(true,  Enum.KeyCode.Return, false, game)
                task.wait()
                VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
                task.wait(CYCLE_DELAY)
                GuiSvc.SelectedObject = nil
            end
        end)
    end
end

local function SideFarm(jobName)
    getgenv().GS.StopFarm = false
    if jobName == "Office Worker" then
        Fire("Job","Office")
        pcall(function()
            LP.Character.HumanoidRootPart.CFrame =
                CFrame.new(-38581, 1039, -62763)
        end)
        task.wait(1)
        for _ = 1, 8 do
            pcall(fireproximityprompt,
                workspace.Etc.Job.Office.Starter.Prompt)
        end
        repeat task.wait(CYCLE_DELAY); QuestOffice()
        until getgenv().GS.StopFarm

    elseif jobName == "Barista" then
        Fire("Job","JanjiJiwa")
        task.spawn(function()
            local pick = Vector3.new(-13716.35, 1052.89, -17997.70)
            local drop = Vector3.new(-13723.75, 1052.89, -17994.23)
            while task.wait(CYCLE_DELAY) and not getgenv().GS.StopFarm do
                pcall(function()
                    fireproximityprompt(
                        workspace.Etc.Job.JanjiJiwa.Starter.Prompt)
                    LP.Character.HumanoidRootPart.CFrame = CFrame.new(pick)
                    task.wait(15)
                    if LP.Backpack:FindFirstChild("Coffee") then
                        LP.Character.HumanoidRootPart.CFrame = CFrame.new(drop)
                        Fire("JanjiJiwa","Delivery")
                    end
                    LP.Character.HumanoidRootPart.CFrame = CFrame.new(pick)
                end)
            end
        end)
    end
end

-- Unlock semua toko
local function UnlockShops()
    local n = 0
    pcall(function()
        for _, d in ipairs(workspace.Etc.Dealership:GetChildren()) do
            local p = d:FindFirstChild("Prompt")
            if p then fireproximityprompt(p); n=n+1; task.wait(0.2) end
        end
    end)
    for _, s in ipairs({
        "KiosMarket","Minimarket","SpeedShop","TuningShop","FuelStation"
    }) do
        pcall(Fire,"OpenShop",s); task.wait(0.12)
    end
    return n
end

-- ════════════════════════════════════════════════════════════════════
-- BLOK 10 — RAYFIELD LOAD & UI
-- Diletakkan TERAKHIR agar semua fungsi di atas sudah terdefinisi
-- ════════════════════════════════════════════════════════════════════

-- Tunggu karakter fully loaded
repeat task.wait(0.1)
until game:IsLoaded() and LP and LP.Character

do
    local hrp = LP.Character:WaitForChild("HumanoidRootPart", 10)
    if not hrp then
        warn("[CDID] HumanoidRootPart timeout. Lanjutkan tetap...")
    end
end

-- ── Load Rayfield ─────────────────────────────────────────────────
local Rayfield = nil

local RF_URLS = {
    -- GitHub raw — paling stabil, tidak melalui CDN pihak ketiga
    "https://raw.githubusercontent.com/shlexware/Rayfield/main/source",
    -- Sirius CDN sebagai fallback
    "https://sirius.menu/rayfield",
}

for i, url in ipairs(RF_URLS) do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(url, true))()
    end)
    if ok and lib ~= nil then
        Rayfield = lib
        print(string.format(
            "[CDID] Rayfield loaded dari URL #%d: %s", i, url
        ))
        break
    end
    warn(string.format("[CDID] URL #%d gagal: %s", i, tostring(lib)))
    task.wait(1.5)
end

-- Guard: jika semua URL gagal, tampilkan error dan berhenti
if not Rayfield then
    warn("[CDID] Library Fail — semua URL tidak bisa dimuat.")
    pcall(function()
        local sg = Instance.new("ScreenGui", LP.PlayerGui)
        sg.Name  = "CDID_ERR"
        sg.ResetOnSpawn = false
        local fr = Instance.new("Frame", sg)
        fr.Size  = UDim2.fromOffset(460, 100)
        fr.Position = UDim2.fromScale(0.5, 0.04)
        fr.AnchorPoint = Vector2.new(0.5, 0)
        fr.BackgroundColor3 = Color3.fromRGB(160, 25, 25)
        Instance.new("UICorner", fr).CornerRadius = UDim.new(0,10)
        local lbl = Instance.new("TextLabel", fr)
        lbl.Size = UDim2.fromScale(1,1)
        lbl.BackgroundTransparency = 1
        lbl.Text = "❌ CDID v"..VERSION..": Rayfield gagal dimuat!\n" ..
                   "Aktifkan HTTP Requests di executor, lalu jalankan ulang."
        lbl.TextColor3 = Color3.new(1,1,1)
        lbl.TextScaled = true
        lbl.Font = Enum.Font.GothamBold
    end)
    return   -- hentikan script dengan bersih
end

-- Cache network setelah Rayfield sukses
CacheNetwork()

-- ── Buat Window ───────────────────────────────────────────────────
local Window = Rayfield:CreateWindow({
    Name            = UI_TITLE,
    LoadingTitle    = UI_TITLE,
    LoadingSubtitle = UI_SUB,
    ConfigurationSaving = { Enabled = false },  -- aman untuk mobile
    Discord   = { Enabled = false },
    KeySystem = false,
})

if not Window then
    warn("[CDID] Window nil. Script dihentikan.")
    return
end

-- Helper notifikasi
local function Notif(title, msg, dur, img)
    pcall(function()
        Rayfield:Notify({
            Title    = tostring(title or UI_TITLE),
            Content  = tostring(msg or ""),
            Duration = tonumber(dur) or 5,
            Image    = tostring(img or "info"),
        })
    end)
end

-- ╔═══════════════════════════════════════╗
-- ║  TAB 1 — HOME                        ║
-- ╚═══════════════════════════════════════╝

local HomeTab = Window:CreateTab("🏠 Home", "home")

HomeTab:CreateSection("Info Pemain")
HomeTab:CreateLabel("👤 "..LP.Name.."   🆔 "..tostring(LP.UserId))
HomeTab:CreateLabel(
    "🗺️ "..MAP_NAME..
    "  ·  ⚡ "..SPEED.." stud/s"..
    "  ·  🛡️ SafeY+"..SAFE_Y
)
HomeTab:CreateLabel("🚫 TeleportService: NONAKTIF (loop dalam 1 server)")

HomeTab:CreateDivider()
HomeTab:CreateSection("Karakter")

HomeTab:CreateSlider({
    Name="Walk Speed", Range={2,250}, Increment=1,
    Suffix=" stud/s", CurrentValue=16, Flag="WalkSpeed",
    Callback=function(v)
        pcall(function() LP.Character.Humanoid.WalkSpeed = v end)
    end,
})

HomeTab:CreateSlider({
    Name="Jump Power", Range={2,200}, Increment=1,
    CurrentValue=50, Flag="JumpPower",
    Callback=function(v)
        pcall(function() LP.Character.Humanoid.JumpHeight = v end)
    end,
})

HomeTab:CreateToggle({
    Name="Infinite Jump", CurrentValue=false, Flag="InfJump",
    Callback=function(v) getgenv().GS.InfJump = v end,
})

UIS.JumpRequest:Connect(function()
    if getgenv().GS.InfJump then
        pcall(function()
            LP.Character:FindFirstChildOfClass("Humanoid"):ChangeState("Jumping")
        end)
    end
end)

HomeTab:CreateToggle({
    Name="No Clip", CurrentValue=false, Flag="NoClip",
    Callback=function(v)
        RunSvc.Stepped:Connect(function()
            if v and LP.Character then
                for _,p in pairs(LP.Character:GetDescendants()) do
                    if p:IsA("BasePart") then p.CanCollide=false end
                end
            end
        end)
    end,
})

HomeTab:CreateToggle({
    Name="Click TP  (CTRL+Klik Kiri)", CurrentValue=false, Flag="ClickTP",
    Callback=function(v)
        UIS.InputBegan:Connect(function(inp)
            if not v then return end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl)
               and inp.UserInputType==Enum.UserInputType.MouseButton1 then
                pcall(function()
                    LP.Character.HumanoidRootPart.CFrame =
                        CFrame.new(LP:GetMouse().Hit.Position
                                   + Vector3.new(0,5,0))
                end)
            end
        end)
    end,
})

-- ╔═══════════════════════════════════════╗
-- ║  TAB 2 — FARMING                     ║
-- ╚═══════════════════════════════════════╝

local FarmTab = Window:CreateTab("🚛 Farming", "truck")

FarmTab:CreateSection("📊 Status Real-Time")

-- Buat semua paragraph SEBELUM mengisi _statusFn / _stepFn / _cycleFn
local statusPara = FarmTab:CreateParagraph({
    Title="Status", Content="Belum dimulai.",
})

local stepPara = FarmTab:CreateParagraph({
    Title="Titik Aktif", Content="—",
})

local cyclePara = FarmTab:CreateParagraph({
    Title="Siklus", Content="0 siklus selesai",
})

local moneyPara = FarmTab:CreateParagraph({
    Title="Uang & Progress", Content="Rp 0",
})

-- Isi _statusFn setelah paragraph ada (nil-safe)
_statusFn = function(txt)
    pcall(function()
        statusPara:Set({ Title="Status", Content=tostring(txt) })
    end)
end

_stepFn = function(txt)
    pcall(function()
        stepPara:Set({ Title="Titik Aktif", Content=tostring(txt) })
    end)
end

_cycleFn = function(n)
    pcall(function()
        cyclePara:Set({
            Title   = "Siklus",
            Content = tostring(n).." siklus selesai",
        })
    end)
end

-- Refresh uang setiap 2 detik (task.spawn agar tidak freeze)
task.spawn(function()
    while task.wait(2) do
        pcall(function()
            local money  = GetMoney()
            local earned = math.max(0, money - getgenv().SS.StartMoney)
            local bar, _ = PBar(earned, getgenv().GS.TargetEarning)
            moneyPara:Set({
                Title="Uang & Progress",
                Content = "💰 Rp "..Fmt(money)..
                          "\n📈 Earned: Rp "..Fmt(earned)..
                          "\n"..bar,
            })
        end)
    end
end)

FarmTab:CreateDivider()
FarmTab:CreateSection("📍 Titik Koordinat")

FarmTab:CreateParagraph({
    Title   = "Titik A — Ambil Misi",
    Content = string.format(
        "X=%.2f\nY=%.2f (sudah dengan SafeY)\nZ=%.2f",
        PT_A.X, PT_A.Y, PT_A.Z
    ),
})

FarmTab:CreateParagraph({
    Title   = "Titik B — Spawn Truck",
    Content = string.format(
        "X=%.2f\nY=%.2f (sudah dengan SafeY)\nZ=%.2f",
        PT_B.X, PT_B.Y, PT_B.Z
    ),
})

FarmTab:CreateParagraph({
    Title   = "Titik C — CDID CARGO Surabaya",
    Content = string.format(
        "X=%.2f\nY=%.2f (sudah dengan SafeY)\nZ=%.2f",
        PT_C.X, PT_C.Y, PT_C.Z
    ),
})

FarmTab:CreateParagraph({
    Title   = "7 Waypoint Transit  (B→C)",
    Content = (function()
        local lines = {}
        for i, v in ipairs(TRANSIT) do
            table.insert(lines, string.format(
                "[%d] Y=%d  X=%.0f Z=%.0f",
                i, math.floor(v.Y), v.X, v.Z
            ))
        end
        return table.concat(lines, "\n")
    end)(),
})

FarmTab:CreateDivider()
FarmTab:CreateSection("⚙️ Konfigurasi")

FarmTab:CreateInput({
    Name="🎯 Target Earning  (Rp, 0 = tidak ada batas)",
    PlaceholderText="0",
    RemoveTextAfterFocusLost=false,
    Flag="TargetInput",
    Callback=function(v)
        local n = tonumber(v)
        if n then
            getgenv().GS.TargetEarning = n
            Notif("Target","Diset ke Rp "..Fmt(n), 4, "check")
        end
    end,
})

FarmTab:CreateDivider()
FarmTab:CreateSection("▶️ Kontrol")

FarmTab:CreateParagraph({
    Title   = "ℹ️ Mode",
    Content = "Loop dalam 1 server (NO REJOIN)\n" ..
              "Urutan: A → B → Spawn → Transit → C → ulang\n" ..
              "TeleportService TIDAK digunakan",
})

FarmTab:CreateToggle({
    Name="🚛  Mulai Auto-Farm  (Loop Mode)",
    CurrentValue=false, Flag="FarmToggle",
    Callback=function(v)
        getgenv().GS.OnFarming = v
        getgenv().GS.StopFarm  = not v

        if v then
            getgenv().SS.StartMoney  = GetMoney()
            getgenv().SS.FarmStart   = os.time()
            getgenv().SS.LastWebhook = 0
            getgenv().GS.CycleCount  = 0
            Notif(
                "Farming",
                "▶️ Loop Farm dimulai!\n"..
                "A→B→Transit→C  |  SafeY+"..SAFE_Y..
                "  |  NO REJOIN\nTarget: Rp "..
                Fmt(getgenv().GS.TargetEarning),
                6, "play"
            )
            -- task.spawn: farming tidak freeze UI
            task.spawn(FarmLoop)
        else
            StopAll(false)
            Notif("Farming","⏹️ Farming dihentikan.",4,"stop")
        end
    end,
})

-- ╔═══════════════════════════════════════╗
-- ║  TAB 3 — SIDE JOBS                   ║
-- ╚═══════════════════════════════════════╝

local JobTab = Window:CreateTab("💼 Side Jobs","briefcase")

JobTab:CreateSection("Pilih Pekerjaan")

local SelJob = getgenv().GS.SelectedJob or "Office Worker"

JobTab:CreateDropdown({
    Name="Job", Options={"Office Worker","Barista"},
    CurrentOption={SelJob}, Flag="JobDD",
    Callback=function(opt)
        SelJob = tostring(opt)
        getgenv().GS.SelectedJob = SelJob
        Notif("Job","Dipilih: "..SelJob, 3,"info")
    end,
})

JobTab:CreateToggle({
    Name="▶️  Mulai Side Job", CurrentValue=false, Flag="SideToggle",
    Callback=function(v)
        if v then
            getgenv().GS.StopFarm = false
            task.spawn(function() SideFarm(SelJob) end)
            Notif("Side Job","Mulai: "..SelJob, 4,"play")
        else
            getgenv().GS.StopFarm = true
            Notif("Side Job","Dihentikan.", 4,"stop")
        end
    end,
})

-- ╔═══════════════════════════════════════╗
-- ║  TAB 4 — TOOLS                       ║
-- ╚═══════════════════════════════════════╝

local ToolTab = Window:CreateTab("🔧 Tools","wrench")

-- Vehicle Sniper
ToolTab:CreateSection("🎯 Vehicle Sniper")
local ls   = RS:FindFirstChild("LimitedStock")
local vList = {}
if ls then
    for _, c in ipairs(ls:GetChildren()) do table.insert(vList,c.Name) end
end
if #vList==0 then vList={"(tidak ada limited stock)"} end

local SelVeh = vList[1]
ToolTab:CreateDropdown({
    Name="Kendaraan", Options=vList, CurrentOption={vList[1]}, Flag="VehDD",
    Callback=function(o) SelVeh=tostring(o) end,
})
ToolTab:CreateButton({
    Name="🛒 Beli Kendaraan Dipilih",
    Callback=function()
        Invoke("Dealership","Buy",SelVeh)
        Notif("Sniper","Membeli: "..SelVeh,4,"cart")
    end,
})
ToolTab:CreateButton({
    Name="🛒 Beli SEMUA Kendaraan",
    Callback=function()
        if ls then
            for _,c in ipairs(ls:GetChildren()) do
                Invoke("Dealership","Buy",c.Name); task.wait(0.3)
            end
            Notif("Sniper","Semua kendaraan dibeli!",4,"check")
        end
    end,
})

-- Dealer
ToolTab:CreateSection("🏪 Dealer & Toko")
local dNames, dPrompts = {}, {}
pcall(function()
    for _,d in ipairs(workspace.Etc.Dealership:GetChildren()) do
        table.insert(dNames,d.Name)
        dPrompts[d.Name] = d:FindFirstChild("Prompt")
    end
end)
if #dNames==0 then dNames={"(tidak ada dealer)"} end

local SelDealer = dNames[1]
ToolTab:CreateDropdown({
    Name="Dealer", Options=dNames, CurrentOption={dNames[1]}, Flag="DealerDD",
    Callback=function(o) SelDealer=tostring(o) end,
})
ToolTab:CreateButton({
    Name="🚪 Buka GUI Dealer",
    Callback=function()
        local p = dPrompts[SelDealer]
        if p then pcall(fireproximityprompt,p); Notif("Dealer","Membuka: "..SelDealer,3,"store")
        else Notif("Dealer","Prompt tidak ditemukan.",4,"alert") end
    end,
})
ToolTab:CreateButton({
    Name="🔓 Unlock SEMUA Toko",
    Callback=function()
        local n = UnlockShops()
        Notif("Shops",tostring(n).." toko dibuka!",5,"check")
    end,
})

-- Box & Slot
ToolTab:CreateSection("📦 Misc")
ToolTab:CreateButton({Name="Claim Box",          Callback=function() Fire("Box","Claim") end})
ToolTab:CreateButton({Name="Gamepass Box",        Callback=function() Fire("Box","Buy","Gamepass Box") end})
ToolTab:CreateButton({Name="⬆️ Upgrade Car Slot", Callback=function() Fire("UpgradeStats","CarSlot") end})

-- ╔═══════════════════════════════════════╗
-- ║  TAB 5 — WEBHOOK                     ║
-- ╚═══════════════════════════════════════╝

local WHTab = Window:CreateTab("📡 Webhook","bell")

WHTab:CreateSection("Discord Config")
WHTab:CreateParagraph({
    Title="Cara Setup",
    Content="1. Discord → Edit Channel → Integrations → Webhooks\n"..
            "2. Buat webhook → Copy URL\n"..
            "3. Paste di input bawah → Enter untuk simpan\n"..
            "4. Log otomatis dikirim tiap 5–10 menit saat farming",
})
WHTab:CreateInput({
    Name="Webhook URL",
    PlaceholderText="https://discord.com/api/webhooks/...",
    RemoveTextAfterFocusLost=false, Flag="WHInput",
    Callback=function(v)
        getgenv().GS.WebhookURL = tostring(v)
        Notif("Webhook","✅ URL disimpan!",4,"check")
    end,
})
WHTab:CreateButton({
    Name="📤 Test Webhook",
    Callback=function()
        local bk = getgenv().GS.OnFarming
        getgenv().GS.OnFarming   = true
        getgenv().SS.StartMoney  = GetMoney() - 55555
        getgenv().SS.FarmStart   = os.time() - 240
        getgenv().SS.LastWebhook = 0
        pcall(SendWebhook, false)
        getgenv().GS.OnFarming = bk
        Notif("Webhook","Test dikirim — cek Discord!",5,"bell")
    end,
})
WHTab:CreateButton({
    Name="✅ Test Alert Target Reached",
    Callback=function()
        getgenv().SS.LastWebhook = 0
        pcall(SendWebhook, true)
        Notif("Webhook","Alert dikirim!",5,"check")
    end,
})

-- ╔═══════════════════════════════════════╗
-- ║  TAB 6 — DEVELOPER                   ║
-- ╚═══════════════════════════════════════╝

local DevTab = Window:CreateTab("🛠️ Developer","code")

DevTab:CreateSection("📍 Coordinate Recorder")
DevTab:CreateParagraph({
    Title="Cara Pakai",
    Content="1. Pindah karakter ke posisi yang ingin direkam\n"..
            "2. Klik 'Ambil Koordinat'\n"..
            "3. Koordinat tampil di label & disalin ke clipboard\n"..
            "4. Paste ke TRANSIT atau PT_A/B/C di bagian KONSTANTA",
})

local CoordLbl = DevTab:CreateLabel("📍 Koordinat: (belum direkam)")

DevTab:CreateButton({
    Name="📍 Ambil Koordinat Sekarang",
    Callback=function()
        local coord = RecordCoord()
        pcall(function() CoordLbl:Set("📍 "..coord) end)
        pcall(function()
            if setclipboard then
                setclipboard(coord)
                Notif("Coord","✅ Disalin!\n"..coord, 7,"copy")
            else
                Notif("Coord", coord, 8,"info")
            end
        end)
        print("[CoordRecorder]", coord)
    end,
})

DevTab:CreateSection("🗺️ Rute Aktif")
DevTab:CreateLabel(string.format(
    "A (Misi):   (%.0f, %.0f, %.0f)",
    PT_A.X, PT_A.Y, PT_A.Z
))
DevTab:CreateLabel(string.format(
    "B (Spawn):  (%.0f, %.0f, %.0f)",
    PT_B.X, PT_B.Y, PT_B.Z
))
for i, v in ipairs(TRANSIT) do
    DevTab:CreateLabel(string.format(
        "T%d/7:       (%.0f, Y:%d, %.0f)",
        i, v.X, math.floor(v.Y), v.Z
    ))
end
DevTab:CreateLabel(string.format(
    "C (Delivery):(%.0f, %.0f, %.0f)",
    PT_C.X, PT_C.Y, PT_C.Z
))

DevTab:CreateDivider()
DevTab:CreateSection("🧪 Test Koordinat")
DevTab:CreateParagraph({
    Title="Cara Test",
    Content="1. Pilih titik dari dropdown\n"...
            "2. Klik 'TP ke Titik' untuk teleport karakter\n"...
            "3. Atau klik 'Test Tween Truck' jika sudah punya truck\n"...
            "4. Cek apakah koordinat masih akurat",
})

local TestPoints = {
    ["A - Ambil Misi"] = PT_A,
    ["B - Spawn Truck"] = PT_B,
    ["C - Delivery Surabaya"] = PT_C,
    ["Transit 1/7"] = TRANSIT[1],
    ["Transit 2/7"] = TRANSIT[2],
    ["Transit 3/7"] = TRANSIT[3],
    ["Transit 4/7 (puncak)"] = TRANSIT[4],
    ["Transit 5/7"] = TRANSIT[5],
    ["Transit 6/7"] = TRANSIT[6],
    ["Transit 7/7"] = TRANSIT[7],
}

local SelTestPoint = "A - Ambil Misi"

DevTab:CreateDropdown({
    Name="Pilih Titik",
    Options={
        "A - Ambil Misi",
        "B - Spawn Truck",
        "C - Delivery Surabaya",
        "Transit 1/7",
        "Transit 2/7",
        "Transit 3/7",
        "Transit 4/7 (puncak)",
        "Transit 5/7",
        "Transit 6/7",
        "Transit 7/7",
    },
    CurrentOption={"A - Ambil Misi"},
    Flag="TestPointDD",
    Callback=function(opt)
        SelTestPoint = tostring(opt)
        local pos = TestPoints[SelTestPoint]
        Notif(
            "Test Point",
            string.format(
                "Dipilih: %s\nX=%.0f Y=%.0f Z=%.0f",
                SelTestPoint, pos.X, pos.Y, pos.Z
            ),
            5, "map-pin"
        )
    end,
})

DevTab:CreateButton({
    Name="📍 TP ke Titik (Karakter)",
    Callback=function()
        local pos = TestPoints[SelTestPoint]
        if not pos then
            Notif("Test","Titik tidak ditemukan!",3,"alert")
            return
        end
        WarpChar(pos)
        Notif(
            "Test TP",
            string.format(
                "✅ Teleport ke %s\nX=%.0f Y=%.0f Z=%.0f",
                SelTestPoint, pos.X, pos.Y, pos.Z
            ),
            5, "check"
        )
        print(string.format(
            "[TestCoord] Teleported to %s: (%.2f, %.2f, %.2f)",
            SelTestPoint, pos.X, pos.Y, pos.Z
        ))
    end,
})

DevTab:CreateButton({
    Name="🚚 Test Tween Truck",
    Callback=function()
        local pos = TestPoints[SelTestPoint]
        if not pos then
            Notif("Test","Titik tidak ditemukan!",3,"alert")
            return
        end
        
        local car = FindCar()
        if not car then
            Notif("Test","❌ Truck tidak ditemukan!\nSpawn truck terlebih dahulu.",5,"alert")
            return
        end
        
        if not InVehicle() then
            Notif("Test","⚠️ Kamu tidak duduk di truck!",4,"alert")
            return
        end
        
        Notif(
            "Test Tween",
            string.format(
                "⏳ Tween truck ke %s...\nX=%.0f Y=%.0f Z=%.0f",
                SelTestPoint, pos.X, pos.Y, pos.Z
            ),
            5, "truck"
        )
        
        task.spawn(function()
            local ok = MoveCar(car, pos)
            if ok then
                Notif(
                    "Test Tween",
                    "✅ Tween selesai!\nCek apakah truck jatuh atau aman.",
                    6, "check"
                )
                print(string.format(
                    "[TestCoord] Tween to %s: SUCCESS",
                    SelTestPoint
                ))
            else
                Notif(
                    "Test Tween",
                    "❌ Tween gagal!\nCek console untuk error.",
                    5, "alert"
                )
                print(string.format(
                    "[TestCoord] Tween to %s: FAILED",
                    SelTestPoint
                ))
            end
        end)
    end,
})

DevTab:CreateButton({
    Name="🔄 Test Full Route (A→B→Transit→C)",
    Callback=function()
        Notif(
            "Test Route",
            "⚠️ Mode debug aktif!\nScript akan test semua titik:\nA → B → 7 Transit → C",
            7, "route"
        )
        
        task.spawn(function()
            -- Test TP ke A
            SetStatus("🧪 [TEST] TP ke A...")
            WarpChar(PT_A)
            task.wait(2)
            
            -- Test TP ke B
            SetStatus("🧪 [TEST] TP ke B...")
            WarpChar(PT_B)
            task.wait(2)
            
            -- Spawn truck
            SetStatus("🧪 [TEST] Spawn truck...")
            local car = SpawnTruck()
            if not car then
                Notif("Test Route","❌ Truck gagal spawn!",5,"alert")
                SetStatus("❌ Test dibatalkan.")
                return
            end
            task.wait(2)
            
            -- Test tween semua transit + C
            local allPoints = {}
            for i, v in ipairs(TRANSIT) do
                table.insert(allPoints, {label = "Transit "..i.."/7", pos = v})
            end
            table.insert(allPoints, {label = "C (Delivery)", pos = PT_C})
            
            for idx, data in ipairs(allPoints) do
                if not InVehicle() then
                    Notif("Test Route","⚠️ Keluar dari truck!",4,"alert")
                    break
                end
                
                SetStatus(string.format(
                    "🧪 [TEST] Tween ke %s (%d/%d)...",
                    data.label, idx, #allPoints
                ))
                
                local ok = MoveCar(car, data.pos)
                if not ok then
                    Notif(
                        "Test Route",
                        string.format("❌ Gagal di %s!", data.label),
                        5, "alert"
                    )
                    SetStatus("❌ Test dibatalkan.")
                    return
                end
                
                task.wait(1)
            end
            
            Notif(
                "Test Route",
                "✅ Test selesai!\nSemua koordinat berhasil.\nJika truck jatuh = Y salah.",
                8, "check"
            )
            SetStatus("✅ Test route selesai.")
        end)
    end,
})

DevTab:CreateDivider()
DevTab:CreateSection("Dev Tools")
DevTab:CreateButton({Name="Dex Explorer",
    Callback=function()
        pcall(function()
            loadstring(game:HttpGet(
                "https://raw.githubusercontent.com/infyiff/backup/main/dex.lua",true))()
        end)
    end,
})
DevTab:CreateButton({Name="Simple Spy",
    Callback=function()
        pcall(function()
            loadstring(game:HttpGet(
                "https://github.com/exxtremestuffs/SimpleSpySource/raw/master/SimpleSpy.lua",true))()
        end)
    end,
})

-- ╔═══════════════════════════════════════╗
-- ║  TAB 7 — SETTINGS                    ║
-- ╚═══════════════════════════════════════╝

local SettTab = Window:CreateTab("⚙️ Settings","settings")

SettTab:CreateSection("ℹ️ Spesifikasi Script")
SettTab:CreateParagraph({
    Title="Info Teknis",
    Content="Versi           : "..VERSION.."\n"..
            "UI Library      : Rayfield (GitHub Raw)\n"..
            "Config Saving   : Nonaktif (aman mobile)\n"..
            "TeleportSpeed   : "..SPEED.." stud/s\n"..
            "SafeY Offset    : +"..SAFE_Y.." stud\n"..
            "Titik Transit   : "..tostring(#TRANSIT).." waypoint\n"..
            "Wait di A       : "..WAIT_A.." detik\n"..
            "Wait di C       : "..WAIT_C.." detik\n"..
            "TeleportService : NONAKTIF (no-rejoin)\n"..
            "Error Handling  : pcall berlapis\n"..
            "task.spawn      : farming + side job\n"..
            "Anti-AFK        : VirtualInputManager",
})

SettTab:CreateSection("Private Server")
SettTab:CreateButton({
    Name="📋 Buat Private Code",
    Callback=function() Fire("PrivateServer","Create")
        Notif("PS","Membuat private code...",4,"info") end,
})

-- ════════════════════════════════════════════════════════════════════
-- BLOK 11 — INIT TASKS
-- ════════════════════════════════════════════════════════════════════

StartAntiAFK()

-- Validasi map (async)
task.spawn(function()
    local ok, info = pcall(function()
        return MktSvc:GetProductInfo(game.PlaceId)
    end)
    if ok and info then
        local name = tostring(info.Name or "")
        local good = name:find("Timur",1,true)
                  or name:find("Car Driving",1,true)
                  or name:find("CDID",1,true)
        if good then
            Notif("✅ Map OK","Terdeteksi: "..name, 5,"check")
        else
            Notif("⚠️ Perhatian",
                "Map: "..name.."\nPastikan kamu di Jawa Timur!", 7,"alert")
        end
    end
end)

print(string.format(
    "[CDID v%s] Ready | Speed=%.1f | SafeY=+%d | Transit=%d | NO-REJOIN",
    VERSION, SPEED, SAFE_Y, #TRANSIT
))
