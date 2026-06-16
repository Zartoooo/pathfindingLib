-- credits to sigmaguyman420 on dc

--[[
    MatchaRaycast - Pure Luau Raycasting Library for Matcha
    
    A fully external raycasting implementation that requires no C++ bridge.
    Uses spatial grid partitioning and property caching for high performance.
    
    Version: 1.0.0
    
    USAGE:
        local Raycaster = loadstring(game:HttpGet("YOUR_URL_HERE"))()
        
        local player = game:GetService("Players").LocalPlayer
        local character = player.Character
        local hrp = character:FindFirstChild("HumanoidRootPart")
        local ignore = Raycaster:GatherParts(character)
        
        -- Basic raycast (Roblox-style, length from direction magnitude)
        local result = Raycaster:Raycast(hrp.Position, Vector3.new(0, -500, 0), ignore)
        
        -- Raycast with explicit max distance
        local result = Raycaster:Raycast(hrp.Position, Vector3.new(0, -1, 0), ignore, 1000)
        
        -- Raycast toward a target position
        local result = Raycaster:RaycastTo(hrp.Position, targetPosition, ignore)
        
        if result then
            print(result.Instance, result.Position, result.Normal, result.Distance)
        end
    
    API:
        Raycaster:Raycast(origin, direction, ignoreList?, maxDistance?) -> RaycastResult?
            Casts a ray from origin in direction. If maxDistance is nil, ray length
            equals direction.Magnitude. Otherwise, direction is normalized and the
            ray extends to maxDistance studs.
        
        Raycaster:RaycastTo(origin, target, ignoreList?, maxDistance?) -> RaycastResult?
            Casts a ray from origin toward target. If maxDistance is provided, the
            ray length is capped at maxDistance.
        
        Raycaster:GatherParts(instance) -> {Instance}
            Recursively collects all BaseParts under an instance. Useful for ignore lists.
        
        Raycaster:RefreshCache() -> nil
            Forces a rebuild of the internal spatial cache.
        
        Raycaster:SetGridSize(size) -> nil
            Sets spatial grid cell size in studs. Default: 64. Range: 32-256.
        
        Raycaster:SetCacheRefreshRate(seconds) -> nil
            Sets how often the cache auto-rebuilds. Default: 10. Set to 0 to disable.
        
        Raycaster:SetDefaultMaxDistance(distance) -> nil
            Sets a global default max ray distance. Default: math.huge.
    
    RaycastResult:
        Instance: Instance  - The part that was hit
        Position: Vector3   - World position of the hit point
        Normal:   Vector3   - Surface normal at the hit point
        Distance: number    - Distance from origin to hit point
    
    NOTES:
        - Treats all parts as oriented bounding boxes (Block shape).
          Spheres, cylinders, and meshes are approximated by their bounding box.
        - Internally caps ray length at 100,000 studs to prevent infinite loops
          with math.huge. This is far beyond any practical Roblox map.
        - Cache rebuilds are expensive (~200-400ms for 1000+ parts) due to
          Matcha's slow property access. Tune CacheRefreshRate accordingly.
        - For dynamic objects (moving parts, players), call RefreshCache() before
          raycasting against them, or use a lower refresh rate.
    
    PERFORMANCE:
        Typical: ~0.4ms per raycast (1000+ part maps)
        Allows ~40+ raycasts per frame at 60 FPS
--]]

local Raycaster = {}
Raycaster.__index = Raycaster

-- ==========================================
-- CONFIGURATION (modifiable via setters)
-- ==========================================

local GRID_SIZE = 64
local CACHE_REFRESH_RATE = 10
local DEFAULT_MAX_DISTANCE = math.huge
local MAX_EFFECTIVE_DISTANCE = 100000  -- Safety cap to prevent math.huge infinite loops

-- Supported part classes (since :IsA() is unreliable in Matcha)
local BASE_PART_CLASSES = {
    Part = true,
    MeshPart = true,
    UnionOperation = true,
    WedgePart = true,
    CornerWedgePart = true,
    TrussPart = true,
    SpawnLocation = true,
    Seat = true,
    VehicleSeat = true,
}

-- ==========================================
-- INTERNAL STATE
-- ==========================================

local Cache = {
    entries = {},
    grid = {},
    lastBuild = 0,
}

-- ==========================================
-- INTERNAL HELPERS
-- ==========================================

local function cellKey(cx, cy, cz)
    return cx * 73856093 + cy * 19349663 + cz * 83492791
end

local function worldToCell(x, y, z, cellSize)
    return math.floor(x / cellSize), math.floor(y / cellSize), math.floor(z / cellSize)
end

