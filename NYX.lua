-- file: NYX.lua
-- runtime: Roblox Luau (Client-Side / Executor or LocalScript)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

local Config = {
    MaxWalkSpeed = 24.0,
    MaxJumpPower = 60.0,
    MaxHorizontalVelocity = 45.0,
    MaxTeleportDelta = 35.0,
    MaxAirborneSeconds = 3.5,
    ScanInterval = 0.25,
    StrictKick = true,
}

local State = {
    LastPosition = nil,
    LastTick = os.clock(),
    AirborneTimer = 0.0,
    Violations = 0,
    MaxViolations = 3,
    Running = true,
}

local function FlagViolation(reason, detail)
    State.Violations += 1
    warn(string.format("[NYX-AC] Violation (%d/%d): %s | %s", State.Violations, State.MaxViolations, reason, tostring(detail)))
    if Config.StrictKick and State.Violations >= State.MaxViolations then
        State.Running = false
        LocalPlayer:Kick(string.format("NYX Integrity Violation: %s", reason))
    end
end

local function CheckMetatableIntegrity()
    local ok = pcall(function()
        local mt = getrawmetatable and getrawmetatable(game) or nil
        if mt and isreadonly and not isreadonly(mt) then
            FlagViolation("Metatable Unlocked", "game metatable is writable")
        end
    end)
    if not ok then
        return
    end
end

local function ValidateCharacter(character, dt)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart or humanoid.Health <= 0 then
        State.LastPosition = nil
        State.AirborneTimer = 0.0
        return
    end

    if humanoid.WalkSpeed > Config.MaxWalkSpeed + 0.5 then
        FlagViolation("WalkSpeed Tamper", humanoid.WalkSpeed)
        humanoid.WalkSpeed = 16.0
    end

    if humanoid.UseJumpPower and humanoid.JumpPower > Config.MaxJumpPower + 0.5 then
        FlagViolation("JumpPower Tamper", humanoid.JumpPower)
        humanoid.JumpPower = 50.0
    end

    local currentPos = rootPart.Position
    local velocity = rootPart.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

    if horizontalSpeed > Config.MaxHorizontalVelocity and humanoid:GetState() ~= Enum.HumanoidStateType.FallingDown then
        FlagViolation("Velocity Exceeded", string.format("%.2f studs/s", horizontalSpeed))
    end

    if State.LastPosition then
        local deltaXZ = (Vector3.new(currentPos.X, 0, currentPos.Z) - Vector3.new(State.LastPosition.X, 0, State.LastPosition.Z)).Magnitude
        local maxAllowedStep = math.max(Config.MaxTeleportDelta, (Config.MaxHorizontalVelocity * dt) * 2.2)
        if deltaXZ > maxAllowedStep then
            FlagViolation("Position Desync / Teleport", string.format("Delta: %.2f studs", deltaXZ))
            rootPart.CFrame = CFrame.new(State.LastPosition)
            return
        end
    end

    local floorState = humanoid.FloorMaterial
    if floorState == Enum.Material.Air then
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = { character }
        rayParams.FilterType = Enum.RaycastFilterType.Exclude

        local hit = Workspace:Raycast(currentPos, Vector3.new(0, -12, 0), rayParams)
        if not hit and velocity.Y >= -2.0 then
            State.AirborneTimer += dt
            if State.AirborneTimer > Config.MaxAirborneSeconds then
                FlagViolation("Sustained Flight / Float", string.format("Airborne %.2fs", State.AirborneTimer))
                State.AirborneTimer = 0.0
            end
        else
            State.AirborneTimer = math.max(0.0, State.AirborneTimer - dt)
        end
    else
        State.AirborneTimer = 0.0
    end

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BodyGyro") or part:IsA("BodyVelocity") or part:IsA("BodyPosition") then
            FlagViolation("UnauthorizedMover", part.Name)
            part:Destroy()
        end
    end

    State.LastPosition = currentPos
end

local accumulator = 0.0
local connection
connection = RunService.Heartbeat:Connect(function(dt)
    if not State.Running then
        if connection then
            connection:Disconnect()
        end
        return
    end

    accumulator += dt
    if accumulator < Config.ScanInterval then
        return
    end

    local stepDt = accumulator
    accumulator = 0.0

    CheckMetatableIntegrity()

    local character = LocalPlayer.Character
    if character then
        ValidateCharacter(character, stepDt)
    end
end)
print("[NYX-AC] Active and monitoring client state.")
print("[NYX-AC] Active and monitoring client state.")
