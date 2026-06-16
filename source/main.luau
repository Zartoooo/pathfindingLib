--[[
    Pathfinder:Pathfind(from: Vector3, to: Vector3, optimize_path: boolean?)
    
    optimize_path makes shortcuts in the generated path to make the lenght of the path shorter,
    it does NOT optimize the execution time itself
]]--


local Pathfinder = {}

local GetHeuristic = require("./getheuristic")
local Node = require("./node")

local function ReconstructPath(node)
    local path = {}

    while node do
        table.insert(path, 1, node.Position)
        node = node.Parent
    end

    return path
end

function Pathfinder:Pathfind(from: Vector3, to: Vector3, optimize_path: boolean?)
    local start = Node.new(from)
    local goal = Node.new(to)

    start.G = 0
    start.H = GetHeuristic(from, to)
    start.F = start.G + start.H

    local open_nodes = { start }
    local closed_nodes = {}

    local function InList(list, node)
        return table.find(list, node) ~= nil
    end

    local function GetLowestFCost()
        local best = open_nodes[1]

        for i = 2, #open_nodes do
            local node = open_nodes[i]

            if node.F < best.F then
                best = node
            elseif node.F == best.F and node.H < best.H then
                best = node
            end
        end

        return best
    end

    while #open_nodes > 0 do
        local current = GetLowestFCost()

        table.remove(open_nodes, table.find(open_nodes, current))
        table.insert(closed_nodes, current)

        if current.Position == goal.Position then
            local path = ReconstructPath(current)

            if optimize_path then
                -- TODO
            end

            return path
        end

        for _, neighbor in current:GetNeighbors() do
            if InList(closed_nodes, neighbor) then
                continue
            end

            local tentativeG =
                current.G +
                GetHeuristic(current.Position, neighbor.Position)

            local inOpen = InList(open_nodes, neighbor)

            if not inOpen or tentativeG < neighbor.G then
                neighbor.Parent = current
                neighbor.G = tentativeG
                neighbor.H = GetHeuristic(
                    neighbor.Position,
                    goal.Position
                )
                neighbor.F = neighbor.G + neighbor.H

                if not inOpen then
                    table.insert(open_nodes, neighbor)
                end
            end
        end
    end

    return nil -- no path found
end

return Pathfinder