local function buildCache()
    local entries = {}
    local grid = {}
    local cellSize = GRID_SIZE
    
    local descendants = workspace:GetDescendants()
    
    for i = 1, #descendants do
        local child = descendants[i]
        if BASE_PART_CLASSES[child.ClassName] then
            local cf = child.CFrame
            local sz = child.Size
            
            if cf and sz then
                local pos = child.Position
                local radius = sz.Magnitude * 0.5
                
                local entry = {
                    instance = child,
                    address = child.Address,
                    cframe = cf,
                    size = sz,
                    posX = pos.X,
                    posY = pos.Y,
                    posZ = pos.Z,
                    radius = radius,
                }
                
                entries[#entries + 1] = entry
                
                local minX, minY, minZ = worldToCell(pos.X - radius, pos.Y - radius, pos.Z - radius, cellSize)
                local maxX, maxY, maxZ = worldToCell(pos.X + radius, pos.Y + radius, pos.Z + radius, cellSize)
                
                for cx = minX, maxX do
                    for cy = minY, maxY do
                        for cz = minZ, maxZ do
                            local key = cellKey(cx, cy, cz)
                            local bucket = grid[key]
                            if not bucket then
                                bucket = {}
                                grid[key] = bucket
                            end
                            bucket[#bucket + 1] = entry
                        end
                    end
                end
            end
        end
    end
    
    Cache.entries = entries
    Cache.grid = grid
    Cache.lastBuild = tick()
end

local function ensureCache()
    if #Cache.entries == 0 or (CACHE_REFRESH_RATE > 0 and tick() - Cache.lastBuild > CACHE_REFRESH_RATE) then
        buildCache()
    end
end

-- Ray vs Oriented Bounding Box intersection using the slab method
local function rayIntersectOBB(origin, direction, cframe, size)
    local localOrigin = cframe:PointToObjectSpace(origin)
    local localDir = cframe:VectorToObjectSpace(direction)

    local halfX = size.X * 0.5
    local halfY = size.Y * 0.5
    local halfZ = size.Z * 0.5
    
    local tMin = -math.huge
    local tMax = math.huge
    local hitAxis = 1
    local hitSign = 1

    -- X axis slab
    local o, d, hs = localOrigin.X, localDir.X, halfX
    if math.abs(d) < 1e-8 then
        if o < -hs or o > hs then return nil end
    else
        local t1 = (-hs - o) / d
        local t2 = (hs - o) / d
        local sign = -1
        if t1 > t2 then t1, t2 = t2, t1; sign = 1 end
        if t1 > tMin then tMin = t1; hitAxis = 1; hitSign = sign end
        if t2 < tMax then tMax = t2 end
        if tMin > tMax then return nil end
    end
    
    -- Y axis slab
    o, d, hs = localOrigin.Y, localDir.Y, halfY
    if math.abs(d) < 1e-8 then
        if o < -hs or o > hs then return nil end
    else
        local t1 = (-hs - o) / d
        local t2 = (hs - o) / d
        local sign = -1
        if t1 > t2 then t1, t2 = t2, t1; sign = 1 end
        if t1 > tMin then tMin = t1; hitAxis = 2; hitSign = sign end
        if t2 < tMax then tMax = t2 end
        if tMin > tMax then return nil end
    end
    
    -- Z axis slab
    o, d, hs = localOrigin.Z, localDir.Z, halfZ
    if math.abs(d) < 1e-8 then
        if o < -hs or o > hs then return nil end
    else
        local t1 = (-hs - o) / d
        local t2 = (hs - o) / d
        local sign = -1
        if t1 > t2 then t1, t2 = t2, t1; sign = 1 end
        if t1 > tMin then tMin = t1; hitAxis = 3; hitSign = sign end
        if t2 < tMax then tMax = t2 end
        if tMin > tMax then return nil end
    end

    if tMax < 0 or tMin > 1 then return nil end
    local t = tMin >= 0 and tMin or tMax
    if t > 1 then return nil end

    local nx = hitAxis == 1 and hitSign or 0
    local ny = hitAxis == 2 and hitSign or 0
    local nz = hitAxis == 3 and hitSign or 0
    
    return t, origin + direction * t, cframe:VectorToWorldSpace(Vector3.new(nx, ny, nz))
end

-- ==========================================
-- PUBLIC API
-- ==========================================

--[[
    Performs a raycast from `origin` along `direction`.
    
    If `maxDistance` is provided, the ray will be `maxDistance` studs long
    (direction is normalized internally).
    
    If `maxDistance` is nil, the ray length equals `direction.Magnitude`
    (Roblox-style behavior).
    
    @param origin Vector3 - Starting point of the ray
    @param direction Vector3 - Direction of the ray
    @param ignoreList {Instance}? - Optional list of parts to ignore
    @param maxDistance number? - Optional explicit ray length in studs
    @return RaycastResult? - Hit info, or nil if nothing was hit
]]
function Raycaster:Raycast(origin, direction, ignoreList, maxDistance)
    ensureCache()
    
    local cellSize = GRID_SIZE
    local grid = Cache.grid
    
    -- Determine ray length and unit direction
    local dirMag = direction.Magnitude
    if dirMag == 0 then return nil end
    
    local rayUnit = direction / dirMag
    local rayLength
    
    if maxDistance then
        rayLength = maxDistance
    else
        rayLength = math.min(dirMag, DEFAULT_MAX_DISTANCE)
    end
    
    if rayLength <= 0 then return nil end
    
    -- Cap effective length to prevent infinite loops with math.huge
    local effectiveLength = math.min(rayLength, MAX_EFFECTIVE_DISTANCE)
    
    local scaledDir = rayUnit * effectiveLength
    
    -- Build ignore dictionary using Address (stable identifier in Matcha)
    local ignoreDict = {}
    if ignoreList then
        for i = 1, #ignoreList do
            local p = ignoreList[i]
            if p then
                ignoreDict[p.Address] = true
            end
        end
    end
    
    local stepSize = cellSize * 0.5
    local numSteps = math.ceil(effectiveLength / stepSize)
    
    local seen = {}
    local closestResult = nil
    local closestT = math.huge
    local ox, oy, oz = origin.X, origin.Y, origin.Z
    local dx, dy, dz = rayUnit.X, rayUnit.Y, rayUnit.Z

    for i = 0, numSteps do
        local t = i * stepSize
        if t > effectiveLength then t = effectiveLength end
        
        local px = ox + dx * t
        local py = oy + dy * t
        local pz = oz + dz * t
        
        local cx, cy, cz = worldToCell(px, py, pz, cellSize)
        local key = cellKey(cx, cy, cz)
        local bucket = grid[key]
        
        if bucket then
            for j = 1, #bucket do
                local entry = bucket[j]
                local addr = entry.address
                
                if not seen[addr] and not ignoreDict[addr] then
                    seen[addr] = true
                    
                    -- Bounding sphere pre-check using cached numbers
                    local pdx = entry.posX - ox
                    local pdy = entry.posY - oy
                    local pdz = entry.posZ - oz
                    local proj = pdx * dx + pdy * dy + pdz * dz
                    local radius = entry.radius
                    
                    if proj > -radius and proj < effectiveLength + radius then
                        local clamped = proj < 0 and 0 or (proj > effectiveLength and effectiveLength or proj)
                        local cpx = ox + dx * clamped
                        local cpy = oy + dy * clamped
                        local cpz = oz + dz * clamped
                        local diffX = entry.posX - cpx
                        local diffY = entry.posY - cpy
                        local diffZ = entry.posZ - cpz
                        local distSq = diffX*diffX + diffY*diffY + diffZ*diffZ
                        
                        if distSq <= radius * radius then
                            local hitT, hitPos, hitNormal = rayIntersectOBB(origin, scaledDir, entry.cframe, entry.size)
                            if hitT and hitT < closestT then
                                closestT = hitT
                                closestResult = {
                                    Instance = entry.instance,
                                    Position = hitPos,
                                    Normal = hitNormal,
                                    Distance = effectiveLength * hitT,
                                }
                            end
                        end
                    end
                end
            end
        end
        
        -- Early exit: stop walking once we've found a hit closer than the current step
        if closestResult and t > closestT * effectiveLength then
            break
        end
    end

    return closestResult
end

--[[
    Performs a raycast from `origin` toward `target`.
    Equivalent to Raycast(origin, target - origin, ignoreList, maxDistance).
    
    @param origin Vector3 - Starting point
    @param target Vector3 - Target position
    @param ignoreList {Instance}? - Optional list of parts to ignore
    @param maxDistance number? - Optional max distance cap
    @return RaycastResult? - Hit info, or nil if nothing was hit
]]
function Raycaster:RaycastTo(origin, target, ignoreList, maxDistance)
    return self:Raycast(origin, target - origin, ignoreList, maxDistance)
end

--[[
    Recursively gathers all BaseParts from an instance.
    Useful for building ignore lists.
    
    @param instance Instance - Root instance to search
    @return {Instance} - Array of parts found
]]
function Raycaster:GatherParts(instance)
    local list = {}
    if not instance then return list end
    
    local descendants = instance:GetDescendants()
    for i = 1, #descendants do
        local child = descendants[i]
        if BASE_PART_CLASSES[child.ClassName] then
            list[#list + 1] = child
        end
    end
    return list
end

--[[
    Forces the spatial cache to rebuild immediately.
    Call this after world geometry changes significantly.
]]
function Raycaster:RefreshCache()
    buildCache()
end

--[[
    Sets the spatial grid cell size in studs.
    Larger = faster cache build, better for long-range/sparse maps.
    Smaller = slower cache build, faster raycasts in dense areas.
    Default: 64
    
    @param size number - Cell size in studs (recommended: 32-256)
]]
function Raycaster:SetGridSize(size)
    GRID_SIZE = math.max(1, size)
    Cache.entries = {}
    Cache.grid = {}
end

--[[
    Sets how often the cache automatically rebuilds (in seconds).
    Set to 0 to disable auto-refresh (use RefreshCache() manually).
    Default: 10
    
    @param seconds number - Refresh interval in seconds
]]
function Raycaster:SetCacheRefreshRate(seconds)
    CACHE_REFRESH_RATE = math.max(0, seconds)
end

--[[
    Sets a global default maximum ray distance applied to all raycasts.
    Individual raycasts can override this by passing their own maxDistance.
    Internally capped at 100,000 studs for performance safety.
    Default: math.huge (no global limit)
    
    @param distance number - Default max ray distance in studs
]]
function Raycaster:SetDefaultMaxDistance(distance)
    DEFAULT_MAX_DISTANCE = math.max(0, distance)
end

return Raycaster