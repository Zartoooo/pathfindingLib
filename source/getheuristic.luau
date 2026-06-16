-- useless to make a whole file for that

-- returns the lenght between the start end the end
return function(Start: Vector2, End: Vector2)
    local v = Start - End;
    return v.x*v.x + v.y*v.y + v.z*v.z;
end